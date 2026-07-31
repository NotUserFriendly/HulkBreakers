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
	var state := CombatState.new(GridFixture.flat(10, 10), units)
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


# --- taskblock-51 (BR26.02): per-element switches for bisecting the GPU cost ----------


func after_each() -> void:
	BoardView.show_wall_cutout = true
	BattleScene.show_occlusion_fade = true
	AimView.show_window = true
	AimView.show_decal = true
	AimView.show_targeting_line = true
	AimView.show_pellet_circle = true
	AimView.show_part_label = true


## **The switches must actually reach the nodes**, or the supervisor bisects against a
## control that does nothing and concludes the wrong element is innocent — which is worse
## than not having the tool.
func test_turning_an_aim_visual_off_hides_exactly_that_node() -> void:
	AimView.show_decal = false

	var injector := BoutInjector.new(CombatState.new(GridFixture.flat(5, 5), []))
	assert_true(
		DebugVerbs._apply_set_aim_visual(injector, {}, {"element": &"decal", "on": false}),
		"the verb accepts a real element"
	)
	assert_false(AimView.show_decal, "and the switch is off")

	DebugVerbs._apply_set_aim_visual(injector, {}, {"element": &"decal", "on": true})
	assert_true(AimView.show_decal, "and back on")


## An unknown element is refused rather than quietly doing nothing — a typo that reads as
## "that element costs nothing" would send the hunt down a false trail.
func test_an_unknown_aim_visual_is_refused() -> void:
	var injector := BoutInjector.new(CombatState.new(GridFixture.flat(5, 5), []))

	assert_false(
		DebugVerbs._apply_set_aim_visual(injector, {}, {"element": &"nonsense", "on": false})
	)


## **Toggling a visual is not an injection.** `was_injected` marks a bout whose results
## cannot be trusted; hiding a decal changes nothing about the simulation, and flagging it
## would make every framerate experiment look like a tainted bout.
func test_toggling_a_visual_never_marks_the_bout_injected() -> void:
	var state := CombatState.new(GridFixture.flat(5, 5), [])
	var injector := BoutInjector.new(state)

	DebugVerbs._apply_set_aim_visual(injector, {}, {"element": &"window", "on": false})

	assert_false(state.was_injected, "a display toggle does not dirty the bout")


## **The dropdown's options and the verb's own switch table must not drift apart.** A name
## offered in the menu that the verb refuses is a dead control; a name the verb accepts but
## the menu never offers is unreachable. Both are the kind of gap that costs a hunting
## session before anyone notices.
func test_every_offered_element_is_one_the_verb_accepts() -> void:
	var injector := BoutInjector.new(CombatState.new(GridFixture.flat(5, 5), []))

	for element: StringName in AimView.TOGGLEABLE:
		assert_true(
			DebugVerbs._apply_set_aim_visual(injector, {}, {"element": element, "on": false}),
			"the dropdown offers %s, so the verb must accept it" % element
		)
		DebugVerbs._apply_set_aim_visual(injector, {}, {"element": element, "on": true})


## The two non-`AimView` switches exist because the first bisection cleared every aim
## element — so they have to actually reach the classes that own them.
func test_the_gpu_switches_reach_their_own_classes() -> void:
	var injector := BoutInjector.new(CombatState.new(GridFixture.flat(5, 5), []))

	DebugVerbs._apply_set_aim_visual(injector, {}, {"element": &"wall_cutout", "on": false})
	DebugVerbs._apply_set_aim_visual(injector, {}, {"element": &"occlusion_fade", "on": false})

	assert_false(BoardView.show_wall_cutout, "the cutout switch reaches BoardView")
	assert_false(BattleScene.show_occlusion_fade, "and the fade switch reaches BattleScene")
