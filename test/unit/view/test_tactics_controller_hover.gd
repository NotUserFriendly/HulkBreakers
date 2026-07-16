extends GutTest

## docs/10 taskblock04 E3: "hover, don't click" — split out of
## test_tactics_controller.gd purely to stay under gdlint's
## max-public-methods; same conventions (driven directly, no live camera
## required except where a real Camera3D projection is the point).


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	root.volume = [Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))]
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


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


## The real end-to-end path: a screen position over a known cell must
## resolve to that cell via the same camera projection a live cursor uses.
func test_update_hover_resolves_a_screen_position_to_the_cell_underneath() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	var target_cell := Vector2i(3, 4)
	var world_point: Vector3 = Vector3(target_cell.x, 0.0, target_cell.y) * UnitGeometry.CELL_SIZE
	var screen_pos: Vector2 = camera_rig.camera().unproject_position(world_point)

	controller.update_hover(screen_pos)

	assert_eq(controller.hovered_cell, target_cell)


func test_update_hover_emits_hover_changed_only_on_an_actual_change() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	var screen_pos: Vector2 = camera_rig.camera().unproject_position(
		Vector3(2.0, 0.0, 2.0) * UnitGeometry.CELL_SIZE
	)

	# GDScript lambdas capture outer locals by value — mutate an Array's
	# own contents in place rather than reassigning a plain int, or the
	# increment would never be visible outside the lambda.
	var fire_count: Array[int] = [0]
	controller.hover_changed.connect(func() -> void: fire_count[0] += 1)

	controller.update_hover(screen_pos)
	assert_eq(fire_count[0], 1)

	controller.update_hover(screen_pos)
	assert_eq(fire_count[0], 1, "hovering the exact same cell again must not re-fire")


## docs/10 taskblock04 E3: "clicking a part in the inventory panel fills
## the same readout" — inspect_part() sets inspected_part and signals.
func test_inspect_part_sets_the_field_and_emits_hover_changed() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var part := Part.new()
	part.id = &"pistol"

	var fired: Array[bool] = [false]
	controller.hover_changed.connect(func() -> void: fired[0] = true)
	controller.inspect_part(part)

	assert_eq(controller.inspected_part, part)
	assert_true(fired[0])


## A fresh board hover always wins over a stale inventory click — E3's
## "one readout, three sources" implies whichever the player is actually
## pointing at right now takes over.
func test_hovering_the_board_again_clears_a_previously_inspected_part() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	controller.inspect_part(Part.new())
	assert_not_null(controller.inspected_part)

	var screen_pos: Vector2 = camera_rig.camera().unproject_position(
		Vector3(1.0, 0.0, 1.0) * UnitGeometry.CELL_SIZE
	)
	controller.update_hover(screen_pos)

	assert_null(controller.inspected_part)
	assert_eq(controller.hovered_cell, Vector2i(1, 1))


func test_update_hover_off_the_board_entirely_clears_hovered_cell() -> void:
	var built: Dictionary = _setup([])
	var controller: TacticsController = built.controller
	var camera_rig: CameraRig = built.camera_rig
	var camera: Camera3D = camera_rig.camera()
	controller.update_hover(camera.unproject_position(Vector3(1.0, 0.0, 1.0)))
	assert_not_null(controller.hovered_cell)

	# Basis.IDENTITY looks along world -Z, exactly horizontal (dir.y == 0) —
	# the dead center of the viewport is then the camera's own forward, the
	# one ray BoardPicker.plane_hit_t's own is_zero_approx(dir.y) guard is
	# built for: parallel to the board plane, never crosses it.
	camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(5.0, 10.0, 5.0))
	var viewport_center: Vector2 = Vector2(camera.get_viewport().size) * 0.5
	controller.update_hover(viewport_center)

	assert_null(controller.hovered_cell)
