extends GutTest

## docs/10 taskblock03 E1: mouse-drag facing — split out of
## test_tactics_controller.gd purely to stay under gdlint's
## max-public-methods; same conventions (drive controller methods directly,
## no live camera/viewport needed).


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


## docs/10 taskblock03 E1: "mouse-drag facing — continuous, any angle."
func test_drag_face_queues_a_single_face_action_and_updates_it_continuously() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	a.mp = 5.0
	controller.click_cell(Vector2i(0, 0))

	controller.drag_face(10.0)
	controller.drag_face(10.0)
	controller.drag_face(-4.0)

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 1, "one continuous drag must stay one queued action")
	var expected: float = 16.0 * TacticsController.FACE_DRAG_SENSITIVITY
	assert_almost_eq((actions[0] as FaceAction).direction, expected, 0.0001)


func test_drag_face_with_nothing_selected_is_a_no_op() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.drag_face(10.0)  # nothing selected: must not crash

	assert_null(controller.selection.selected_unit)


## docs/10 taskblock03 E1: press-and-hold on the already-selected unit's own
## body starts a drag instead of a click; releasing LMB ends it, so a motion
## event afterward must not still be treated as a drag.
func test_pressing_lmb_on_the_selected_unit_starts_a_drag_not_a_reselect_click() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	# _cell_at() needs a live camera ray, which this file's own convention
	# avoids requiring for input plumbing (see the class doc comment) — set
	# the drag flag directly, exactly what a real LMB-down on the selected
	# unit's own body would have done.
	controller._facing_drag_active = true

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20.0, 0.0)
	controller._unhandled_input(motion)

	assert_eq(controller.selection.current_queue().actions.size(), 1)

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	controller._unhandled_input(up)

	assert_false(controller._facing_drag_active)
	controller._unhandled_input(motion)
	assert_eq(
		controller.selection.current_queue().actions.size(),
		1,
		"motion after release must not still drag",
	)


## docs/10 taskblock03 D3: RMB-undo mid-drag must not leave a dangling
## reference that a later motion event silently mutates off-queue.
func test_rmb_undo_mid_drag_clears_the_drag_so_a_later_motion_queues_fresh() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller._facing_drag_active = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10.0, 0.0)
	controller._unhandled_input(motion)
	assert_eq(controller.selection.current_queue().actions.size(), 1)

	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	controller._unhandled_input(rmb)
	assert_eq(controller.selection.current_queue().actions.size(), 0)

	controller._unhandled_input(motion)

	assert_eq(
		controller.selection.current_queue().actions.size(),
		1,
		"a motion event after the undo must queue a fresh FaceAction",
	)
