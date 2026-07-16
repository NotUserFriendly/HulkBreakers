extends GutTest

## docs/10 "render is hitbox": UnitView must spawn exactly one mesh per
## living box UnitGeometry.placements() reports, at exactly that transform,
## and rebuild on refresh() so destroyed parts vanish. Team flagging
## (docs/10) adds a ground marker (child 0) and a facing wedge (docs/10
## taskblock02 F3, child 1) ahead of the part meshes — both overlays,
## never touching a part's own material.


func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


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

	return {"unit": Unit.new(Matrix.new(), Shell.new(torso), cell), "arm": arm}


func test_setup_spawns_the_team_marker_plus_one_mesh_per_living_box() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())
	assert_eq(view.get_child_count(), 3, "team marker + facing wedge + one part mesh")


func test_refresh_after_a_part_is_destroyed_removes_its_mesh() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm

	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())
	assert_eq(view.get_child_count(), 4, "team marker + facing wedge + torso + arm")

	arm.hp = 0
	view.refresh()
	assert_eq(view.get_child_count(), 3, "the destroyed arm's mesh must disappear")


func test_mesh_transform_matches_unit_geometry_exactly() -> void:
	var unit := _torso_unit(Vector2i(3, 4))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var expected: BoxPlacement = UnitGeometry.placements(unit)[0]
	var mesh_instance: MeshInstance3D = view.get_child(2)
	assert_eq(mesh_instance.transform, expected.transform.translated_local(expected.box.center))


func test_mesh_size_matches_the_box_size_exactly() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var mesh_instance: MeshInstance3D = view.get_child(2)
	var box_mesh: BoxMesh = mesh_instance.mesh
	assert_eq(box_mesh.size, Vector3(2.0, 1.0, 0.6))


func test_part_material_is_lit_not_unshaded() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var mesh_instance: MeshInstance3D = view.get_child(2)
	var box_mesh: BoxMesh = mesh_instance.mesh
	var material: StandardMaterial3D = box_mesh.material
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL)


func test_part_material_carries_a_rim_outline_next_pass() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var mesh_instance: MeshInstance3D = view.get_child(2)
	var box_mesh: BoxMesh = mesh_instance.mesh
	var material: StandardMaterial3D = box_mesh.material
	assert_not_null(material.next_pass, "a rim outline pass must ride the part's own material")


## docs/10 taskblock02 F3: "a facing wedge on the ring."
func test_facing_wedge_sits_at_child_1_pointing_along_orientation() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	unit.orientation = PI / 2.0
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var wedge: MeshInstance3D = view.get_child(1)
	var forward: Vector2 = BodyProjector.WORLD_FORWARD.rotated(unit.orientation)
	var expected_xz := Vector2(2.0, 3.0) + forward * UnitView.FACING_WEDGE_OFFSET
	assert_almost_eq(wedge.position.x, expected_xz.x, 0.0001)
	assert_almost_eq(wedge.position.z, expected_xz.y, 0.0001)


## docs/10 taskblock03 E3: "the wedge shows committed state — it must show
## PREVIEW." Both the wedge and the part meshes must rotate to
## preview_orientation, never the committed unit.orientation, whenever one
## is set.
func test_preview_orientation_moves_both_the_wedge_and_the_part_meshes() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	unit.orientation = 0.0
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())
	var committed_wedge_x: float = (view.get_child(1) as MeshInstance3D).position.x
	var committed_mesh_transform: Transform3D = (view.get_child(2) as MeshInstance3D).transform

	view.preview_orientation = PI / 2.0
	view.refresh()

	var preview_wedge_x: float = (view.get_child(1) as MeshInstance3D).position.x
	var preview_mesh_transform: Transform3D = (view.get_child(2) as MeshInstance3D).transform
	assert_ne(preview_wedge_x, committed_wedge_x, "the wedge must move to the preview")
	assert_ne(
		preview_mesh_transform, committed_mesh_transform, "the body itself must also rotate"
	)
	assert_almost_eq(unit.orientation, 0.0, 0.0001, "the real unit is never mutated by a preview")


func test_null_preview_orientation_renders_the_committed_orientation() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 0)
	unit.orientation = 0.5
	var view := UnitView.new()
	add_child_autofree(view)
	view.preview_orientation = null
	view.setup(unit, MaterialTable.default_table())

	var expected: BoxPlacement = UnitGeometry.placements(unit)[0]
	var mesh_instance: MeshInstance3D = view.get_child(2)
	assert_eq(mesh_instance.transform, expected.transform.translated_local(expected.box.center))


func test_team_marker_sits_at_the_units_cell_and_matches_its_squad_color() -> void:
	var unit := _torso_unit(Vector2i(2, 3), 1)
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var marker: MeshInstance3D = view.get_child(0)
	assert_almost_eq(marker.position.x, 2.0, 0.0001)
	assert_almost_eq(marker.position.z, 3.0, 0.0001)
	var material: StandardMaterial3D = marker.material_override
	assert_eq(material.albedo_color, WorldPalette.TEAM_B)


func test_set_selected_brightens_the_team_marker() -> void:
	var unit := _torso_unit(Vector2i(0, 0), 0)
	var view := UnitView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var marker: MeshInstance3D = view.get_child(0)
	var before: Color = (marker.material_override as StandardMaterial3D).albedo_color

	view.set_selected(true)
	var after: Color = (marker.material_override as StandardMaterial3D).albedo_color

	assert_ne(before, after, "selecting must visibly brighten the marker")
	assert_eq(before, WorldPalette.TEAM_A, "sanity: unselected must be the plain team color")
