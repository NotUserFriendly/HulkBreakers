extends GutTest

## runNotes.md: "Dartboard isn't following the cursor exactly instead being
## offset" — split out of test_tactics_controller_aim.gd purely to stay
## under gdlint's max-public-methods; same conventions.


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


## The actual contract: wherever the literal cursor points on screen, the
## reticle lands there — a screen position aimed at a KNOWN world point
## (via the camera's own unproject) must recover that same point's
## aim_point, round-tripped through AimPlaneGeometry the same way AimView's
## rendering does.
func test_aim_reticle_at_screen_points_the_reticle_at_the_cursors_own_target() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	var wanted_aim_point := Vector2(0.15, 0.2)
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, wanted_aim_point
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)

	controller.aim_reticle_at_screen(screen_pos)

	var expected_offset: Vector2 = wanted_aim_point - ShotPlane.center_of(aim["plane"], target.unit)
	assert_almost_eq(controller.reticle_offset.x, expected_offset.x, 0.01)
	assert_almost_eq(controller.reticle_offset.y, expected_offset.y, 0.01)


func test_aim_reticle_at_screen_does_nothing_outside_aim_mode() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))  # selected, not aiming

	controller.aim_reticle_at_screen(Vector2(100.0, 100.0))

	assert_eq(controller.reticle_offset, Vector2.ZERO)


func test_aim_reticle_at_screen_does_nothing_while_input_locked() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	controller.input_locked = true

	controller.aim_reticle_at_screen(Vector2(100.0, 100.0))

	assert_eq(controller.reticle_offset, Vector2.ZERO)


## tb34 Pass C: "mousing over a part while aiming should say what that part
## is" — a cursor position aimed at a KNOWN world point on the target's own
## torso (the same round-trip the reticle's own test above uses) must find
## that exact Part, the same `ShotPlane.region_at` rect-containment
## `resolves` itself is built from.
func test_update_aim_hover_finds_the_part_under_the_cursor() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	# Dead center of the torso's own frontmost region -- guaranteed to fall
	# inside it, not near an edge.
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, Vector2.ZERO
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)

	controller.update_aim_hover(screen_pos)

	assert_not_null(controller.aim_hovered_part)
	assert_eq(controller.aim_hovered_part.id, &"torso")


func test_update_aim_hover_over_empty_space_finds_nothing() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	# Far outside the torso's own narrow box (Box half-width 1.0/half-
	# height 0.5) -- clean past every region in the plane.
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, Vector2(5.0, 5.0)
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)

	controller.update_aim_hover(screen_pos)

	assert_null(controller.aim_hovered_part)


## The load-bearing guarantee: "hovering reads, it never re-aims." Calling
## update_aim_hover() alone -- never aim_reticle_at_screen() -- must never
## touch reticle_offset, proof the two are structurally independent, not
## just documented as such.
func test_update_aim_hover_never_touches_the_reticle() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, Vector2.ZERO
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)

	controller.update_aim_hover(screen_pos)

	assert_eq(controller.reticle_offset, Vector2.ZERO, "hover alone must never move the reticle")


func test_update_aim_hover_does_nothing_outside_aim_mode() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var built: Dictionary = _setup([a])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))  # selected, not aiming

	controller.update_aim_hover(Vector2(100.0, 100.0))

	assert_null(controller.aim_hovered_part)


func test_update_aim_hover_does_nothing_while_input_locked() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, Vector2.ZERO
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)
	controller.input_locked = true

	controller.update_aim_hover(screen_pos)

	assert_null(controller.aim_hovered_part)


## aim_reticle_at_screen() itself must still keep the hover in sync (same
## screen position drives both), never diverging from a direct
## update_aim_hover() call at the identical position.
func test_aim_reticle_at_screen_also_updates_the_hover() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, Vector2.ZERO
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)

	controller.aim_reticle_at_screen(screen_pos)

	assert_not_null(controller.aim_hovered_part)
	assert_eq(controller.aim_hovered_part.id, &"torso")
