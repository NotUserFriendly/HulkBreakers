extends GutTest

## docs/09 taskblock06 Pass I2: Part.mesh_scene / show_hit_volumes — split
## out from test_hit_volume_view.gd purely to stay under gdlint's
## max-public-methods (that file's own trailing convention).


func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := _piloted_torso()
	return Unit.new(torso.hosted_matrix, Shell.new(torso), cell, squad)


func _torso_with_arm_unit(cell: Vector2i) -> Dictionary:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.4, 0.9, 0.4))]

	var torso := _piloted_torso()
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets.append(shoulder)

	return {"unit": Unit.new(torso.hosted_matrix, Shell.new(torso), cell), "arm": arm}


func _piloted_torso() -> Part:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [Socket.new(&"MATRIX")]
	torso.dock_matrix(Matrix.new())
	return torso


## A minimal packable scene, distinct in kind from anything
## `_add_box_instance` builds (a bare Node3D, never a MeshInstance3D) so a
## test can tell "the commissioned mesh rendered" apart from "a hit-volume
## box rendered" without inspecting mesh contents.
func _make_mesh_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "CommissionedMesh"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## docs/09 taskblock06 Pass I2 TESTS: "a part with mesh_scene renders the
## mesh."
func test_a_part_with_mesh_scene_renders_the_commissioned_mesh() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.mesh_scene = _make_mesh_scene()
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var found: Node = null
	for child: Node in view.get_children():
		if child.name == "CommissionedMesh":
			found = child
	assert_not_null(found, "the commissioned mesh must actually be instantiated")
	assert_false(found is MeshInstance3D)


## docs/09 taskblock06 Pass I2 TESTS: "without, the hit volumes" — default
## show_hit_volumes (false) never draws a box for a part that HAS a mesh.
func test_a_part_with_mesh_scene_does_not_also_draw_its_box_by_default() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.mesh_scene = _make_mesh_scene()
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	# child 0/1 are the team marker/facing wedge overlays (also BoxMesh-
	# shaped, docs/10) — unrelated to per-part hit volumes, excluded here.
	for i in range(2, view.get_child_count()):
		var child: Node = view.get_child(i)
		assert_false(
			child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh,
			"no box instance may exist for a part that has a commissioned mesh"
		)


## docs/09 taskblock06 Pass I2 TESTS: "a mixed assembly renders both" — a
## rigged torso above a box arm, both representations present together.
func test_a_mixed_assembly_renders_the_mesh_and_the_box_together() -> void:
	var built: Dictionary = _torso_with_arm_unit(Vector2i(0, 0))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	unit.shell.root.mesh_scene = _make_mesh_scene()  # torso: commissioned
	# arm: left without a mesh_scene, still a plain hit-volume box.
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	var has_commissioned_mesh: bool = false
	var has_box_for_arm: bool = false
	for child: Node in view.get_children():
		if child.name == "CommissionedMesh":
			has_commissioned_mesh = true
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			var box_mesh: BoxMesh = (child as MeshInstance3D).mesh
			if box_mesh.size == arm.volume[0].size:
				has_box_for_arm = true
	assert_true(has_commissioned_mesh, "the torso's own commissioned mesh must render")
	assert_true(has_box_for_arm, "the arm, with no mesh_scene, must still render its hit volume")


## docs/09 taskblock06 Pass I2 TESTS: "HitVolumeView toggles independently
## of either" — show_hit_volumes overlays the box back on TOP of a
## commissioned mesh, without removing the mesh itself.
func test_show_hit_volumes_overlays_the_box_on_a_meshed_part_without_removing_the_mesh() -> void:
	var unit := _torso_unit(Vector2i(0, 0))
	unit.shell.root.mesh_scene = _make_mesh_scene()
	var view := HitVolumeView.new()
	add_child_autofree(view)
	view.setup(unit, DataLibrary.material_table())

	view.show_hit_volumes = true
	view.refresh()

	var has_commissioned_mesh: bool = false
	var has_box: bool = false
	# child 0/1 are the team marker/facing wedge overlays (also BoxMesh-
	# shaped, docs/10) — always present, unrelated to this part's own
	# hit-volume box, excluded so this test can't pass for the wrong reason.
	for i in range(2, view.get_child_count()):
		var child: Node = view.get_child(i)
		if child.name == "CommissionedMesh":
			has_commissioned_mesh = true
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			has_box = true
	assert_true(has_commissioned_mesh, "toggling hit volumes on must not remove the real mesh")
	assert_true(has_box, "toggling hit volumes on must add the box overlay")
