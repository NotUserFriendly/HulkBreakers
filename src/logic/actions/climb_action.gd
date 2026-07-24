class_name ClimbAction
extends CombatAction

## taskblock-37 Pass D: "climb-up... via leading-edge detection against the
## target cell's level" (docs/PLAN.md) — a discrete, deliberate single-cell
## action, distinct from ordinary `MoveAction` the same way `FaceAction`'s
## manual face is distinct from a move's own free re-facing. Capability-
## gated (`Shell.can_climb()`); capped at one full level's worth of real
## rise, at the settled cost (4 MP per full level, 2 MP per half — the
## HALF case is a real climb launched from a `RAMP` tile the mover is
## already resting on, `UnitGeometry.true_height_for_cell`'s own +0.5
## offset, not a whole-level ledge).
##
## The target cell itself must NOT be a ramp — stepping ONTO a ramp is
## always ordinary movement (`Pathfinder`'s own "no special-casing" rule),
## never this action; the mover's OWN cell being a ramp is exactly what
## makes the half-level case possible, and is fine.

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
	if not actual.shell.can_climb():
		return false
	var rise: float = _rise(state, actual)
	if rise <= 0.0 or rise > Pathfinder.MAX_CLIMB_LEVELS * UnitGeometry.LEVEL_HEIGHT + 0.001:
		return false
	return _can_afford(actual, _cost(rise))


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var origin_cell: Vector2i = actual.cell
	var rise: float = _rise(state, actual)
	var cost: float = _cost(rise)
	var per_ap: float = actual.mp_per_ap()
	while actual.mp < cost:
		actual.ap -= 1
		actual.mp += per_ap
	actual.mp -= cost

	state.grid.set_occupant_id(actual.cell, -1)
	actual.cell = target_cell
	state.grid.set_occupant_id(actual.cell, actual.id)
	actual.level = state.grid.get_level(actual.cell)
	actual.height = UnitGeometry.true_height_for_cell(actual.cell, state.grid)

	FaceAction.face_for_free(
		state, actual, FaceAction.orientation_toward(origin_cell, target_cell), &"free_with_move"
	)
	_log(state, actual, origin_cell, rise, cost)


func _rise(state: CombatState, actual: Unit) -> float:
	return UnitGeometry.true_height_for_cell(target_cell, state.grid) - actual.height


func _cost(rise: float) -> float:
	return Pathfinder.CLIMB_COST * (rise / UnitGeometry.LEVEL_HEIGHT)


func _can_afford(actual: Unit, cost: float) -> bool:
	var sim_ap: int = actual.ap
	var sim_mp: float = actual.mp
	var per_ap: float = actual.mp_per_ap()
	while sim_mp < cost:
		if sim_ap <= 0:
			return false
		sim_ap -= 1
		sim_mp += per_ap
	return true


func _log(
	state: CombatState, actual: Unit, origin_cell: Vector2i, rise: float, cost: float
) -> void:
	var text: String = (
		"ClimbAction: unit %d climbed to %s (rise %.2f, cost %.1f MP)"
		% [actual.id, target_cell, rise, cost]
	)
	state.log_action(text)
	if state.is_preview:
		return
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					actual.id,
					&"climbed",
					# taskblock-37 Pass E: `path`, the same shape a `move` event
					# carries — ResolutionPlayer's own slide playback reads this
					# generically, so a climb plays as a real vertical slide with
					# no dedicated animation code at all.
					{
						"cell": target_cell,
						"rise": rise,
						"cost": cost,
						"path": [origin_cell, target_cell] as Array[Vector2i]
					},
					(
						"unit %d climbed to %s (rise %.2f, cost %.1f MP)"
						% [actual.id, target_cell, rise, cost]
					)
				)
			)
		)
	)


func describe() -> String:
	return "ClimbAction(unit=%d, target=%s)" % [unit.id, target_cell]


func speed(_state: CombatState) -> float:
	return SPEED


func unit_id() -> int:
	return unit.id
