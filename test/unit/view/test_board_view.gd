extends GutTest

## docs/10: BoardView is pure presentation — a ground plane sized to the
## grid, plus one box per blocker box, plus a separate TACTICS overlay
## (reachable highlight / ghost paths). It never mutates Grid.


func test_build_spawns_a_ground_plane_and_one_box_per_blocker() -> void:
	var grid := Grid.new(4, 3)
	var rack := Part.new()
	rack.id = &"rack"
	rack.hp = 5
	rack.max_hp = 5
	rack.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.blockers[Vector2i(1, 1)] = rack

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, MaterialTable.default_table())

	# +1: the grid-line mesh (docs/10 taskblock02 G3), always present.
	assert_eq(view._static.get_child_count(), 3, "ground plane + grid lines + the one blocker box")


## docs/10 taskblock02 G3: a line per cell boundary on both axes, spanning
## exactly the grid's own footprint (half a cell of margin on every edge,
## same as the ground plane).
func test_build_draws_grid_lines_spanning_the_grids_own_footprint() -> void:
	var grid := Grid.new(4, 3)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, MaterialTable.default_table())

	var mesh: ImmediateMesh = view._static.get_child(1).mesh
	assert_not_null(mesh, "the grid-line mesh must be the second static child")
	assert_eq(mesh.get_surface_count(), 1)

	var cell_size: float = UnitGeometry.CELL_SIZE
	var half: float = cell_size * 0.5
	var aabb: AABB = mesh.get_aabb()
	assert_almost_eq(aabb.position.x, -half, 0.0001)
	assert_almost_eq(aabb.position.z, -half, 0.0001)
	assert_almost_eq(aabb.end.x, (grid.width - 1) * cell_size + half, 0.0001)
	assert_almost_eq(aabb.end.z, (grid.height - 1) * cell_size + half, 0.0001)


func test_build_clears_previous_children_on_rebuild() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, MaterialTable.default_table())
	var first_count: int = view._static.get_child_count()
	view.build(grid, MaterialTable.default_table())

	assert_eq(
		view._static.get_child_count(), first_count, "rebuilding must not accumulate children"
	)


func test_a_destroyed_blocker_spawns_no_mesh() -> void:
	var grid := Grid.new(2, 2)
	var dead := Part.new()
	dead.id = &"dead"
	dead.hp = 0
	dead.max_hp = 5
	dead.volume = [Box.new(Vector3.ZERO, Vector3(1, 1, 1))]
	grid.blockers[Vector2i(0, 0)] = dead

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, MaterialTable.default_table())

	assert_eq(
		view._static.get_child_count(),
		2,
		"ground plane + grid lines; a dead blocker contributes nothing"
	)


func test_show_reachable_spawns_one_marker_per_cell_and_replaces_the_last_call() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	assert_eq(view._reachable_overlay.get_child_count(), 3)

	view.show_reachable([Vector2i(0, 0)])
	assert_eq(
		view._reachable_overlay.get_child_count(), 1, "a new call must replace the old overlay"
	)


## docs/10 taskblock03 D2: each leg is a marker per cell, plus its own
## polyline, plus one numbered waypoint label at its destination.
func test_show_ghost_paths_spawns_a_marker_line_and_label_per_leg() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0)]])
	assert_eq(
		view._ghost_overlay.get_child_count(),
		8,
		"(2 cell markers + 1 line + 1 label) per leg, 2 legs",
	)


func test_show_ghost_paths_numbers_waypoints_and_shows_the_running_total() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_ghost_paths(
		[[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]],
		[1.0, 2.0]
	)

	var labels: Array[Label3D] = []
	for child: Node in view._ghost_overlay.get_children():
		if child is Label3D:
			labels.append(child)
	assert_eq(labels.size(), 2)
	assert_true(labels[0].text.begins_with("1:"), "the first leg is waypoint 1")
	assert_true(labels[1].text.begins_with("2:"), "the second leg is waypoint 2")
	assert_true(labels[1].text.contains("3.0"), "the running total across both legs is 1+2")


func test_reachable_and_ghost_overlays_coexist() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])

	assert_eq(view._reachable_overlay.get_child_count(), 2, "ghosts must not clobber reachable")
	assert_eq(view._ghost_overlay.get_child_count(), 4, "2 cell markers + 1 line + 1 label")


func test_clear_overlays_removes_everything() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])
	view.show_unit_ghost(_torso_unit(Vector2i(0, 0)))
	view.clear_overlays()
	assert_eq(view._reachable_overlay.get_child_count(), 0)
	assert_eq(view._ghost_overlay.get_child_count(), 0)
	assert_eq(view._unit_ghost_overlay.get_child_count(), 0)


func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## docs/10 taskblock03 F1: "a translucent ghost of the unit where it will
## end up... at its final facing."
func test_show_unit_ghost_spawns_one_translucent_mesh_per_living_box() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_unit_ghost(_torso_unit(Vector2i(3, 4)))

	assert_eq(view._unit_ghost_overlay.get_child_count(), 1)
	var instance: MeshInstance3D = view._unit_ghost_overlay.get_child(0)
	var material: StandardMaterial3D = instance.mesh.material
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_lt(material.albedo_color.a, 1.0, "must actually be translucent, not just alpha-capable")
	assert_almost_eq(instance.transform.origin.x, 3.0, 0.0001)
	assert_almost_eq(instance.transform.origin.z, 4.0, 0.0001)


func test_show_unit_ghost_with_null_clears_it_and_does_not_crash() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	view.show_unit_ghost(_torso_unit(Vector2i(0, 0)))

	view.show_unit_ghost(null)

	assert_eq(view._unit_ghost_overlay.get_child_count(), 0)


func test_show_unit_ghost_never_touches_the_waypoint_ghost_overlay() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])

	view.show_unit_ghost(_torso_unit(Vector2i(5, 5)))

	assert_eq(view._ghost_overlay.get_child_count(), 4, "2 cell markers + 1 line + 1 label")
	assert_eq(view._unit_ghost_overlay.get_child_count(), 1)


func test_overlays_never_touch_the_static_board() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, MaterialTable.default_table())
	var static_count: int = view._static.get_child_count()

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])

	assert_eq(
		view._static.get_child_count(), static_count, "the overlay must not rebuild the board"
	)
