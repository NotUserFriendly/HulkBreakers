class_name EndTurnAction
extends CombatAction

var unit: Unit


func _init(p_unit: Unit) -> void:
	unit = p_unit


func is_legal(state: CombatState) -> bool:
	return unit.alive and state.current_unit() == unit


func apply(state: CombatState) -> void:
	state.log_action("EndTurnAction: unit %d ended turn" % unit.id)
	state.advance_turn()


func describe() -> String:
	return "EndTurnAction(unit=%d)" % unit.id
