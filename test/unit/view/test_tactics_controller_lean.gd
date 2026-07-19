extends GutTest

## taskblock-18 Pass D2/D4: leans — a click on a covered-but-leanable
## enemy enters lean-choice mode instead of ordinary aim mode; wheel
## cycles candidates; a further click/confirm_shot() commits the triple.
## Same conventions as the rest of this file's siblings (click_cell()
## driven directly, no live camera/viewport needed).


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


## Verified geometry (matches test_unit_ai.gd's own AI-lean-fallback
## fixture): a real WALL (opacity) at (3,2) blinds a shooter at (3,0)
## from an enemy at (3,9), while both orthogonal neighbors keep clear
## LoS around it. Row y=1 is ALSO walled (pathing only, no opacity) so
## no diagonal shortcut competes with the lean cells for the reachable-
## cell scorer elsewhere in the codebase — irrelevant to TacticsController
## itself (it never repositions), kept only so this fixture matches its
## AI-side counterpart byte for byte.
func _setup_covered_scene() -> Dictionary:
	var grid := Grid.new(10, 10)
	for x in range(8):
		grid.set_terrain(Vector2i(x, 1), Enums.TerrainType.WALL)
	grid.set_terrain(Vector2i(3, 2), Enums.TerrainType.WALL)
	grid.set_opacity(Vector2i(3, 2), 1.0)

	var shooter := _make_armed_unit(Vector2i(3, 0), 0)
	var enemy := _make_armed_unit(Vector2i(3, 9), 1)
	var state := CombatState.new(grid, [shooter, enemy])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)
	return {
		"state": state,
		"controller": controller,
		"shooter": shooter,
		"enemy": enemy,
		"board_view": board_view,
		"camera_rig": camera_rig
	}


func test_clicking_a_covered_enemy_enters_lean_mode_not_aim_mode() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller

	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)

	assert_eq(controller.leaning_at, built.enemy)
	assert_null(controller.aiming_at, "a lean never also enters ordinary aim mode")


func test_a_directly_visible_enemy_still_enters_ordinary_aim_mode() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)  # open board, no cover at all
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var controller := TacticsController.new()
	var board_view := BoardView.new()
	var camera_rig := CameraRig.new()
	add_child_autofree(board_view)
	add_child_autofree(camera_rig)
	add_child_autofree(controller)
	controller.setup(state, board_view, camera_rig)

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))

	assert_eq(controller.aiming_at, b)
	assert_null(controller.leaning_at, "a clear shot must never enter lean mode")


func test_lean_candidates_are_populated_safest_first() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")

	controller.click_cell(built.enemy.cell)

	assert_gt(controller._lean_candidates.size(), 0)
	assert_eq(controller._lean_cell_index, 0, "starts on the safest (first) candidate")
	for cell: Vector2i in controller._lean_candidates:
		assert_eq(
			Grid.distance_manhattan(built.shooter.cell, cell), 1, "every candidate is orthogonal"
		)


func test_wheel_cycles_the_lean_cell_and_wraps() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	var count: int = controller._lean_candidates.size()
	assert_gt(count, 1, "sanity: this fixture must offer more than one candidate to prove cycling")

	controller.cycle_lean_cell(1)
	assert_eq(controller._lean_cell_index, 1)

	controller.cycle_lean_cell(1 * (count - 1))  # wrap all the way back around
	assert_eq(controller._lean_cell_index, 0)

	controller.cycle_lean_cell(-1)
	assert_eq(controller._lean_cell_index, count - 1, "cycling backward from 0 wraps to the end")


func test_confirming_a_lean_queues_the_move_attack_move_triple() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	var firing_cell: Vector2i = controller._lean_candidates[0]

	controller.confirm_shot()

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 3)
	assert_true(actions[0] is MoveAction)
	assert_true(actions[1] is AttackAction)
	assert_true(actions[2] is MoveAction)
	var out_move: MoveAction = actions[0]
	assert_eq(out_move.path[out_move.path.size() - 1], firing_cell)
	var back_move: MoveAction = actions[2]
	assert_eq(back_move.path[back_move.path.size() - 1], built.shooter.cell)
	assert_null(controller.leaning_at, "confirming must leave lean mode")


## Clicking on ANY cell while leaning confirms it — mirrors confirm_shot's
## own "any click confirms" contract for ordinary aim mode.
func test_any_click_while_leaning_confirms_it() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)

	controller.click_cell(Vector2i(9, 9))  # an unrelated, empty cell

	assert_null(controller.leaning_at)
	assert_eq(controller.selection.current_queue().actions.size(), 3)


func test_esc_cancels_a_pending_lean_without_queuing_anything() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	assert_not_null(controller.leaning_at)

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	controller._unhandled_input(esc)

	assert_null(controller.leaning_at)
	assert_eq(controller.selection.current_queue().actions.size(), 0)
	assert_not_null(
		controller.selection.selected_unit, "Esc backs out one level, not a full deselect"
	)


func test_rmb_also_cancels_a_pending_lean() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)

	assert_null(controller.leaning_at)
	assert_eq(controller.selection.current_queue().actions.size(), 0)


## taskblock-18 D4: "the ghost must disclose exposure."
func test_lean_exposure_reports_a_real_overwatcher_at_the_selected_cell() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	var state: CombatState = built.state

	var overwatch_pistol := Part.new()
	overwatch_pistol.id = &"owpistol"
	overwatch_pistol.hp = 3
	overwatch_pistol.max_hp = 3
	overwatch_pistol.damage = 5.0
	overwatch_pistol.ap_cost = 1
	overwatch_pistol.scatter = [Ring.new(0.1, 1.0)]
	overwatch_pistol.requires = {&"TRIGGER": 1}
	var ow_hand := Part.new()
	ow_hand.id = &"owhand"
	ow_hand.hp = 3
	ow_hand.max_hp = 3
	ow_hand.capabilities = [&"TRIGGER"]
	var ow_grip := Socket.new(&"GRIP")
	ow_grip.occupant = overwatch_pistol
	ow_hand.sockets = [ow_grip]
	var ow_torso := Part.new()
	ow_torso.id = &"owtorso"
	ow_torso.hp = 10
	ow_torso.max_hp = 10
	var ow_wrist := Socket.new(&"WRIST")
	ow_wrist.occupant = ow_hand
	ow_torso.sockets = [ow_wrist]
	var overwatcher := Unit.new(Matrix.new(), Shell.new(ow_torso), Vector2i(8, 0), 1)
	overwatcher.orientation = BodyProjector.orientation_for(Vector2(-1, 0))
	state.add_unit(overwatcher)
	overwatcher.overwatch_weapon_id = &"owpistol"

	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	# Find the candidate the overwatcher actually threatens and select it,
	# regardless of which one sorted first.
	var threatened_index := -1
	for i in range(controller._lean_candidates.size()):
		if Overwatch.would_trigger_at(state, built.shooter, controller._lean_candidates[i]).has(
			overwatcher
		):
			threatened_index = i
	assert_true(threatened_index >= 0, "sanity: the fixture must actually threaten one candidate")
	while controller._lean_cell_index != threatened_index:
		controller.cycle_lean_cell(1)

	assert_eq(controller.lean_exposure(), [overwatcher])
