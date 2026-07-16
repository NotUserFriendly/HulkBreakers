extends GutTest

## docs/09: TACTICS queues intents against a speculative preview and mutates
## nothing; RESOLUTION replays the whole queue for real. These tests use the
## existing Move/EndTurn actions to prove the queue mechanism itself — the
## probabilistic abort-and-continue case (a queued attack whose target dies
## earlier in the same resolution) lives in test_attack_action.gd, since it
## needs a real attack to demonstrate.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_enqueue_validates_but_never_mutates_the_real_state() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var queue := ActionQueue.new(unit)

	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	assert_true(queue.enqueue(MoveAction.new(unit, path), state))

	assert_eq(unit.cell, Vector2i(0, 0), "the real unit must not have moved")
	assert_eq(unit.ap, unit.max_ap, "the real unit's AP must be untouched")
	assert_eq(state.grid.get_occupant_id(Vector2i(1, 0)), -1, "the real grid must be untouched")


func test_enqueue_previews_against_already_queued_actions_not_just_the_real_state() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var queue := ActionQueue.new(unit)

	# Only legal because the queue's own first move is replayed onto the
	# preview before this second one is checked — from the real state alone
	# (still at (0,0)), a path starting at (1,0) would be rejected outright.
	assert_true(queue.enqueue(MoveAction.new(unit, [Vector2i(0, 0), Vector2i(1, 0)]), state))
	assert_true(queue.enqueue(MoveAction.new(unit, [Vector2i(1, 0), Vector2i(2, 0)]), state))
	assert_eq(unit.cell, Vector2i(0, 0), "still untouched — this was only queuing")


func test_resolve_turn_applies_the_whole_queue_in_order() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(grid, [a, b])
	var queue := ActionQueue.new(a)

	assert_true(queue.enqueue(MoveAction.new(a, [Vector2i(0, 0), Vector2i(1, 0)]), state))
	assert_true(queue.enqueue(MoveAction.new(a, [Vector2i(1, 0), Vector2i(2, 0)]), state))
	assert_true(queue.enqueue(EndTurnAction.new(a), state))

	state.resolve_turn(queue)

	assert_eq(a.cell, Vector2i(2, 0), "resolution must actually move the real unit")
	assert_eq(state.grid.get_occupant_id(Vector2i(2, 0)), a.id)
	assert_eq(state.current_unit(), b, "the trailing EndTurnAction must have advanced the turn")


func test_resolve_turn_aborts_an_action_invalidated_by_an_earlier_one_and_keeps_going() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [a])
	var queue := ActionQueue.new(a)

	# Both moves are legal when queued in this order (each previews from
	# where the last one left off). Directly reversing the queue's own
	# action list afterward simulates "the world moved" without needing a
	# whole second unit: move_b's path assumes the unit already reached
	# (1,0), which is only true once move_a has actually run.
	var move_a := MoveAction.new(a, [Vector2i(0, 0), Vector2i(1, 0)])
	var move_b := MoveAction.new(a, [Vector2i(1, 0), Vector2i(2, 0)])
	assert_true(queue.enqueue(move_a, state))
	assert_true(queue.enqueue(move_b, state))
	queue.actions = [move_b, move_a]  # move_b now runs first, before the unit ever reaches (1,0)

	state.resolve_turn(queue)

	assert_eq(a.cell, Vector2i(1, 0), "move_b must have aborted; move_a ran instead and applied")
	var aborts: Array = state.action_log.filter(
		func(line: String) -> bool: return line.begins_with("aborted at resolution")
	)
	assert_eq(
		aborts.size(), 1, "exactly move_b must have aborted, not crashed: %s" % [state.action_log]
	)


func test_resolve_turn_replays_identically_from_the_same_seed() -> void:
	var grid_a := Grid.new(10, 10)
	var unit_a := _make_unit(Vector2i(0, 0))
	var state_a := CombatState.new(grid_a, [unit_a], 42)
	var queue_a := ActionQueue.new(unit_a)
	queue_a.enqueue(
		MoveAction.new(unit_a, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), state_a
	)
	state_a.resolve_turn(queue_a)

	var grid_b := Grid.new(10, 10)
	var unit_b := _make_unit(Vector2i(0, 0))
	var state_b := CombatState.new(grid_b, [unit_b], 42)
	var queue_b := ActionQueue.new(unit_b)
	queue_b.enqueue(
		MoveAction.new(unit_b, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]), state_b
	)
	state_b.resolve_turn(queue_b)

	assert_eq(unit_a.cell, unit_b.cell)
	assert_eq(unit_a.ap, unit_b.ap)
	assert_almost_eq(unit_a.mp, unit_b.mp, 0.0001)
