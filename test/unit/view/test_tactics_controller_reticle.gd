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
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var wanted_aim_point := Vector2(0.15, 0.2)
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, (aim["target"] as Unit).cell, wanted_aim_point
	)
	var screen_pos: Vector2 = controller.camera.unproject_position(world)

	controller.aim_reticle_at_screen(screen_pos)

	var expected_offset: Vector2 = (
		wanted_aim_point - ShotPlane.center_of(aim["plane"], aim["target"])
	)
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
	controller.click_cell(Vector2i(5, 5))
	controller.input_locked = true

	controller.aim_reticle_at_screen(Vector2(100.0, 100.0))

	assert_eq(controller.reticle_offset, Vector2.ZERO)
