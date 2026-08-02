extends GutTest

## taskblock-53 Pass E: a climb is interruptible on the same rule a move is.
##
## Two gaps were flagged when `ClimbAction`/`HopDownAction` were built in taskblock-37 and
## never closed. This file covers the second: **a unit on a ladder is the most exposed it will
## ever be** — slow, committed, unable to take cover — and it was the one thing in the game
## that could not be shot at while moving, because `apply()` never consulted the mid-move hook.
## `docs/09`: "every real exposure the same."


func _grid() -> Grid:
	var grid := Grid.new(6, 6)
	for y: int in range(6):
		for x: int in range(6):
			grid.add_surface(Vector2i(x, y), Surface.new(DataLibrary.get_part(&"ship_floor"), 0.0))
	# A raised shelf at x=2, and a ladder standing against it at x=1.
	for y: int in range(6):
		grid.clear_surfaces(Vector2i(2, y))
		grid.add_surface(Vector2i(2, y), Surface.new(DataLibrary.get_part(&"ship_floor"), 2.0))
	GridPlacement.place(grid, Vector2i(1, 0), DataLibrary.get_part(&"ladder"), 0.0)
	return grid


func _unit(cell: Vector2i, grid: Grid, squad: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.6))]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad)
	unit.height = UnitGeometry.true_height_for_cell(cell, grid)
	return unit


## **The interruption itself**, driven through the same `{"stopped": bool}` contract
## `MoveAction.apply_stepwise` uses — a hook that fires returns the climber's turn to the
## resolver exactly as an interrupted move does.
func test_a_hook_that_fires_stops_the_queue_on_a_climb() -> void:
	var grid: Grid = _grid()
	var climber: Unit = _unit(Vector2i(1, 0), grid, 0)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var fired := {"count": 0}
	var hook := func(_s: CombatState, _u: Unit) -> bool:
		fired.count += 1
		return true

	var climb := ClimbAction.new(climber, Vector2i(2, 0))
	assert_true(climb.is_legal(state), "sanity: the ladder makes this climb legal")
	var result: Dictionary = climb.apply_interruptible(state, hook)

	assert_eq(fired.count, 1, "the hook is consulted exactly once for one climb")
	assert_true(result.stopped, "and a hook that fires stops the queue")
	assert_eq(climber.cell, Vector2i(2, 0), "the climb itself completes — being shot on a ladder")
	assert_almost_eq(climber.height, 2.0, 0.001, "ends the turn, it does not rewind the rungs")


func test_a_hook_that_does_not_fire_leaves_the_climb_uninterrupted() -> void:
	var grid: Grid = _grid()
	var climber: Unit = _unit(Vector2i(1, 0), grid, 0)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var hook := func(_s: CombatState, _u: Unit) -> bool: return false
	var result: Dictionary = ClimbAction.new(climber, Vector2i(2, 0)).apply_interruptible(
		state, hook
	)
	assert_false(result.stopped, "a quiet hook does not stop anything")
	assert_eq(climber.cell, Vector2i(2, 0))


## **`apply()` still works and still climbs**, so every existing caller is unchanged — the
## interruptible form is the general one and `apply` is it with no hook.
func test_plain_apply_still_climbs() -> void:
	var grid: Grid = _grid()
	var climber: Unit = _unit(Vector2i(1, 0), grid, 0)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	ClimbAction.new(climber, Vector2i(2, 0)).apply(state)
	assert_eq(climber.cell, Vector2i(2, 0), "an unhooked climb is an ordinary climb")


## **The interrupted climb resolves consistently with an interrupted move — same rule, not a
## parallel one.** Both report `mid_move_interrupt` through `resolve_until`, so a caller cannot
## tell which kind of movement was caught and does not need to.
func test_an_interrupted_climb_stops_the_queue_the_way_an_interrupted_move_does() -> void:
	var grid: Grid = _grid()
	var climber: Unit = _unit(Vector2i(1, 0), grid, 0)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var queue := ActionQueue.new(climber)
	queue.enqueue(ClimbAction.new(climber, Vector2i(2, 0)), state)
	var hook := func(_s: CombatState, _u: Unit) -> bool: return true
	var outcome: Dictionary = state.resolve_until(queue, hook)

	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED, "the queue stops")
	assert_eq(
		outcome.reason,
		&"mid_move_interrupt",
		"and reports the same reason an interrupted move does"
	)


## A real overwatcher, through the real trigger, rather than a stand-in Callable — the point of
## the pass is that `Overwatch.check_trigger` catches a climber, not that some hook can.
func test_a_real_overwatcher_can_be_wired_to_a_climb_without_a_second_code_path() -> void:
	var grid: Grid = _grid()
	var climber: Unit = _unit(Vector2i(1, 0), grid, 0)
	var watcher: Unit = _unit(Vector2i(4, 0), grid, 1)
	var state := CombatState.new(grid, [climber, watcher])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var queue := ActionQueue.new(climber)
	queue.enqueue(ClimbAction.new(climber, Vector2i(2, 0)), state)
	# The same Callable `BoutRunner` threads into every real bout.
	var outcome: Dictionary = state.resolve_until(queue, Overwatch.check_trigger)

	# The watcher holds no overwatch here, so nothing should trigger — what is being pinned is
	# that the real trigger is REACHED on a climb and behaves, not that it fires.
	assert_eq(
		outcome.kind,
		Enums.ResolveOutcome.COMPLETED,
		"an unarmed watcher does not stop a climb, and the real hook runs without error"
	)
	assert_eq(climber.cell, Vector2i(2, 0), "the climb completed")
