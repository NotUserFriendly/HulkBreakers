extends GutTest

## `HitVolumeView.show_assembly` — the resource editor's own bare-part-tree
## preview (docs/10 taskblock04 C1's "field object" case), replacing the
## taskblock-11 C throwaway matrix-hosting carrier. Locks in the two bugs
## that carrier caused: a rim-outline/facing-wedge "extraneous blue faces"
## overlay meant for real squads, and geometry drifting off-center as the
## preview pivot spins (fixed by recentering onto the origin here rather
## than trusting wherever the part's own volume happens to be authored).


func _offset_part(box_center: Vector3) -> Part:
	var part := Part.new()
	part.id = &"offset_part"
	part.hp = 4
	part.max_hp = 4
	part.volume = [Box.new(box_center, Vector3.ONE)]
	return part


func test_null_root_clears_the_view() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	view.show_assembly(_offset_part(Vector3.ZERO), DataLibrary.material_table(), Color.BLUE)
	assert_gt(view.get_child_count(), 0)

	view.show_assembly(null, DataLibrary.material_table(), Color.BLUE)
	assert_eq(view.get_child_count(), 0)


func test_draws_exactly_a_marker_plus_one_mesh_per_box_no_wedge() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	view.show_assembly(_offset_part(Vector3.ZERO), DataLibrary.material_table(), Color.BLUE)

	assert_eq(view.get_child_count(), 2, "marker disc + one part mesh, no facing wedge")


func test_marker_sits_at_the_origin_in_the_passed_color_never_team_color() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	view.show_assembly(
		_offset_part(Vector3(5.0, 0.0, 0.0)), DataLibrary.material_table(), Color.BLUE
	)

	var marker: MeshInstance3D = view.get_child(0)
	assert_eq(marker.position, Vector3(0.0, HitVolumeView.TEAM_MARKER_Y, 0.0))
	var material: StandardMaterial3D = marker.material_override
	assert_eq(material.albedo_color, Color.BLUE)


## The bug this fixes: a part authored off the rotation axis (any part
## whose own volume isn't centered at its own local origin) used to spin
## around that axis while visually orbiting away from screen center. The
## part's own box must render exactly at the origin, whatever its own
## authored `box.center` was.
func test_geometry_is_recentered_onto_the_origin() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	view.show_assembly(
		_offset_part(Vector3(5.0, 2.0, -3.0)), DataLibrary.material_table(), Color.BLUE
	)

	var mesh_instance: MeshInstance3D = view.get_child(1)
	assert_almost_eq(mesh_instance.transform.origin.x, 0.0, 0.0001)
	assert_almost_eq(mesh_instance.transform.origin.z, 0.0, 0.0001)
	# Only x/z are re-centered — the part's own authored elevation is real
	# data (docs/01's ROOT_ELEVATION), not an artifact to erase.
	assert_almost_eq(mesh_instance.transform.origin.y, 2.0, 0.0001)


## The other bug this fixes: a rim outline and facing wedge exist to read
## "this is your unit" on a real battlefield — neither concept applies to
## a single Part definition being edited, and both were the "extraneous...
## faces" reported against the old carrier approach.
func test_part_material_carries_no_rim_outline() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)

	view.show_assembly(_offset_part(Vector3.ZERO), DataLibrary.material_table(), Color.BLUE)

	var mesh_instance: MeshInstance3D = view.get_child(1)
	var box_mesh: BoxMesh = mesh_instance.mesh
	var material: StandardMaterial3D = box_mesh.material
	assert_null(material.next_pass, "no team rim outline on a bare-assembly preview")


func test_registers_meshes_by_part_for_hover_and_camera_framing() -> void:
	var view := HitVolumeView.new()
	add_child_autofree(view)
	var part := _offset_part(Vector3.ZERO)

	view.show_assembly(part, DataLibrary.material_table(), Color.BLUE)

	assert_true(view._meshes_by_part.has(part))
	assert_eq((view._meshes_by_part[part] as Array).size(), 1)
