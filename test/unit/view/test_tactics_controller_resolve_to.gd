extends GutTest

## docs/10 taskblock06 G: "Resolve to Here" — resolve_to_marker(), split out
## from test_tactics_controller.gd purely to stay under gdlint's
## max-public-methods (see that file's own trailing comment).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func _setup(units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(Grid.new(10, 10), units)
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)
	return {
		"state": state, "controller": controller, "board_view": board_view, "camera_rig": camera_rig
	}


## docs/10 taskblock06 G1/TESTS: "resolving to a marker applies exactly the
## prefix and no more."
func test_resolve_to_marker_applies_only_the_prefix_through_the_marker() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))
	assert_eq(controller.selection.ghost_paths().size(), 2, "two queued move legs")

	controller.resolve_to_marker(0)

	assert_eq(a.cell, Vector2i(1, 0), "only the first leg actually resolved")


## docs/10 taskblock06 G1/TESTS: "queuing resumes after."
func test_queuing_resumes_after_a_partial_resolve() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))

	controller.resolve_to_marker(0)

	assert_eq(controller.selection.ghost_paths().size(), 0, "the abandoned suffix is discarded")
	assert_eq(controller.selection.selected_unit, a, "still selected — the turn has not ended")

	# docs/10 Phase 12.4: input stays locked until whoever plays the
	# resolved events back calls unlock_input(), same as end_turn() — a
	# real ResolutionPlayer isn't wired in this headless test, so this
	# stands in for "the cosmetic replay finished."
	controller.unlock_input()
	controller.click_cell(Vector2i(1, 1))  # queuing must still work after a partial resolve

	assert_eq(controller.selection.ghost_paths().size(), 1, "a fresh move was queued")


## docs/10 taskblock06 G1/TESTS: "the speculative clone is rebuilt from
## post-resolve authoritative state."
func test_previewed_unit_after_a_partial_resolve_reflects_the_moved_authoritative_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))

	controller.resolve_to_marker(0)

	assert_eq(controller.selection.previewed_unit().cell, Vector2i(1, 0))


## docs/10 taskblock06 G1/G3/TESTS: "Reset Turn after a partial resolve
## returns to the resolve point, not turn start."
func test_reset_turn_after_a_partial_resolve_returns_to_the_resolve_point() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))
	controller.resolve_to_marker(0)
	controller.unlock_input()  # stands in for a real ResolutionPlayer's own unlock
	controller.click_cell(Vector2i(2, 1))  # queue something new, post-resolve

	controller.reset_turn()

	assert_eq(a.cell, Vector2i(1, 0), "the real unit stays wherever the partial resolve left it")
	assert_eq(
		controller.selection.previewed_unit().cell,
		Vector2i(1, 0),
		"reset returns to the resolve point, never the original turn-start cell (0,0)"
	)


func test_resolve_to_marker_with_an_out_of_range_index_is_a_no_op() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))

	controller.resolve_to_marker(5)

	assert_eq(a.cell, Vector2i(0, 0), "nothing resolved — the index was out of range")
	assert_eq(controller.selection.ghost_paths().size(), 1, "the queue is untouched")
