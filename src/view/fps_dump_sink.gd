class_name FpsDumpSink
extends LogSink

## tb35 Pass A1: "the reason BR26.02 has survived three passes is that CC
## cannot see a framerate, so every fix has been reasoned rather than
## measured." Watches the combat log for `&"turn_start"` and dumps
## `Engine.get_frames_per_second()` back into the SAME log, so "the game is
## slow" becomes a greppable number in `out/combat.log` instead of a felt
## impression.
##
## ## taskblock-42 Pass A: TWO dumps per turn, not one
## BR26.02's own 2026-07-23 supervisor revision, which had never been built.
## The single 200ms sample could not tell BR26.02 and BR27.09 apart, because
## it was deliberately positioned to miss the thing BR27.09 is about:
##
## - **`turn_boundary`, at 0ms** — the boundary cost ITSELF, sampled the
##   instant the turn starts. **This is the number BR27.09 is actually about,
##   and it did not previously exist at any offset.**
## - **`turn_settled`, at `SETTLED_DELAY_SECONDS`** — the honest steady-state
##   rate, moved out from 200ms because 200ms proved close enough to the
##   transient to still be contaminated by it.
##
## **Both, always.** Either alone conflates a boundary spike with a slow game;
## it is the PAIR that separates them, and a later pass that "tidies" this back
## to one sample deletes the only signal telling the two bugs apart.
##
## The aim-entry counterpart lives in `TacticsController._enter_aim_mode()`
## rather than here, since that trigger is not a combat-log event at all. It
## moves to the same settled delay; it gets no 0ms twin, because BR26.02's
## revision asked for the boundary sample on the TURN specifically. Add one if
## a boundary question ever arises for aim.

## Where the settled sample is taken. Two seconds rather than the original
## 200ms: the supervisor's own finding is that 200ms is not yet settled.
const SETTLED_DELAY_SECONDS := 2.0

## `data.context` values, so the two dumps are distinguishable by grep and by
## test without parsing prose. The old single value was `"turn"`, which is
## ambiguous by construction now that there are two turn dumps.
const CONTEXT_BOUNDARY: StringName = &"turn_boundary"
const CONTEXT_SETTLED: StringName = &"turn_settled"

var _host: Node
var _combat_log: CombatLog


func _init(host: Node, combat_log: CombatLog) -> void:
	_host = host
	_combat_log = combat_log


func emit(event: LogEvent) -> void:
	if event.kind != &"turn_start":
		return
	# **Emitted synchronously, deliberately.** `await create_timer(0.0)` or
	# `await process_frame` would push this a frame past the boundary — which is
	# precisely the transient it exists to catch, and would quietly make it a
	# second copy of the settled sample wearing a different label. The whole
	# value of this dump is that it happens BEFORE anything yields.
	_dump(event.turn, event.unit_id, CONTEXT_BOUNDARY, 0.0)
	_dump_after_delay(event.turn, event.unit_id)


func _dump_after_delay(turn: int, unit_id: int) -> void:
	await _host.get_tree().create_timer(SETTLED_DELAY_SECONDS).timeout
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	_dump(turn, unit_id, CONTEXT_SETTLED, SETTLED_DELAY_SECONDS)


## taskblock-44 Pass A: the dump carries `BuildIdentity` alongside the number.
## A framerate is meaningless without knowing whether it came from a tools binary
## or an exported release build, and this sink is the one instrument whose output
## a supervisor reads directly out of `out/combat.log` — so the provenance has to
## ride in the event rather than being something a reader is expected to recall.
## Merged into `data` (machine-readable, the same convention `offset_ms` follows)
## and left out of the prose line, which stays short enough to skim.
func _dump(turn: int, unit_id: int, context: StringName, offset_seconds: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	var offset_ms: int = int(offset_seconds * 1000.0)
	var when: String = "at turn start" if offset_ms <= 0 else "%dms after turn start" % offset_ms
	var data: Dictionary = {"context": context, "fps": fps, "offset_ms": offset_ms}
	data.merge(BuildIdentity.as_data())
	_combat_log.emit(
		LogEvent.new(
			turn,
			Enums.Phase.RESOLUTION,
			unit_id,
			&"fps_dump",
			data,
			"Turn FPS (%s): %.1f" % [when, fps]
		)
	)
