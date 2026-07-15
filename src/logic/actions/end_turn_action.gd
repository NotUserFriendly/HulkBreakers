class_name EndTurnAction
extends CombatAction

var unit: Unit


func _init(p_unit: Unit) -> void:
	unit = p_unit


## Resolved through state.find_unit(), not the stored reference directly
## (docs/09): a preview's units are independent clones sharing `unit.id`.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	return actual != null and actual.alive and state.current_unit() == actual


func apply(state: CombatState) -> void:
	state.log_action("EndTurnAction: unit %d ended turn" % unit.id)
	state.advance_turn()


func describe() -> String:
	return "EndTurnAction(unit=%d)" % unit.id
