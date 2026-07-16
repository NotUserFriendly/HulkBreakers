extends GutTest

## docs/10 Phase 12.2: TacticsController is a thin shell — click_cell() is
## driven directly here (no live camera/viewport needed); the raw input ->
## ray -> cell translation is BoardPicker's job, already covered headlessly.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol — the same shape
## test_attack_action.gd uses, so the shooter can actually fire.
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


## docs/10 taskblock02 F2: "click away / Esc -> deselect."
func test_deselect_clears_selection_and_overlays() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var board_view: BoardView = built.board_view
	controller.click_cell(Vector2i(0, 0))
	assert_not_null(controller.selection.selected_unit)

	controller.deselect()

	assert_null(controller.selection.selected_unit)
	assert_eq(board_view._reachable_overlay.get_child_count(), 0)


func test_deselect_with_nothing_selected_is_a_no_op() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.deselect()  # must not crash with no selection to clear

	assert_null(controller.selection.selected_unit)


## docs/10 taskblock02 F2: "click away / Esc -> deselect." `_handle_mouse_
## button` takes the same `deselect()` path on an off-board click (when
## `BoardPicker.cell_at_ray` returns null) — untested here since that
## needs a live camera/viewport this file's own convention avoids (ray ->
## cell translation is BoardPicker's job, already covered headlessly);
## `deselect()` itself is what both callers share, and it's covered above.
func test_esc_deselects_when_not_aiming() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))

	controller._unhandled_input(InputEventKey.new())  # unused key: no-op guard
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	controller._unhandled_input(esc)

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


## docs/10 taskblock02 F3: Q/E queues a FaceAction; ending the turn
## actually turns the real unit and costs the MP FaceAction always does.
func test_turn_selected_queues_a_face_action_and_resolves_it_on_end_turn() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	# A second unit so advance_turn() moves on rather than wrapping straight
	# back to `a` and resetting its MP via _start_turn before this can check it.
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	a.mp = 5.0  # plenty — isolates this test from the separate AP-burn case

	controller.click_cell(Vector2i(0, 0))
	controller.turn_selected(TacticsController.FACE_STEP)

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 1)
	assert_true(actions[0] is FaceAction)

	controller.end_turn()

	assert_almost_eq(a.orientation, TacticsController.FACE_STEP, 0.0001)
	assert_almost_eq(a.mp, 5.0 - FaceAction.COST, 0.0001)


func test_turn_selected_twice_composes_relative_to_the_already_queued_turn() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.turn_selected(TacticsController.FACE_STEP)
	controller.turn_selected(TacticsController.FACE_STEP)

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 2, "each press queues its own FaceAction")
	var second := actions[1] as FaceAction
	assert_almost_eq(second.direction, TacticsController.FACE_STEP * 2.0, 0.0001)


func test_turn_selected_with_nothing_selected_is_a_no_op() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.turn_selected(TacticsController.FACE_STEP)  # nothing selected: must not crash

	assert_null(controller.selection.selected_unit)

## Aim mode, the dartboard read/resolve pair, and RESOLUTION input-locking
## live in test_tactics_controller_aim.gd — split out purely to stay under
## gdlint's max-public-methods.
