extends GutTest

## taskblock-08 Pass B1: the attack camera's own shooter — split out of
## test_tactics_controller_aim.gd purely to stay under gdlint's
## max-public-methods; same conventions (click_cell() driven directly, no
## live camera/viewport needed).


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


## taskblock-08 B1: "the camera frames the origin, not the ghost." With a
## move queued before entering aim, the shooter the camera actually frames
## must carry the queued END cell — the same speculative clone the ghost
## and the aim preview already read (taskblock-03 D5) — never the
## committed cell `selection.selected_unit` still visibly sits at.
func test_attack_framing_reads_the_queued_end_cell_not_the_committed_one() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(9, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	a.mp = 10.0

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 0))  # queue a move, still just queued
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(9, 0))  # enters aim mode

	assert_eq(a.cell, Vector2i(0, 0), "still just queued — the real unit has not moved")
	var framed_shooter: Unit = controller._framing_shooter()
	assert_eq(framed_shooter.cell, Vector2i(5, 0), "must frame the queued end cell, not (0, 0)")
	assert_eq(
		framed_shooter.cell,
		controller._end_position_ghost().cell,
		"the framed shooter and the ghost must coincide"
	)


func test_attack_framing_falls_back_to_the_committed_cell_with_no_move_queued() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))

	assert_eq(controller._framing_shooter().cell, Vector2i(0, 0))


## The whole point: two shooters at the same committed cell but different
## queued end cells must frame differently — `ease_to_attack_framing`
## itself receives a genuinely different bounding sphere, not just a
## differently-labeled Unit at the same geometry.
func test_framing_shooter_bounding_sphere_moves_with_the_queued_cell() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(9, 0), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	a.mp = 10.0
	var stale_sphere: Dictionary = UnitGeometry.bounding_sphere(a)

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(5, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(9, 0))

	var queued_sphere: Dictionary = UnitGeometry.bounding_sphere(controller._framing_shooter())
	assert_ne(
		(queued_sphere.center as Vector3).x,
		(stale_sphere.center as Vector3).x,
		"the framed shooter's own bounding sphere must have actually moved"
	)
