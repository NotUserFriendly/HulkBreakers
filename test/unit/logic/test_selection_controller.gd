extends GutTest

## docs/10 Phase 12.2: SelectionController is the pure TACTICS-time layer —
## nothing it does may mutate the authoritative CombatState. Two units on an
## open 10x10 grid, matching test_action_queue.gd's fixture style.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_select_accepts_only_the_current_units_turn() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var selection := SelectionController.new(state)

	selection.select(a)
	assert_eq(selection.selected_unit, a, "a is the current unit — turn order starts with a")

	selection.select(b)
	assert_null(selection.selected_unit, "b isn't the current unit, so selecting it clears")


func test_reachable_cells_matches_pathfinder_exactly() -> void:
	var a := _make_unit(Vector2i(4, 4), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var budget: float = a.mp + a.mp_per_ap() * a.ap
	var expected: Array[Vector2i] = pf.reachable(a.cell, budget)

	assert_eq(selection.reachable_cells(), expected)


func test_queue_move_to_an_unreachable_cell_fails() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(20, 20), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_false(selection.queue_move(Vector2i(19, 19)), "far outside any reachable budget")


func test_queuing_two_moves_shows_two_ghosts_the_second_starting_where_the_first_left_off() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_true(selection.queue_move(Vector2i(1, 0)))
	assert_true(selection.queue_move(Vector2i(2, 0)))

	var ghosts: Array[Array] = selection.ghost_paths()
	assert_eq(ghosts.size(), 2)
	assert_eq(ghosts[0][0], Vector2i(0, 0))
	assert_eq(ghosts[0][ghosts[0].size() - 1], Vector2i(1, 0))
	assert_eq(ghosts[1][0], Vector2i(1, 0), "the second ghost must start where the first ends")
	assert_eq(ghosts[1][ghosts[1].size() - 1], Vector2i(2, 0))


func test_queuing_never_mutates_the_real_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)

	var cell_before: Vector2i = a.cell
	var ap_before: int = a.ap
	var mp_before: float = a.mp
	var occupant_before: int = state.grid.get_occupant_id(Vector2i(1, 0))

	selection.select(a)
	selection.reachable_cells()
	selection.queue_move(Vector2i(1, 0))
	selection.queue_move(Vector2i(2, 0))
	selection.queue_end_turn()

	assert_eq(a.cell, cell_before, "queuing must never move the real unit")
	assert_eq(a.ap, ap_before, "queuing must never spend the real unit's AP")
	assert_eq(a.mp, mp_before, "queuing must never spend the real unit's MP")
	assert_eq(
		state.grid.get_occupant_id(Vector2i(1, 0)),
		occupant_before,
		"queuing must never touch the real grid's occupancy"
	)


## docs/10 taskblock03 D2: "the running MP cost per leg and the total."
func test_leg_costs_matches_pathfinders_own_cost_per_queued_leg() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	selection.queue_move(Vector2i(2, 0))
	selection.queue_move(Vector2i(2, 2))

	var costs: Array[float] = selection.leg_costs()
	assert_eq(costs.size(), 2)
	assert_almost_eq(costs[0], 2.0, 0.0001, "two default-cost steps: (0,0)->(1,0)->(2,0)")
	assert_almost_eq(costs[1], 2.0, 0.0001, "two more steps: (2,0)->(2,1)->(2,2)")


## docs/10 taskblock03 D3: "RMB pops the last queued action."
func test_undo_last_pops_the_most_recently_queued_action() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))
	selection.queue_move(Vector2i(2, 0))

	assert_true(selection.undo_last())

	assert_eq(selection.ghost_paths().size(), 1, "only the first leg remains")
	var remaining: Array = selection.ghost_paths()[0]
	assert_eq(remaining[remaining.size() - 1], Vector2i(1, 0))


func test_undo_last_with_an_empty_queue_returns_false() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_false(selection.undo_last())


func test_undo_last_refunds_the_popped_actions_cost_against_the_speculative_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	var full_budget: Array[Vector2i] = selection.reachable_cells()
	selection.queue_move(Vector2i(1, 0))

	selection.undo_last()

	assert_eq(
		selection.reachable_cells(),
		full_budget,
		"undoing the only queued move must restore the full original reach"
	)


## docs/10 taskblock03 D4: "Reset Turn" restores position, facing, MP, AP,
## and empties the queue — but keeps the unit selected.
func test_reset_turn_clears_the_queue_but_keeps_the_unit_selected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))
	selection.queue_face(1.0)

	selection.reset_turn()

	assert_eq(selection.selected_unit, a, "still mid-TACTICS for the same unit")
	assert_eq(selection.ghost_paths(), [] as Array[Array])
	assert_almost_eq(selection.previewed_orientation(), 0.0, 0.0001)


func test_reset_turn_with_nothing_selected_is_a_no_op() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)

	selection.reset_turn()  # must not crash with no selection

	assert_null(selection.selected_unit)


## docs/10 taskblock03 F1: previewed_unit()'s own cell/orientation ARE the
## queued end state — the ghost's whole source of truth.
func test_previewed_unit_reflects_the_queued_end_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	selection.queue_move(Vector2i(2, 0))

	assert_eq(selection.previewed_unit().cell, Vector2i(2, 0))
	assert_eq(a.cell, Vector2i(0, 0), "the real unit must still be untouched")


func test_previewed_unit_with_nothing_selected_is_null() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)

	assert_null(selection.previewed_unit())


func test_reset_clears_selection_and_queues() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))

	selection.reset()

	assert_null(selection.selected_unit)
	selection.select(a)
	assert_eq(selection.ghost_paths(), [] as Array[Array], "a fresh queue must have no ghosts")


func test_queue_end_turn_appends_an_end_turn_action_that_resolves_cleanly() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_true(selection.queue_move(Vector2i(1, 0)))
	assert_true(selection.queue_end_turn())

	state.resolve_turn(selection.current_queue())

	assert_eq(a.cell, Vector2i(1, 0), "resolution must actually move the real unit")
	assert_eq(state.current_unit(), b, "ending the turn must advance turn order")
