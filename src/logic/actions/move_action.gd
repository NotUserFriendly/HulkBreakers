class_name MoveAction
extends CombatAction

## A full path (inclusive of the unit's current cell). Movement spends MP per
## tile; when MP runs short the unit burns 1 AP for +mp_per_ap MP, repeating
## while AP remains (Appendix E). Fails (is_legal == false) if AP runs out
## before the path completes.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


func is_legal(state: CombatState) -> bool:
	if not unit.alive:
		return false
	if state.current_unit() != unit:
		return false
	if path.size() < 2 or path[0] != unit.cell:
		return false

	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var sim_ap: int = unit.ap
	var sim_mp: float = unit.mp
	var per_ap: float = unit.mp_per_ap()

	for i in range(1, path.size()):
		if Grid.distance_chebyshev(path[i - 1], path[i]) != 1:
			return false
		var step_cost: float = pf.move_cost(path[i])
		if step_cost < 0.0:
			return false
		while sim_mp < step_cost:
			if sim_ap <= 0:
				return false
			sim_ap -= 1
			sim_mp += per_ap
		sim_mp -= step_cost

	return true


func apply(state: CombatState) -> void:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var per_ap: float = unit.mp_per_ap()

	for i in range(1, path.size()):
		var step_cost: float = pf.move_cost(path[i])
		while unit.mp < step_cost:
			unit.ap -= 1
			unit.mp += per_ap
		unit.mp -= step_cost
		state.grid.set_occupant_id(unit.cell, -1)
		unit.cell = path[i]
		state.grid.set_occupant_id(unit.cell, unit.id)

	state.log_action("MoveAction: unit %d moved to %s" % [unit.id, unit.cell])


func describe() -> String:
	return "MoveAction(unit=%d, path=%s)" % [unit.id, path]
