extends GutTest

## taskblock-18 Pass D2/D4 (taskblock-19 Pass B: Lean -> Step Out
## rename): step outs — a click on a covered-but-steppable-out-to
## enemy enters step-out-choice mode instead of ordinary aim mode; wheel
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


## Verified geometry (matches test_unit_ai.gd's own AI-step-out-fallback
## fixture): a real WALL (opacity) at (3,2) blinds a shooter at (3,0)
## from an enemy at (3,9), while both orthogonal neighbors keep clear
## LoS around it. Row y=1 is ALSO walled (pathing only, no opacity) so
## no diagonal shortcut competes with the step-out cells for the reachable-
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


## BR27.06 investigation: every OTHER test in this file drives the click
## through `click_cell()` directly. The real game drives a LEFT click
## through `_handle_mouse_button` (camera ray -> `_cell_at` -> dispatch),
## a genuinely separate code path `click_cell` documents itself as never
## using. Proving whether THAT path also enters step-out mode is the
## actual reproduction this investigation needs — same pattern
## test_spectator_overlay.gd's own real-click tests already use
## (`camera.unproject_position` -> a real `InputEventMouseButton`).
func test_a_real_mouse_click_on_a_covered_enemy_also_enters_step_out_mode() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")

	var world_point: Vector3 = (
		Vector3(built.enemy.cell.x, 0.5, built.enemy.cell.y) * UnitGeometry.CELL_SIZE
	)
	var screen_pos: Vector2 = camera_rig.camera().unproject_position(world_point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_pos
	controller._unhandled_input(click)

	assert_eq(controller.stepping_out_at, built.enemy)
	assert_null(controller.aiming_at, "a step out never also enters ordinary aim mode")


func test_clicking_a_covered_enemy_enters_step_out_mode_not_aim_mode() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller

	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)

	assert_eq(controller.stepping_out_at, built.enemy)
	assert_null(controller.aiming_at, "a step out never also enters ordinary aim mode")


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
	assert_null(controller.stepping_out_at, "a clear shot must never enter step-out mode")


## BR27.06 investigation: every OTHER test in this file arms+clicks from
## the shooter's OWN TURN-START cell, never after a queued (not yet
## resolved) move. A real player very often moves toward/into cover
## FIRST, then arms and shoots — the realistic pattern this file had no
## coverage for at all. `(5, 0)` has clear, uncovered LOS to the enemy at
## `(3, 9)` (the only opaque cell, `(3, 2)`, isn't on that line); queuing
## a move to `(3, 0)` — the SAME covered cell every other test in this
## file starts the shooter at directly — must make the queued (not yet
## resolved) destination the one `_enter_aim_or_step_out_mode` evaluates
## cover from, not the stale pre-move cell.
func test_moving_into_cover_then_shooting_still_enters_step_out_mode() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	var shooter: Unit = built.shooter
	shooter.cell = Vector2i(5, 0)
	built.state.grid.set_occupant_id(Vector2i(3, 0), -1)
	built.state.grid.set_occupant_id(Vector2i(5, 0), shooter.id)
	shooter.mp = 100.0

	controller.click_cell(shooter.cell)
	assert_true(
		controller.selection.queue_move(Vector2i(3, 0)), "sanity: the move into cover must queue"
	)
	controller.arm_action(&"shoot")

	controller.click_cell(built.enemy.cell)

	assert_eq(
		controller.stepping_out_at,
		built.enemy,
		"the queued (not yet resolved) destination is covered — step out must trigger from there"
	)
	assert_null(controller.aiming_at, "a step out never also enters ordinary aim mode")


## Pass D audit (BR27.05/BR27.06 parent pattern): `_confirm_step_out()`
## computed its outbound path from `selection.selected_unit.cell` — the
## same stale, pre-queued-move cell BR27.06 already fixed one function
## over. `MoveAction.is_legal()` requires `path[0] == actual.cell` against
## whatever the unit's ACTUAL (previewed) position is by the time the
## queue validates it — so continuing directly from
## `test_moving_into_cover_then_shooting_still_enters_step_out_mode`
## (a move already queued into cover before arming/clicking), confirming
## the step-out cell must still succeed, not silently cancel because the
## computed path starts from the wrong (pre-move) cell.
func test_confirming_a_step_out_cell_after_a_prior_queued_move_still_queues_the_out_leg() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	var shooter: Unit = built.shooter
	shooter.cell = Vector2i(5, 0)
	built.state.grid.set_occupant_id(Vector2i(3, 0), -1)
	built.state.grid.set_occupant_id(Vector2i(5, 0), shooter.id)
	shooter.mp = 100.0
	controller.click_cell(shooter.cell)
	controller.selection.queue_move(Vector2i(3, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	assert_eq(controller.stepping_out_at, built.enemy, "sanity: step-out mode entered")

	controller.confirm_shot()

	assert_null(
		controller.stepping_out_at, "step-out choice must resolve, not silently cancel back to null"
	)
	assert_eq(
		controller.aiming_at,
		built.enemy,
		"confirming must reach ordinary aim mode — a silent cancel leaves this null instead"
	)
	var queued: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(queued.size(), 2, "the prior move leg plus the step-out's own free outbound leg")
	var out_leg := queued[1] as MoveAction
	assert_eq(
		out_leg.path[0],
		Vector2i(3, 0),
		"the outbound leg must path from where the prior move actually leaves the shooter, not (5, 0)"
	)


func test_step_out_candidates_are_populated_safest_first() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")

	controller.click_cell(built.enemy.cell)

	assert_gt(controller._step_out_candidates.size(), 0)
	assert_eq(controller._step_out_cell_index, 0, "starts on the safest (first) candidate")
	for cell: Vector2i in controller._step_out_candidates:
		assert_eq(
			Grid.distance_manhattan(built.shooter.cell, cell), 1, "every candidate is orthogonal"
		)


func test_wheel_cycles_the_step_out_cell_and_wraps() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	var count: int = controller._step_out_candidates.size()
	assert_gt(count, 1, "sanity: this fixture must offer more than one candidate to prove cycling")

	controller.cycle_step_out_cell(1)
	assert_eq(controller._step_out_cell_index, 1)

	controller.cycle_step_out_cell(1 * (count - 1))  # wrap all the way back around
	assert_eq(controller._step_out_cell_index, 0)

	controller.cycle_step_out_cell(-1)
	assert_eq(
		controller._step_out_cell_index, count - 1, "cycling backward from 0 wraps to the end"
	)


## taskblock-27 Pass B: confirming a step-out's own CELL choice no longer
## auto-resolves the whole triple — it queues only the free outbound leg,
## then hands off into ORDINARY aim mode (dartboard open) from the
## stepped-out position. The attack + free return leg only get queued
## once the player actually fires (confirm_shot() again, now in aim
## mode) — see the fixture below for the full sequence.
func test_confirming_a_step_out_cell_queues_only_the_free_outbound_leg_then_opens_aim() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	var firing_cell: Vector2i = controller._step_out_candidates[0]

	controller.confirm_shot()

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 1, "only the free outbound leg — no shot, no return leg yet")
	assert_true(actions[0] is MoveAction)
	var out_move: MoveAction = actions[0]
	assert_eq(out_move.path[out_move.path.size() - 1], firing_cell)
	assert_true(out_move.free, "the outbound leg must cost no MP/AP")
	assert_null(
		controller.stepping_out_at, "confirming the cell must leave step-out CELL-choice mode"
	)
	assert_eq(controller.aiming_at, built.enemy, "must hand off into ordinary aim mode")


## The full sequence: confirm the step-out cell (queues the free out-leg,
## opens aim), then fire (confirm_shot() again, now in ordinary aim mode)
## — this is what actually assembles the whole move/fire/return triple,
## with both moves free.
func test_firing_after_a_step_out_completes_the_free_move_attack_move_triple() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	var firing_cell: Vector2i = controller._step_out_candidates[0]
	controller.confirm_shot()  # locks in the step-out cell, opens aim

	controller.confirm_shot()  # fires from the stepped-out position

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 3)
	assert_true(actions[0] is MoveAction)
	assert_true(actions[1] is AttackAction)
	assert_true(actions[2] is MoveAction)
	var out_move: MoveAction = actions[0]
	assert_eq(out_move.path[out_move.path.size() - 1], firing_cell)
	assert_true(out_move.free)
	var back_move: MoveAction = actions[2]
	assert_eq(back_move.path[back_move.path.size() - 1], built.shooter.cell)
	assert_true(back_move.free, "the return leg must cost no MP/AP too")
	assert_null(controller.aiming_at, "firing must leave aim mode")


## taskblock-27 Pass B: backing out of aim mid-step-out (before ever
## firing) must undo the free outbound leg too, not leave the unit
## standing at the firing cell with nothing queued to show for it.
func test_cancelling_aim_mid_step_out_undoes_the_free_outbound_leg() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	controller.confirm_shot()  # locks in the step-out cell, opens aim
	assert_eq(controller.selection.current_queue().actions.size(), 1, "sanity: out-leg queued")

	controller.cancel_aim()

	assert_eq(
		controller.selection.current_queue().actions.size(),
		0,
		"the free outbound leg must be undone, not left dangling with no shot fired"
	)
	assert_null(controller.aiming_at)


## Clicking on ANY cell while stepping out confirms the CELL choice —
## mirrors confirm_shot's own "any click confirms" contract for ordinary
## aim mode. Only the free out-leg is queued at this point; see the
## "firing after a step out" test above for the rest of the sequence.
func test_any_click_while_stepping_out_confirms_the_cell_choice() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)

	controller.click_cell(Vector2i(9, 9))  # an unrelated, empty cell

	assert_null(controller.stepping_out_at)
	assert_eq(controller.selection.current_queue().actions.size(), 1)
	assert_eq(controller.aiming_at, built.enemy)


func test_esc_cancels_a_pending_step_out_without_queuing_anything() -> void:
	var built: Dictionary = _setup_covered_scene()
	var controller: TacticsController = built.controller
	controller.click_cell(built.shooter.cell)
	controller.arm_action(&"shoot")
	controller.click_cell(built.enemy.cell)
	assert_not_null(controller.stepping_out_at)

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	controller._unhandled_input(esc)

	assert_null(controller.stepping_out_at)
	assert_eq(controller.selection.current_queue().actions.size(), 0)
	assert_not_null(
		controller.selection.selected_unit, "Esc backs out one level, not a full deselect"
	)


func test_rmb_also_cancels_a_pending_step_out() -> void:
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

	assert_null(controller.stepping_out_at)
	assert_eq(controller.selection.current_queue().actions.size(), 0)


## taskblock-18 D4: "the ghost must disclose exposure."
func test_step_out_exposure_reports_a_real_overwatcher_at_the_selected_cell() -> void:
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
	for i in range(controller._step_out_candidates.size()):
		if Overwatch.would_trigger_at(state, built.shooter, controller._step_out_candidates[i]).has(
			overwatcher
		):
			threatened_index = i
	assert_true(threatened_index >= 0, "sanity: the fixture must actually threaten one candidate")
	while controller._step_out_cell_index != threatened_index:
		controller.cycle_step_out_cell(1)

	assert_eq(controller.step_out_exposure(), [overwatcher])
