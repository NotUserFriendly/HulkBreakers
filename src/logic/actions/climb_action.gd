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
	if Surface.is_ramp_at(state.grid, target_cell):
		return false
	var pf := Pathfinder.new(state.grid)
	if not pf.is_walkable(target_cell):
		return false
	# taskblock-53 Pass C4: **a ladder is a second source of legality for an action
	# that already exists** — `can_climb() or ladder_present`. No new action, no new
	# cost model. The point of the block is that maps must be navigable by a unit
	# with no climbing capability, so the ladder is what a plain shell uses.
	var on_ladder: bool = Surface.ladder_serves_climb(state.grid, actual.cell, target_cell)
	if not actual.shell.can_climb() and not on_ladder:
		return false
	var rise: float = _rise(state, actual)
	if rise <= 0.0:
		return false
	# **A ladder replaces the rise cap with its own reach, rather than raising it.**
	# `MAX_CLIMB_LEVELS` exists because a bare face is only climbable so far; a ladder
	# removes that limit by construction, and `ladder_serves_climb` has already
	# checked the destination is within the ladder's actual height. Keeping the cap
	# here as well would make a three-segment ladder unusable, which is the exact
	# thing "tileable to arbitrary height" is for.
	if not on_ladder and rise > Pathfinder.MAX_CLIMB_LEVELS * UnitGeometry.LEVEL_HEIGHT + 0.001:
		return false
	return _can_afford(actual, _cost(rise, on_ladder))


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var origin_cell: Vector2i = actual.cell
	var rise: float = _rise(state, actual)
	# The same discount `is_legal` cleared the climb against. Charging full price here
	# would let a unit be told a climb was affordable and then be unable to pay for it.
	var cost: float = _cost(rise, Surface.ladder_serves_climb(state.grid, origin_cell, target_cell))
	var per_ap: float = actual.mp_per_ap()
	while actual.mp < cost:
		actual.ap -= 1
		actual.mp += per_ap
	actual.mp -= cost

	state.grid.set_occupant_id(actual.cell, -1)
	actual.cell = target_cell
	state.grid.set_occupant_id(actual.cell, actual.id)
	actual.height = UnitGeometry.true_height_for_cell(actual.cell, state.grid)
	actual.level = actual.height / UnitGeometry.LEVEL_HEIGHT

	FaceAction.face_for_free(
		state, actual, FaceAction.orientation_toward(origin_cell, target_cell), &"free_with_move"
	)
	_log(state, actual, origin_cell, rise, cost)


func _rise(state: CombatState, actual: Unit) -> float:
	return UnitGeometry.true_height_for_cell(target_cell, state.grid) - actual.height


## taskblock-53 Pass C4: **the action charges what `Pathfinder.move_cost` quotes.** A
## ladder edge is discounted there, and an action that ignored the discount would refuse
## climbs the planner had already costed and committed to — the planner's idea of an edge
## and the action's must be one formula, which is why `LADDER_COST_SCALE` is read here
## rather than duplicated.
func _cost(rise: float, on_ladder: bool = false) -> float:
	var climb: float = Pathfinder.CLIMB_COST * (rise / UnitGeometry.LEVEL_HEIGHT)
	return climb * Pathfinder.LADDER_COST_SCALE if on_ladder else climb


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
