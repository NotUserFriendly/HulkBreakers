class_name ImplantAction
extends CombatAction

## Installs unit.held_matrix into target_chassis, spawning a new active Unit at
## target_cell mid-combat. Where target_chassis comes from (reserve stash vs.
## a chassis found on the field) is a Phase 10 concern — this action just
## needs an already-resolved empty chassis to implant into.

const AP_COST: int = 2

var unit: Unit
var target_chassis: Chassis
var target_cell: Vector2i
var squad_id: int


func _init(
	p_unit: Unit, p_target_chassis: Chassis, p_target_cell: Vector2i, p_squad_id: int = -1
) -> void:
	unit = p_unit
	target_chassis = p_target_chassis
	target_cell = p_target_cell
	squad_id = p_squad_id if p_squad_id != -1 else p_unit.squad_id


func is_legal(state: CombatState) -> bool:
	if not unit.alive:
		return false
	if state.current_unit() != unit:
		return false
	if unit.ap < AP_COST:
		return false
	if unit.held_matrix == null:
		return false
	if target_chassis == null:
		return false
	if not state.grid.in_bounds(target_cell):
		return false
	if state.grid.get_occupant_id(target_cell) != -1:
		return false
	return Grid.distance_chebyshev(unit.cell, target_cell) <= 1


func apply(state: CombatState) -> void:
	unit.ap -= AP_COST
	var matrix: Matrix = unit.held_matrix
	unit.held_matrix = null

	var new_unit := Unit.new(matrix, target_chassis, target_cell, squad_id)
	state.add_unit(new_unit)

	state.log_action(
		(
			"ImplantAction: unit %d implanted a matrix at %s (new unit %d)"
			% [unit.id, target_cell, new_unit.id]
		)
	)


func describe() -> String:
	return "ImplantAction(unit=%d, cell=%s)" % [unit.id, target_cell]
