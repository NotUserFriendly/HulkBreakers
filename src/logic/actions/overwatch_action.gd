class_name OverwatchAction
extends CombatAction

## docs/09 taskblock06 Pass F1: "declaring" overwatch. Costs 1 AP and ENDS
## the unit's turn (you're holding, not acting) — never queued alongside
## anything after it; requires a legal, functional weapon, same
## capability-matching check AttackAction's own is_legal() uses. The
## actual trigger (torso visible, in arc, in range — Pass F2) is a
## separate, later concern: Overwatch.check_trigger(), called as the
## mid_move_hook a queued MoveAction's own apply_stepwise() invokes at
## every cell step (docs/09 taskblock06 Pass D's own seam).

## Flagged starting data (docs/09 taskblock06 F1), not a tuned design
## number.
const AP_COST := 1

var unit: Unit
var weapon_id: StringName


func _init(p_unit: Unit, p_weapon_id: StringName) -> void:
	unit = p_unit
	weapon_id = p_weapon_id


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.ap < AP_COST:
		return false

	var weapon: Part = actual.shell.find_part(weapon_id)
	if weapon == null or weapon.hp <= 0:
		return false
	var manipulators: Array[Part] = []
	for part: Part in actual.shell.living_parts():
		if part != weapon:
			manipulators.append(part)
	return PartGraph.can_operate(weapon, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	actual.ap -= AP_COST
	actual.overwatch_weapon_id = weapon_id

	var text: String = "OverwatchAction: unit %d holding with %s" % [actual.id, weapon_id]
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"overwatch_declared",
				{"weapon": weapon_id},
				"holding with %s" % weapon_id
			)
		)

	# "Ends the unit's turn" (docs/09 taskblock06 F1) — the same turn
	# advance EndTurnAction itself performs, called unconditionally (even
	# during a TACTICS preview, matching EndTurnAction's own convention)
	# so a preview correctly shows that declaring overwatch ends the turn
	# right here.
	state.advance_turn()


func describe() -> String:
	return "OverwatchAction(unit=%d, weapon=%s)" % [unit.id, weapon_id]
