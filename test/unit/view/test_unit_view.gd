extends GutTest

## docs/10 "render is hitbox": UnitView must spawn exactly one mesh per
## living box UnitGeometry.placements() reports, at exactly that transform,
## and rebuild on refresh() so destroyed parts vanish.


func _torso_unit(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Frame.new(torso), cell)


func _torso_with_arm_unit(cell: Vector2i) -> Dictionary:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	return {"unit": Unit.new(Matrix.new(), Frame.new(torso), cell), "arm": arm}


func test_setup_spawns_one_mesh_per_living_box() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())
	assert_eq(view.get_child_count(), 1)


func test_refresh_after_a_part_is_destroyed_removes_its_mesh() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm

	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())
	assert_eq(view.get_child_count(), 2, "torso + arm")

	arm.hp = 0
	view.refresh()
	assert_eq(view.get_child_count(), 1, "the destroyed arm's mesh must disappear")


func test_mesh_transform_matches_unit_geometry_exactly() -> void:
	var unit := _torso_unit(Vector2i(3, 4))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var expected: BoxPlacement = UnitGeometry.placements(unit)[0]
	var mesh_instance: MeshInstance3D = view.get_child(0)
	assert_eq(mesh_instance.transform, expected.transform.translated_local(expected.box.center))


func test_mesh_size_matches_the_box_size_exactly() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var mesh_instance: MeshInstance3D = view.get_child(0)
	var box_mesh: BoxMesh = mesh_instance.mesh
	assert_eq(box_mesh.size, Vector3(2.0, 1.0, 0.6))
