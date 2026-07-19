class_name HoldAction
extends CombatAction

## taskblock-19 Pass F: "a unit with nowhere useful to go can wait — take
## its turn after the next ally instead." An alternative to EndTurnAction
## for the CURRENT unit's own turn, not a stop condition of its own —
## `CombatState.begin_hold()` owns the actual "resume after one more unit
## acts" bookkeeping (`_held_unit_id`/`_hold_ready`), mirroring
## EndTurnAction's own "the real logic lives on CombatState, this is just
## the queued entry point" shape.

var unit: Unit


func _init(p_unit: Unit) -> void:
	unit = p_unit


## Only legal for the CURRENT, living unit, AND only when some other
## living unit actually exists to be "the next ally" — holding with
## nobody else on the board would either stall (nothing to defer to) or,
## worse, silently re-select the SAME unit under `begin_hold`'s own
## resume bookkeeping, corrupting the next real hold. "Ally" in the
## taskblock's own prose is flavor, not a squad restriction — the
## mechanic just needs SOME next unit in initiative order, same as the
## AI section's own framing ("wait for an ally to move first") is a
## reason to hold, not a legality requirement on WHO's next.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	for other: Unit in state.units:
		if other != actual and other.alive:
			return true
	return false


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var text: String = "HoldAction: unit %d holds, deferring to the next ally" % actual.id
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(state.round_number, Enums.Phase.RESOLUTION, actual.id, &"held", {}, text)
		)
	state.begin_hold(actual)


func describe() -> String:
	return "HoldAction(unit=%d)" % unit.id
