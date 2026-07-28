class_name EngineErrorTap
extends Logger

## taskblock-41 Pass B: engine and script errors land on the SAME combat-log
## stream as combat events — "conflated on purpose, separable on demand"
## (docs/09's own one-stream-many-sinks rule, extended past events the game
## itself emits). A crash log that lives beside the shot that preceded it is
## worth more than either half alone.
##
## Direction is the opposite of a `LogSink`, despite the taskblock's shorthand:
## a sink CONSUMES the stream, this PRODUCES onto it. It is a real Godot
## `Logger` registered with `OS.add_logger`, so it sees what the engine sees.
##
## ## The reachable set — observed, not assumed
## Verified empirically against Godot 4.7 headless before this was written
## (a throwaway `Logger` subclass, one probe per case):
##
## | Source | Reached? | `error_type` |
## |---|---|---|
## | `push_error` | **yes** | `ERROR_TYPE_ERROR` |
## | `push_warning` | **yes** | `ERROR_TYPE_WARNING` |
## | **GDScript runtime errors** (null deref, bad index) | **yes** | `ERROR_TYPE_SCRIPT` |
## | Engine-internal C++ `ERR_FAIL_*` | **yes** | `ERROR_TYPE_ERROR` |
## | Shader compile failures | expected | `ERROR_TYPE_SHADER` |
## | **A hard crash (segfault, OOM, abort)** | **NO** | — |
## | Anything before `install()` runs | **NO** | — |
##
## The GDScript runtime-error case is the valuable one and was not a given:
## the callback carries the REAL script file and line (`some_script.gd:412`), so a
## null deref mid-resolution lands in the log next to the event before it.
##
## **A segfault is not reachable and never will be from in-process GDScript** —
## the process is gone before any sink flushes. Catching that needs an external
## wrapper around the engine (a shell runner tee-ing stdout, or a core-dump
## handler); `FileSink` already flushes per line, so everything logged up to
## the instant of death does survive on disk. Do not let this class's coverage
## imply otherwise.
##
## **One engine failure can produce several callbacks.** A single missing
## resource produced three (`resource_format_text.cpp` → `resource_loader.cpp`
## → `core_bind.cpp`) as the C++ error chain unwound. That is faithfully
## reported as three diagnostics rather than deduplicated — collapsing them
## would need a policy nobody has specified, and the unwind chain is itself
## information. Flagged as a tunable if the volume proves annoying.

## Mapped from `Logger.ErrorType`, which IS a closed engine enum — the
## StringName the log carries is the open half (CLAUDE.md: enums for engine
## states, open vocabularies for content).
const SEVERITY_BY_ERROR_TYPE: Dictionary = {
	Logger.ERROR_TYPE_ERROR: &"error",
	Logger.ERROR_TYPE_WARNING: &"warning",
	Logger.ERROR_TYPE_SCRIPT: &"script",
	Logger.ERROR_TYPE_SHADER: &"shader",
}
const UNKNOWN_SEVERITY: StringName = &"unknown"

## `OS.add_logger` is process-global, so this is deliberately ONE instance
## re-pointed at whichever battle is current, never one per `BattleScene`.
## A per-scene tap would accumulate across a session (and across a test run)
## until every engine error fanned out into every stale battle's own log.
static var _shared: EngineErrorTap = null

## Where captured diagnostics go. Null (the default, and the state after a
## battle is torn down) makes this a silent no-op rather than an error —
## an error hook that errors is worse than no error hook.
var combat_log: CombatLog = null
## Optional, purely for stamping `turn`/`phase`/`unit_id` so a diagnostic is
## greppable against the combat events around it. Never required.
var state: CombatState = null

var _installed := false
## Re-entrancy guard. Emitting a diagnostic runs real sink code — `FileSink`
## writes a file, `StdoutSink` prints, `HierarchicalUiSink` folds — and any of
## that can itself raise an error, which would re-enter here forever. A
## dropped nested diagnostic is a far better failure than a stack overflow.
var _emitting := false


## The one shared tap. Creates it on first call; does NOT install it — a
## caller that wants engine errors on its stream says so explicitly.
static func shared() -> EngineErrorTap:
	if _shared == null:
		_shared = EngineErrorTap.new()
	return _shared


## Idempotent: registering the same `Logger` twice would double every
## captured error.
func install() -> void:
	if _installed:
		return
	OS.add_logger(self)
	_installed = true


func uninstall() -> void:
	if not _installed:
		return
	OS.remove_logger(self)
	_installed = false


func is_installed() -> bool:
	return _installed


## Points this tap at a battle. `p_state` is optional context for stamping
## only — a null state still logs, just without turn/phase/unit.
func watch(p_combat_log: CombatLog, p_state: CombatState = null) -> void:
	combat_log = p_combat_log
	state = p_state


func stop_watching() -> void:
	combat_log = null
	state = null


## Godot's own callback. Deliberately delegates immediately to `report()` so
## every mapping decision is testable without touching `OS.add_logger` at all
## — a global logger installed by a unit test would capture every OTHER
## test's engine errors too.
func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array
) -> void:
	report(error_type, function, file, line, code, rationale)


## `_log_message` is deliberately NOT overridden. `print()` routes through it,
## and `StdoutSink` prints every event it receives — capturing messages would
## turn one diagnostic into an unbounded print/emit loop. Errors only.
func report(
	error_type: int, function: String, file: String, line: int, code: String, rationale: String
) -> void:
	if combat_log == null or _emitting:
		return
	_emitting = true
	combat_log.emit(build_event(error_type, function, file, line, code, rationale))
	_emitting = false


## Split out from `report()` so the event's own shape is assertable with no
## `CombatLog` at all.
func build_event(
	error_type: int, function: String, file: String, line: int, code: String, rationale: String
) -> LogEvent:
	var severity: StringName = SEVERITY_BY_ERROR_TYPE.get(error_type, UNKNOWN_SEVERITY)
	# `push_error` puts its message in `code` and leaves `rationale` empty;
	# an engine `ERR_FAIL_COND_MSG` puts the failed condition in `code` and
	# the human-readable part in `rationale`. Prefer the human half when
	# there is one, and never drop the other — both go in `data`.
	var message: String = rationale if rationale != "" else code
	var current: Unit = state.current_unit() if state != null else null
	return (
		LogEvent
		. new(
			state.round_number if state != null else 0,
			_phase(),
			current.id if current != null else -1,
			LogEvent.DIAGNOSTIC_KIND,
			{
				"severity": severity,
				"function": function,
				"file": file,
				"line": line,
				"code": code,
				"rationale": rationale,
			},
			"[%s] %s (%s:%d in %s)" % [severity, message, file.get_file(), line, function]
		)
	)


func _phase() -> Enums.Phase:
	if state != null and state.is_resolving:
		return Enums.Phase.RESOLUTION
	return Enums.Phase.TACTICS
