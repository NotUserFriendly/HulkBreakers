class_name BoutInjector
extends RefCounted

## taskblock-29: the debug scalpel — a single, explicit entry point for
## mutating a LIVE `CombatState` from outside the turn loop, so CC (or the
## supervisor) can force a specific scenario into a running bout and watch
## it instead of waiting for one to occur naturally. `src/debug/`, not
## `src/logic/` (CLAUDE.md: "Debug = ASCII renderers, your eyes" — this is
## the same tier, a tool that inspects/mutates for a human's benefit, not
## game logic itself), view-agnostic but never reachable from a real
## player-controlled bout (Pass C/D: `SpectatorOverlay` is the only view
## that ever constructs one).
##
## **The core constraint: injection is a deliberate determinism break.**
## Every verb goes through ONE gate (`_guard`): reject outright if
## `state.is_resolving` (a mutation mid-`resolve_until` is forbidden, the
## same two-phase-turn discipline docs/09 already states, applied here);
## otherwise mark `state.was_injected` and log a distinct `&"inject"`
## event BEFORE doing anything else, naming exactly what's about to
## happen — so a bug found under injection is traceable to the injection
## that set it up, and a rejected call is a true no-op (nothing mutated,
## no log entry, no RNG draw).
##
## **No parallel systems.** Every verb below is a thin call into the real
## mutation path it fronts (`DeepStrike`/`BodyAssembler`, `KitEquipper`,
## `PartGraph`, `WoundEffects`, `CombatState.try_apply`) — injection
## INVOKES the real logic, it never reimplements it.

var state: CombatState


func _init(p_state: CombatState) -> void:
	state = p_state


## True iff a verb may mutate right now — never mid-resolution.
func can_inject() -> bool:
	return not state.is_resolving


func _reject(kind: StringName) -> void:
	push_error("BoutInjector: %s rejected — injection mid-resolution is forbidden" % kind)


## Every successful verb's own tail call: marks the bout non-deterministic
## for good and logs the `&"inject"` event. `unit_id` -1 — the same
## "no specific unit caused this" convention cover/terrain impacts already
## use (`ShotResolution`) — since an injection isn't attributed to any
## unit's own turn.
func _log_injection(kind: StringName, data: Dictionary, text: String) -> void:
	state.was_injected = true
	var full_data: Dictionary = data.duplicate()
	full_data["verb"] = kind
	state.combat_log.emit(
		LogEvent.new(state.round_number, Enums.Phase.RESOLUTION, -1, &"inject", full_data, text)
	)


## Forces whose turn it is — `CombatState.force_current_unit`, which
## (deliberately, see its own doc comment) never resets AP/MP/facing the
## way a real `_begin_turn` would; a scenario that wants a fresh turn too
## should follow this with a real `set_ap`/`set_mp` call (Pass B), not get
## one silently bundled in.
func force_current_unit(unit: Unit) -> bool:
	if not can_inject():
		_reject(&"force_current_unit")
		return false
	state.force_current_unit(unit.id)
	_log_injection(
		&"force_current_unit", {"unit": unit.id}, "unit %d forced current" % unit.id
	)
	return true
