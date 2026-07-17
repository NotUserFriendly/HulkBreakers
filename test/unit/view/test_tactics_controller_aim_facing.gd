extends GutTest

## docs/10 taskblock05 A3: "if the free face only lands at apply() time, the
## preview lies" — entering aim must orient the shooter toward the target in
## the SPECULATIVE preview immediately, so the projected shot plane (and the
## wedge) reflect the facing the shooter will actually have, not whatever it
## was queued to before aiming. Split out of test_tactics_controller_aim.gd
## purely to stay under gdlint's max-public-methods; same conventions
## (click_cell() driven directly, no live camera/viewport needed).


## torso -[HAND]- hand(TRIGGER) -[GRIP]- pistol, same shape
## test_attack_action.gd uses, so the shooter can actually fire — plus a
## torso box offset along local +X, which makes the projected region's
## lateral position orientation-sensitive: a wrong facing projects it onto
## the wrong side of the shot plane entirely, not just a slightly different
## spot on the same side.
func _make_lopsided_armed_unit(cell: Vector2i, orientation: float, squad: int = 0) -> Unit:
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
	torso.volume = [Box.new(Vector3(0.5, 0.5, 0.0), Vector3(0.4, 1.0, 0.4))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad)
	unit.orientation = orientation
	return unit


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


func test_entering_aim_orients_the_shooter_at_the_target_in_the_preview() -> void:
	# Target sits due north; starting orientation faces due south — as
	# wrong as it can be.
	var a := _make_lopsided_armed_unit(Vector2i(0, 0), PI, 0)
	var b := _make_lopsided_armed_unit(Vector2i(0, 5), 0.0, 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(0, 5))
	var aim: Dictionary = controller.aim_state()

	var expected: float = FaceAction.orientation_toward(a.cell, b.cell)
	assert_eq((aim["shooter"] as Unit).orientation, expected)
	assert_ne(
		(aim["shooter"] as Unit).orientation, PI, "the stale pre-aim orientation must not survive"
	)
	# The real, authoritative unit is untouched — this is a scratch preview.
	assert_eq(a.orientation, PI)


## docs/10 taskblock05 A3: "the previewed shot plane uses that facing" —
## the shooter's own regions are excluded from `aim["plane"]` by design
## (they'd otherwise resolve as a phantom nearest layer), so the
## observable surface for the shooter's OWN corrected geometry is
## UnitGeometry.placements() on `aim["shooter"]` — the exact thing
## aim_view.gd's muzzle point (the dartboard's targeting line origin)
## reads. A stale facing would put that box on the wrong side of the body
## entirely, not just slightly off.
func test_the_previewed_shooters_own_geometry_uses_the_corrected_facing() -> void:
	var a := _make_lopsided_armed_unit(Vector2i(0, 0), PI, 0)
	var b := _make_lopsided_armed_unit(Vector2i(0, 5), 0.0, 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(0, 5))
	var aim: Dictionary = controller.aim_state()
	var shooter: Unit = aim["shooter"]

	var torso_placement: BoxPlacement = null
	for placement: BoxPlacement in UnitGeometry.placements(shooter):
		if placement.part.id == &"torso":
			torso_placement = placement
			break
	assert_not_null(torso_placement)

	var actual_world: Vector3 = torso_placement.transform * torso_placement.box.center
	var correct_world: Vector3 = (
		UnitGeometry.placements(shooter, 0.0)[0].transform
		* UnitGeometry.placements(shooter, 0.0)[0].box.center
	)
	var stale_world: Vector3 = (
		UnitGeometry.placements(shooter, PI)[0].transform
		* UnitGeometry.placements(shooter, PI)[0].box.center
	)
	assert_true(actual_world.is_equal_approx(correct_world))
	assert_false(
		actual_world.is_equal_approx(stale_world),
		"the stale facing would have placed the box on the other side of the body entirely"
	)


func test_the_free_face_costs_nothing_and_is_idempotent_across_enter_cancel_enter() -> void:
	var a := _make_lopsided_armed_unit(Vector2i(0, 0), PI, 0)
	var b := _make_lopsided_armed_unit(Vector2i(0, 5), 0.0, 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var starting_ap: int = a.ap
	var starting_mp: float = a.mp

	controller.click_cell(Vector2i(0, 0))
	controller.click_cell(Vector2i(0, 5))
	var first: Dictionary = controller.aim_state()
	controller.cancel_aim()

	controller.click_cell(Vector2i(0, 5))
	var second: Dictionary = controller.aim_state()

	assert_eq((first["shooter"] as Unit).orientation, (second["shooter"] as Unit).orientation)
	assert_eq(a.ap, starting_ap, "the free face must never spend AP")
	assert_eq(a.mp, starting_mp, "the free face must never spend MP")
	assert_eq(a.orientation, PI, "the real unit's own orientation is never touched by aiming alone")
