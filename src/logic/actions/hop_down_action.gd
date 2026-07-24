class_name HopDownAction
extends CombatAction

## taskblock-37 Pass D: "hop-down... via leading-edge detection against the
## target cell's level" (docs/PLAN.md) — the mirror of `ClimbAction`, but
## with none of its gating: no capability needed, flat cost regardless of
## how much of its 2-level allowance it actually uses. Deliberately
## discrete-level based (not `Unit.height`/ramp-aware like `ClimbAction`'s
## own half-cost case) — the taskblock's own settled table gives hop-down
## no "half" variant, only "1 MP, safe up to 2 levels."
##
## The target cell must NOT be a ramp — stepping ONTO a ramp is always
## ordinary movement (`Pathfinder`'s own rule), never this action.

const SPEED := 40.0

var unit: Unit
var target_cell: Vector2i


func _init(p_unit: Unit, p_target_cell: Vector2i) -> void:
	unit = p_unit
	target_cell = p_target_cell


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if Grid.distance_chebyshev(actual.cell, target_cell) != 1:
		return false
	if state.grid.get_terrain(target_cell) == Enums.TerrainType.RAMP:
		return false
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	if not pf.is_walkable(target_cell):
		return false
	var drop_levels: int = actual.level - state.grid.get_level(target_cell)
	if drop_levels <= 0 or drop_levels > Pathfinder.MAX_HOP_DOWN_LEVELS:
		return false
	return _can_afford(actual)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var origin_cell: Vector2i = actual.cell
	var per_ap: float = actual.mp_per_ap()
	while actual.mp < Pathfinder.HOP_DOWN_COST:
		actual.ap -= 1
		actual.mp += per_ap
	actual.mp -= Pathfinder.HOP_DOWN_COST

	state.grid.set_occupant_id(actual.cell, -1)
	actual.cell = target_cell
	state.grid.set_occupant_id(actual.cell, actual.id)
	actual.level = state.grid.get_level(actual.cell)
	actual.height = UnitGeometry.true_height_for_cell(actual.cell, state.grid)

	FaceAction.face_for_free(
		state, actual, FaceAction.orientation_toward(origin_cell, target_cell), &"free_with_move"
	)
	_log(state, actual)


func _can_afford(actual: Unit) -> bool:
	var sim_ap: int = actual.ap
	var sim_mp: float = actual.mp
	var per_ap: float = actual.mp_per_ap()
	while sim_mp < Pathfinder.HOP_DOWN_COST:
		if sim_ap <= 0:
			return false
		sim_ap -= 1
		sim_mp += per_ap
	return true


func _log(state: CombatState, actual: Unit) -> void:
	var text: String = "HopDownAction: unit %d hopped down to %s" % [actual.id, target_cell]
	state.log_action(text)
	if state.is_preview:
		return
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			actual.id,
			&"hopped_down",
			{"cell": target_cell, "cost": Pathfinder.HOP_DOWN_COST},
			"unit %d hopped down to %s" % [actual.id, target_cell]
		)
	)


func describe() -> String:
	return "HopDownAction(unit=%d, target=%s)" % [unit.id, target_cell]


func speed(_state: CombatState) -> float:
	return SPEED


func unit_id() -> int:
	return unit.id
