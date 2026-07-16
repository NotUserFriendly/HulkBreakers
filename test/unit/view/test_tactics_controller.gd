extends GutTest

## docs/10 Phase 12.2: TacticsController is a thin shell — click_cell() is
## driven directly here (no live camera/viewport needed); the raw input ->
## ray -> cell translation is BoardPicker's job, already covered headlessly.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Frame.new(root), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	add_child_autofree(board_view)
	add_child_autofree(controller)
	controller.setup(state, board_view, null)
	return {"state": state, "controller": controller, "board_view": board_view}


func test_clicking_the_current_unit_selects_it_and_shows_its_reachable_cells() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var board_view: BoardView = built.board_view

	controller.click_cell(Vector2i(0, 0))

	assert_eq(controller.selection.selected_unit, a)
	assert_true(board_view._reachable_overlay.get_child_count() > 0)


func test_clicking_a_non_current_unit_does_not_select_it() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(5, 5))

	assert_null(controller.selection.selected_unit)


func test_clicking_a_reachable_cell_after_selecting_queues_a_move_and_shows_a_ghost() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var board_view: BoardView = built.board_view

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))

	assert_eq(controller.selection.ghost_paths().size(), 1)
	assert_true(board_view._ghost_overlay.get_child_count() > 0)
	assert_eq(a.cell, Vector2i(0, 0), "still just queued, the real unit has not moved")


func test_end_turn_resolves_the_queue_and_clears_the_overlay() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var board_view: BoardView = built.board_view
	var state: CombatState = built.state

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.end_turn()

	assert_eq(a.cell, Vector2i(1, 0), "resolution must actually move the real unit")
	assert_eq(state.current_unit(), b, "ending the turn must advance turn order")
	assert_eq(board_view._reachable_overlay.get_child_count(), 0)
	assert_eq(board_view._ghost_overlay.get_child_count(), 0)
	assert_null(controller.selection.selected_unit)


func test_end_turn_emits_turn_ended() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	watch_signals(controller)
	controller.end_turn()

	assert_signal_emitted(controller, "turn_ended")
