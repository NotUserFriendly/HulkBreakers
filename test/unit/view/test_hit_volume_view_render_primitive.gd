extends GutTest

## taskblock-10 Pass A: Part.render_primitive/render_scale/render_color_override
## — a placeholder look for a part with no mesh_scene. Split out from
## test_hit_volume_view_mesh_scene.gd for the same reason that file was split
## from test_hit_volume_view.gd (gdlint's max-public-methods).


func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := _piloted_torso()
	return Unit.new(torso.hosted_matrix, Shell.new(torso), cell, squad)


func _piloted_torso() -> Part:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.material = &"steel"
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [Socket.new(&"MATRIX")]
	torso.dock_matrix(Matrix.new())
	return torso


func _non_overlay_children(view: HitVolumeView) -> Array[Node]:
	# child 0/1 are the team marker/facing wedge overlays (docs/10) —
	# unrelated to per-part hit volumes, excluded everywhere below.
	var children: Array[Node] = []
	for i in range(2, view.get_child_count()):
		children.append(view.get_child(i))
	return children


## TEST: "a part with render_primitive = CYLINDER and no mesh renders a
## cylinder."
func test_a_part_with_render_primitive_cylinder_renders_a_cylinder() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.render_primitive = &"CYLINDER"
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var found_cylinder: bool = false
	for child: Node in _non_overlay_children(view):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
			found_cylinder = true
	assert_true(found_cylinder, "a CYLINDER render_primitive must instantiate a CylinderMesh")


## TEST: "with a mesh, the mesh" — mesh_scene still wins over
## render_primitive when both are set.
func test_mesh_scene_wins_over_render_primitive_when_both_are_set() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.render_primitive = &"CYLINDER"
	var root := Node3D.new()
	root.name = "CommissionedMesh"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	unit.shell.root.mesh_scene = packed
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var has_commissioned_mesh: bool = false
	var has_cylinder: bool = false
	for child: Node in _non_overlay_children(view):
		if child.name == "CommissionedMesh":
			has_commissioned_mesh = true
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
			has_cylinder = true
	assert_true(has_commissioned_mesh, "mesh_scene must still render")
	assert_false(has_cylinder, "render_primitive must not also render once mesh_scene wins")


## TEST: "the volume boxes (and thus the shot plane) are identical in all
## cases" — BOX (default), CYLINDER, and mesh_scene never change what
## BodyProjector/ShotPlane read.
func test_render_primitive_never_changes_the_parts_own_volume() -> void:
	var box_unit := _torso_unit(Vector2i(0, 0))
	var box_size: Vector3 = box_unit.shell.root.volume[0].size

	var cylinder_unit := _torso_unit(Vector2i(1, 0))
	cylinder_unit.shell.root.render_primitive = &"CYLINDER"

	assert_eq(cylinder_unit.shell.root.volume[0].size, box_size)
	assert_eq(cylinder_unit.shell.root.volume[0].center, box_unit.shell.root.volume[0].center)


## TEST: "render_scale scales the primitive, not the hitboxes."
func test_render_scale_scales_the_primitive_instance_only() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.render_primitive = &"CYLINDER"
	unit.shell.root.render_scale = Vector3(2.0, 3.0, 2.0)
	var original_box_size: Vector3 = unit.shell.root.volume[0].size
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var found: MeshInstance3D = null
	for child: Node in _non_overlay_children(view):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
			found = child
	assert_not_null(found)
	assert_eq(found.scale, Vector3(2.0, 3.0, 2.0), "the instance's own scale must carry render_scale")
	assert_eq(unit.shell.root.volume[0].size, original_box_size, "the hitbox itself must be untouched")


## TEST: a BOX render_primitive (the default) draws exactly the existing
## box-per-placement render — no primitive instance, no behavior change.
func test_render_primitive_box_is_the_existing_box_render_unchanged() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var has_box: bool = false
	for child: Node in _non_overlay_children(view):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			has_box = true
	assert_true(has_box, "the default BOX primitive must still draw the plain hit-volume box")


## TEST: render_color_override, when set (alpha > 0), overrides the
## part's material colour on the primitive.
func test_render_color_override_replaces_the_material_colour() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.render_primitive = &"CYLINDER"
	unit.shell.root.render_color_override = Color(1.0, 0.0, 0.0, 1.0)
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, MaterialTable.default_table())

	var found: MeshInstance3D = null
	for child: Node in _non_overlay_children(view):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
			found = child
	assert_not_null(found)
	var material: StandardMaterial3D = (found.mesh as CylinderMesh).material
	assert_eq(material.albedo_color, Color(1.0, 0.0, 0.0, 1.0))


## TEST: the (0,0,0,0) default sentinel falls back to the part's material
## colour, same lookup a hit-volume box already uses.
func test_default_render_color_override_falls_back_to_material_colour() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.render_primitive = &"CYLINDER"
	var table := MaterialTable.default_table()
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, table)

	var found: MeshInstance3D = null
	for child: Node in _non_overlay_children(view):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
			found = child
	assert_not_null(found)
	var material: StandardMaterial3D = (found.mesh as CylinderMesh).material
	assert_eq(material.albedo_color, table.color_for(&"steel"))
