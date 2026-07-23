extends GutTest

## tb34 Pass C: "mousing over a part while aiming should say what that part
## is" — the aim view's own in-world part label. Full wiring (a real
## TacticsController/BoardView/CameraRig/AimView, same shape
## test_tactics_controller_aim.gd's own `_setup()` uses) so `refresh()`
## draws from real `aim_state()`/`update_aim_hover()` output, not a
## hand-built AimResult.


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
	torso.material = &"steel"
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
	var readout := RichTextLabel.new()
	add_child_autofree(readout)
	var aim_view := AimView.new()
	add_child_autofree(aim_view)
	aim_view.setup(controller, readout, DataLibrary.material_table())
	return {"state": state, "controller": controller, "aim_view": aim_view}


## One builder, no parallel text: the label's own content must be exactly
## what TooltipBuilder.for_part/TooltipView.to_plain_text produce for the
## hovered part — never a re-derived string built inside aim_view.gd.
func test_hovering_a_part_yields_that_parts_tooltip_content() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var aim_view: AimView = built.aim_view

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	# The default aim point (zero reticle offset) is the target's own
	# frontmost region's center -- not necessarily plane-local (0,0), which
	# can land on whatever part physically sticks out furthest (a gripped
	# weapon's own hand, say). Whichever part is actually frontmost there
	# is exactly what a hover at that point must find.
	var aim_point: Vector2 = ShotPlane.center_of(aim["plane"], target.unit)
	var expected_part: Part = ShotPlane.region_at(aim["plane"], aim_point).part
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, aim_point
	)
	controller.update_aim_hover(controller.camera.unproject_position(world))
	aim_view.refresh()

	var expected: String = TooltipView.to_plain_text(
		TooltipBuilder.for_part(expected_part, DataLibrary.material_table())
	)
	assert_eq(aim_view._part_label.text, expected)
	assert_true(aim_view._part_label.visible)


func test_hovering_empty_space_shows_nothing() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var aim_view: AimView = built.aim_view

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, Vector2(5.0, 5.0)
	)
	controller.update_aim_hover(controller.camera.unproject_position(world))
	aim_view.refresh()

	assert_null(controller.aim_hovered_part)
	assert_false(aim_view._part_label.visible)


## docs/10 rule 2: read the real node's global_transform back, don't
## re-derive it. The label must sit coplanar with the aim window — same
## basis (the plane's own facing), a real 3D offset apart only along the
## shared normal (the small forward nudge that keeps it from z-fighting).
func test_the_part_labels_transform_is_coplanar_with_the_aim_window() -> void:
	var a := _make_armed_unit(Vector2i(0, 0), 0)
	var b := _make_armed_unit(Vector2i(5, 5), 1)
	var built: Dictionary = _setup([a, b])
	var controller: TacticsController = built.controller
	var aim_view: AimView = built.aim_view

	controller.click_cell(Vector2i(0, 0))
	controller.arm_action(&"shoot")
	controller.click_cell(Vector2i(5, 5))
	var aim: Dictionary = controller.aim_state()
	var target: AimTarget = aim["target"]
	var aim_point: Vector2 = ShotPlane.center_of(aim["plane"], target.unit)
	var world: Vector3 = AimPlaneGeometry.world_point(
		(aim["shooter"] as Unit).cell, target.cell, aim_point
	)
	controller.update_aim_hover(controller.camera.unproject_position(world))
	aim_view.refresh()

	var window_xform: Transform3D = aim_view._window.global_transform
	var label_xform: Transform3D = aim_view._part_label.global_transform

	assert_true(
		window_xform.basis.is_equal_approx(label_xform.basis),
		"the label must share the window's own facing basis, not a separately-derived one"
	)
	var offset: Vector3 = label_xform.origin - window_xform.origin
	assert_almost_eq(offset.length(), AimView.PART_LABEL_DEPTH_OFFSET, 0.001)
