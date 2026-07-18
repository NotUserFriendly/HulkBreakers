extends GutTest

## taskblock-08 Pass A1: "arm then click." arm_action()/disarm_action() and
## the click-gating they add to _click_unit() — split out of
## test_tactics_controller_aim.gd purely to stay under gdlint's
## max-public-methods; same conventions (click_cell() driven directly, no
## live camera/viewport needed).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol — the same shape
## test_tactics_controller_aim.gd uses, so the shooter can actually fire.
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


## Both a gun (provides &"shoot") and a saw (provides &"saw") living on the
## same shell — the fixture Pass A1's own "the armed action decides what a
## click means" needs: arming one or the other must pick the DIFFERENT
## part, never just whatever DeepStrike.find_operable_weapon happens to
## find first.
func _make_dual_armed_unit(cell: Vector2i, squad: int = 0) -> Unit:
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

	var saw := Part.new()
	saw.id = &"saw_hand"
	saw.hp = 4
	saw.max_hp = 4
	saw.attaches_to = [&"HAND"]
	saw.damage = 3.0
	saw.ap_cost = 1
	saw.scatter = [Ring.new(0.1, 1.0)]
	saw.provides_actions = [&"saw"]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var saw_socket := Socket.new(&"HAND")
	saw_socket.occupant = saw
	torso.sockets = [hand_socket, saw_socket]

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


## Pass A1: "a bare enemy click with no action armed does nothing."
func test_enemy_click_with_no_action_armed_does_not_enter_aim() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 5))

	assert_null(controller.aiming_at, "nothing armed — the click must be inert")
	assert_null(controller.armed_action)
	assert_eq(controller.selection.current_queue().actions.size(), 0)


## Pass A1: "arming SHOOT then clicking an enemy enters aim at that enemy."
func test_arming_shoot_then_clicking_an_enemy_enters_aim_at_that_enemy() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	assert_eq(controller.armed_action.id, &"shoot")

	controller.click_cell(Vector2i(5, 5))

	assert_eq(controller.aiming_at, b)


## Arming an id the selected unit has no provider for must not arm
## anything — the action bar itself would never offer it, but arm_action()
## guards the same invariant directly (ActionCatalog.actions_for is the
## single source of truth for "can this unit do this").
func test_arming_an_id_the_unit_cannot_provide_is_a_no_op() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)  # only provides &"shoot"
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))

	controller.arm_action(&"saw")

	assert_null(controller.armed_action)


## Pass A1: "Esc / RMB disarms the action and returns to normal selection."
func test_esc_disarms_an_armed_but_not_yet_aiming_action() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	assert_not_null(controller.armed_action)

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	controller._unhandled_input(esc)

	assert_null(controller.armed_action, "Esc disarms")
	assert_not_null(controller.selection.selected_unit, "back to normal selection, not deselected")

	# The disarm must be real, not cosmetic: an enemy click right after
	# still does nothing.
	controller.click_cell(Vector2i(5, 5))
	assert_null(controller.aiming_at)


func test_rmb_disarms_an_armed_but_not_yet_aiming_action() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	controller._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	controller._unhandled_input(up)

	assert_null(controller.armed_action)
	assert_not_null(controller.selection.selected_unit, "RMB disarms, it does not deselect")


## Pass A1: "this generalises... no per-action special-casing in the click
## handler." Arming SAW instead of SHOOT reaches aim mode through the exact
## same _click_unit()/confirm_shot() code path — the only thing that
## differs is which part ends up providing the queued AttackAction, read
## from the armed action's own id (ActionCatalog.provider_for), never a
## hardcoded weapon lookup.
func test_arming_saw_instead_of_shoot_picks_the_saw_not_the_gun() -> void:
	var a := _make_dual_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"saw")
	controller.click_cell(Vector2i(5, 5))
	controller.confirm_shot()

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	assert_eq(actions.size(), 1)
	var attack := actions[0] as AttackAction
	assert_not_null(attack)
	assert_eq(attack.weapon_id, &"saw_hand", "SAW armed must fire the saw, not the pistol")


## The mirror case: SHOOT armed on the same dual-armed unit must fire the
## pistol, not the saw — confirming the armed action, not part ORDER,
## decides the weapon.
func test_arming_shoot_on_a_dual_armed_unit_picks_the_gun_not_the_saw() -> void:
	var a := _make_dual_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	controller.confirm_shot()

	var actions: Array[CombatAction] = controller.selection.current_queue().actions
	var attack := actions[0] as AttackAction
	assert_not_null(attack)
	assert_eq(attack.weapon_id, &"pistol", "SHOOT armed must fire the pistol, not the saw")


## Arming an action mid-aim is a no-op — you're already committed to a
## target; arming a different action makes no sense until you back out.
func test_arming_while_already_aiming_is_a_no_op() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var armed_before: ActionDef = controller.armed_action

	controller.arm_action(&"shoot")

	assert_eq(controller.armed_action, armed_before)
	assert_eq(controller.aiming_at, b, "still aiming — arming mid-aim must not disturb it")


## ActionDef.requires_target = false (overwatch) keeps arming a documented
## no-op instead of misfiring an AttackAction through whichever part also
## lists &"shoot" — action_bar.gd/action_catalog.gd's own flagged gap:
## overwatch has no UI call site at all yet.
func test_arming_an_untargeted_action_is_a_no_op() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var pistol: Part = a.shell.find_part(&"pistol")
	pistol.provides_actions = [&"shoot", &"overwatch"]
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	var offered := false
	for def: ActionDef in ActionCatalog.actions_for(a):
		offered = offered or def.id == &"overwatch"
	assert_true(offered, "sanity: overwatch must actually be on the bar for this fixture")

	controller.arm_action(&"overwatch")

	assert_null(controller.armed_action, "overwatch does not need a target — arming it is a no-op")


func test_arm_action_with_nothing_selected_is_a_no_op() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller

	controller.arm_action(&"shoot")  # nothing selected: must not crash

	assert_null(controller.armed_action)


## Reselecting the current unit (a no-op selection) clears whatever was
## armed — a safety default, same posture as end_turn()/reset_turn().
func test_reselecting_the_current_unit_clears_an_armed_action() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")

	controller.click_cell(Vector2i(0, 0))

	assert_null(controller.armed_action)
