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


## Same shape as `_make_armed_unit`, but a burst-only weapon (matching
## chaingun.tres's own provides_actions/burst_size data shape) — for
## taskblock-24 Pass A's own confirm_shot dispatch test below.
func _make_chaingun_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var chaingun := Part.new()
	chaingun.id = &"chaingun"
	chaingun.hp = 1
	chaingun.max_hp = 1
	chaingun.attaches_to = [&"GRIP"]
	chaingun.requires = {&"TRIGGER": 1}
	chaingun.damage = 5.0
	chaingun.ap_cost = 2
	chaingun.scatter = [Ring.new(0.1, 1.0)]
	chaingun.provides_actions = [&"burst"]
	chaingun.weapon_def = WeaponDef.new()
	chaingun.weapon_def.burst_size = 12

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = chaingun
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


## Mirrors test_overwatch.gd's own _make_overwatcher (WRIST socket, not
## HAND) — UnitGeometry.muzzle_point's own placement math depends on that
## specific socket type.
func _make_overwatcher(cell: Vector2i, orientation: float, squad: int) -> Unit:
	var pistol := Part.new()
	pistol.id = &"owpistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.requires = {&"TRIGGER": 1}

	var hand := Part.new()
	hand.id = &"owhand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"owtorso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad)
	unit.orientation = orientation
	return unit


## taskblock-19 Pass D: "a transparent pie slice... exactly the cells that
## would trigger" — selecting a unit sitting inside an armed enemy
## overwatcher's own arc must populate the overlay, driven through
## TacticsController._refresh_overlay() -> Overwatch.arc_cells, never a
## second, view-only notion of the arc.
func test_selecting_a_unit_inside_an_armed_overwatchers_arc_shows_the_threat_overlay() -> void:
	var overwatcher := _make_overwatcher(
		Vector2i(5, 0), BodyProjector.orientation_for(Vector2(0, 1)), 1
	)
	var target := _make_armed_unit(Vector2i(5, 3), 0)
	var built: Dictionary = _setup([target, overwatcher])
	var board_view: BoardView = built.board_view
	var controller: TacticsController = built.controller
	overwatcher.overwatch_weapon_id = &"owpistol"

	controller.click_cell(target.cell)

	assert_true(board_view._overwatch_overlay.get_child_count() > 0)


## An overwatcher's own arc never threatens itself — selecting it (with
## no OTHER armed overwatcher on the board) must show nothing.
func test_selecting_the_overwatcher_itself_shows_no_threat_overlay() -> void:
	var overwatcher := _make_overwatcher(
		Vector2i(5, 0), BodyProjector.orientation_for(Vector2(0, 1)), 0
	)
	var built: Dictionary = _setup([overwatcher])
	var board_view: BoardView = built.board_view
	var controller: TacticsController = built.controller
	overwatcher.overwatch_weapon_id = &"owpistol"

	controller.click_cell(overwatcher.cell)

	assert_eq(board_view._overwatch_overlay.get_child_count(), 0)


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


## taskblock-19 Pass F: "available to AI and player" — the same
## queue-and-resolve-for-real shape end_turn() has, proven end to end
## through the real controller/state rather than just HoldAction/
## CombatState in isolation.
func test_hold_defers_the_selected_unit_to_after_the_next_ally() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var state: CombatState = built.state
	controller.click_cell(Vector2i(0, 0))

	controller.hold()

	assert_eq(state.current_unit(), b, "the next unit acts as normal")
	assert_null(controller.selection.selected_unit, "the holding unit's own selection clears")
	state.advance_turn()  # b ends its turn
	assert_eq(state.current_unit(), a, "a resumes right after b")


func test_hold_emits_turn_ended() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))

	watch_signals(controller)
	controller.hold()

	assert_signal_emitted(controller, "turn_ended")


func test_hold_is_a_no_op_with_nothing_selected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.hold()  # must not crash with no selection to hold

	assert_null(controller.selection.selected_unit)


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


## A unit with a wide torso box overhanging the neighboring cell — the case
## docs/10 taskblock03 D1 calls out: a click on the mesh, not the tile.
## runNotes.md: "make undo last action only on click, while a drag doesn't
## cancel the action" — a click is a press immediately followed by a
## release, no motion event in between.
func _rmb_click(controller: TacticsController) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)


## docs/10 taskblock03 D3: "RMB pops the last queued action... RMB with an
## empty queue -> deselect."
func test_rmb_undoes_the_last_queued_action_without_aiming() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	assert_eq(controller.selection.ghost_paths().size(), 1)

	_rmb_click(controller)

	assert_eq(controller.selection.ghost_paths().size(), 0)
	assert_eq(controller.selection.selected_unit, a, "still selected — only the action was undone")


func test_rmb_with_an_empty_queue_deselects() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))

	_rmb_click(controller)

	assert_null(controller.selection.selected_unit)


## docs/10 taskblock03 D4: Reset Turn — button + R.
func test_r_key_resets_the_turn_but_keeps_the_unit_selected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))
	assert_eq(controller.selection.ghost_paths().size(), 1)

	var r_key := InputEventKey.new()
	r_key.pressed = true
	r_key.keycode = KEY_R
	controller._unhandled_input(r_key)

	assert_eq(controller.selection.ghost_paths().size(), 0)
	assert_eq(controller.selection.selected_unit, a)


func test_reset_turn_with_nothing_selected_does_not_crash() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.reset_turn()  # nothing selected: must not crash

	assert_null(controller.selection.selected_unit)


## A unit with real box volume — the ghost overlay needs at least one
## placement to actually spawn a mesh; `_make_unit` above has none (it
## never needed one for click-cell dispatch).
func _make_boxed_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))]
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


## docs/10 taskblock03 F1: nothing queued -> no ghost (it would just sit on
## top of the real, opaque unit); once something changes the end state, the
## ghost overlay actually gets a mesh.
func test_selecting_a_unit_with_nothing_queued_shows_no_end_position_ghost() -> void:
	var a := _make_boxed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var board_view: BoardView = built.board_view

	controller.click_cell(Vector2i(0, 0))

	assert_eq(board_view._unit_ghost_overlay.get_child_count(), 0)


func test_queuing_a_move_shows_an_end_position_ghost() -> void:
	var a := _make_boxed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var board_view: BoardView = built.board_view

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(1, 0))

	assert_true(board_view._unit_ghost_overlay.get_child_count() > 0)


## Aim mode, the dartboard read/resolve pair, and RESOLUTION input-locking
## live in test_tactics_controller_aim.gd; mouse-drag facing (docs/10
## taskblock03 E1) lives in test_tactics_controller_facing.gd; "Resolve to
## Here" (docs/10 taskblock06 G) lives in
## test_tactics_controller_resolve_to.gd — all split out purely to stay
## under gdlint's max-public-methods.


## taskblock-24 Pass A: confirm_shot() used to unconditionally build an
## AttackAction regardless of `armed_action.id` — arming and clicking
## BURST never actually reached BurstAction at all. Proof it now does.
func test_confirm_shot_with_burst_armed_queues_a_burst_action_not_an_attack_action() -> void:
	var a := _make_chaingun_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"burst")
	controller.click_cell(Vector2i(5, 5))
	controller.confirm_shot()

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 1)
	assert_true(actions[0] is BurstAction, "arming BURST must actually queue a real BurstAction")


## tb35 Pass C (BR32.07): "burst cannot aim at a wall at all" — the reported
## symptom is a failure at AIM time, not confirm/queue time (`BurstAction.
## is_legal()`/`apply()` already support a blocker-only target cell, tb32
## Pass C). Arms burst and clicks a real wall cell — `aiming_at` and
## `aim_state()` must populate exactly the way they do for a live-unit
## target, never leave aim mode empty/unentered.
func test_arming_burst_and_clicking_a_wall_enters_aim_mode() -> void:
	var a := _make_chaingun_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	var state: CombatState = built.state
	state.grid.blockers[Vector2i(5, 0)] = DataLibrary.get_part(&"wall")

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"burst")
	controller.click_cell(Vector2i(5, 0))

	assert_not_null(controller.aiming_at, "arming burst at a wall must still enter aim mode")
	var aim: Dictionary = controller.aim_state()
	assert_false(aim.is_empty(), "aim_state() must not come back empty for a wall target")
