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


## BR27.08 (supervisor follow-up): a partial resolve must not discard what
## was queued after the marker — only the resolved prefix is gone.
func test_the_later_queued_leg_survives_a_partial_resolve() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))

	controller.resolve_to_marker(0)

	assert_eq(
		controller.selection.ghost_paths().size(),
		1,
		"only the resolved prefix is gone — the still-queued leg survives"
	)
	assert_eq(controller.selection.selected_unit, a, "still selected — the turn has not ended")

	# docs/10 Phase 12.4: input stays locked until whoever plays the
	# resolved events back calls unlock_input(), same as end_turn() — a
	# real ResolutionPlayer isn't wired in this headless test, so this
	# stands in for "the cosmetic replay finished."
	controller.unlock_input()
	controller.click_cell(Vector2i(1, 1))  # queuing must still work after a partial resolve

	assert_eq(
		controller.selection.ghost_paths().size(), 2, "the surviving leg plus a freshly queued one"
	)


## docs/10 taskblock06 G1/TESTS: "the speculative clone is rebuilt from
## post-resolve authoritative state" — BR27.08 follow-up: now ALSO carries
## the still-queued leg's own preview forward, since that leg survives
## the resolve instead of being discarded.
func test_previewed_unit_after_a_partial_resolve_reflects_the_moved_state_plus_the_kept_suffix(
) -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	controller.click_cell(Vector2i(2, 0))

	controller.resolve_to_marker(0)

	assert_eq(
		controller.selection.previewed_unit().cell,
		Vector2i(2, 0),
		"the real move happened AND the still-queued leg's own preview carries it further"
	)


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
