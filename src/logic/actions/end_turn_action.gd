class_name EndTurnAction
extends CombatAction

var unit: Unit


func _init(p_unit: Unit) -> void:
	unit = p_unit


## Resolved through state.find_unit(), not the stored reference directly
## (docs/09): a preview's units are independent clones sharing `unit.id`.
## Deliberately does NOT require `actual.alive`: a unit can die mid-turn from
## its own queued action (e.g. cook-off, or a shot that reaches its own
## body), and turn order only ever advances via this action's apply() — if
## ending a dead unit's own turn were illegal, the engine would never call
## advance_turn() again and every subsequent turn would stall on a corpse.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	return actual != null and state.current_unit() == actual


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var text: String = "EndTurnAction: unit %d ended turn" % unit.id
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number, Enums.Phase.RESOLUTION, actual.id, &"turn_end", {}, "ended turn"
			)
		)
	state.advance_turn()


func describe() -> String:
	return "EndTurnAction(unit=%d)" % unit.id
