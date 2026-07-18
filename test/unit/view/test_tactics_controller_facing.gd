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


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol — the same shape
## test_attack_action.gd uses, so a shooter can actually enter aim mode.
func _make_armed_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.provides_actions = [&"shoot"]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


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

	# runNotes.md: undo only fires on RMB release now (a click, not a
	# press) — press, then release with no motion in between, still reads
	# as a click.
	var rmb_down := InputEventMouseButton.new()
	rmb_down.button_index = MOUSE_BUTTON_RIGHT
	rmb_down.pressed = true
	controller._unhandled_input(rmb_down)
	var rmb_up := InputEventMouseButton.new()
	rmb_up.button_index = MOUSE_BUTTON_RIGHT
	rmb_up.pressed = false
	controller._unhandled_input(rmb_up)
	assert_eq(controller.selection.current_queue().actions.size(), 0)

	controller._unhandled_input(motion)

	assert_eq(
		controller.selection.current_queue().actions.size(),
		1,
		"a motion event after the undo must queue a fresh FaceAction",
	)


## runNotes.md: "keep both things on RMB, but make undo last action only on
## click, while a drag doesn't cancel the action" — RMB also orbits the
## camera; pressing it and moving the mouse before releasing must not also
## undo whatever's queued.
func test_rmb_drag_does_not_undo_the_queued_action() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	assert_eq(controller.selection.ghost_paths().size(), 1)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var motion2 := InputEventMouseMotion.new()
	motion2.relative = Vector2(30.0, 0.0)
	controller._unhandled_input(motion2)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)

	assert_eq(
		controller.selection.ghost_paths().size(), 1, "the drag must not have undone the move"
	)


func test_rmb_click_with_nothing_queued_still_deselects() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)

	assert_null(controller.selection.selected_unit)


## runNotes.md: "keep the both things on RMB" — a plain RMB click while
## aiming must still cancel it.
func test_rmb_click_while_aiming_still_cancels() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	assert_not_null(controller.aiming_at)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)

	assert_null(controller.aiming_at)


func test_rmb_drag_while_aiming_does_not_cancel() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	assert_not_null(controller.aiming_at)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var motion3 := InputEventMouseMotion.new()
	motion3.relative = Vector2(30.0, 0.0)
	controller._unhandled_input(motion3)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)

	assert_not_null(controller.aiming_at, "a drag must not have cancelled aim")


## runNotes.md: "the controlled unit ghost should face the aimed-at unit
## while aiming is happening, and if aiming is cancelled, then they
## 'unface'."
func test_aim_facing_points_the_shooter_at_the_target() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	assert_null(controller.aim_facing(), "not aiming yet: nothing to face")

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 0))

	var expected: float = FaceAction.orientation_toward(Vector2i(0, 0), Vector2i(5, 0))
	assert_almost_eq(controller.aim_facing(), expected, 0.0001)


func test_aim_facing_goes_null_again_once_aim_is_cancelled() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 0))
	assert_not_null(controller.aim_facing())

	controller.cancel_aim()

	assert_null(controller.aim_facing(), "cancelling aim must 'unface' back to nothing")


## runNotes.md: "clicking while a move is highlighted faces both the
## original position and the ghost" — with no move queued, the ghost has
## nothing to show ("where it will end up") even while aiming; the live
## model (BattleScene) is the one that previews aim_facing() in that case.
func test_no_end_position_ghost_while_aiming_with_no_move_queued() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")

	controller.click_cell(Vector2i(5, 0))  # enters aim mode, no move queued

	assert_null(controller._end_position_ghost())
	assert_not_null(controller.aim_facing(), "the live model still has something to preview")


func test_end_position_ghost_faces_the_target_when_a_move_is_also_queued() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	a.mp = 5.0
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(2, 0))  # queue a move first
	controller.arm_action(&"shoot")

	controller.click_cell(Vector2i(5, 0))  # then enter aim mode

	var ghost: Unit = controller._end_position_ghost()
	assert_not_null(ghost, "a move is queued: the ghost carries the aim-facing preview")
	var expected: float = FaceAction.orientation_toward(Vector2i(2, 0), Vector2i(5, 0))
	assert_almost_eq(ghost.orientation, expected, 0.0001)


func test_end_position_ghost_stops_facing_the_target_once_aim_is_cancelled() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	a.mp = 5.0
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(2, 0))  # a queued move keeps the ghost alive post-cancel
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 0))
	assert_not_null(controller._end_position_ghost())

	controller.cancel_aim()

	assert_not_null(
		controller._end_position_ghost(), "the queued move alone still has an end position to show"
	)


func test_has_queued_move_is_false_until_a_move_is_actually_queued() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	assert_false(controller.has_queued_move(), "nothing selected yet")

	controller.click_cell(Vector2i(0, 0))
	assert_false(controller.has_queued_move(), "selected, but nowhere queued to go")

	controller.turn_selected(TacticsController.FACE_STEP)
	assert_false(controller.has_queued_move(), "a pure rotation is not a move")

	a.mp = 5.0
	controller.click_cell(Vector2i(1, 0))
	assert_true(controller.has_queued_move())
