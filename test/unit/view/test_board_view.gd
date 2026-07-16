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

	assert_eq(view._static.get_child_count(), 2, "ground plane + the one blocker box")


func test_build_clears_previous_children_on_rebuild() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, MaterialTable.default_table())
	var first_count: int = view._static.get_child_count()
	view.build(grid, MaterialTable.default_table())

	assert_eq(view._static.get_child_count(), first_count, "rebuilding must not accumulate children")


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
		view._static.get_child_count(), 1, "only the ground plane; a dead blocker contributes nothing"
	)


func test_show_reachable_spawns_one_marker_per_cell_and_replaces_the_last_call() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	assert_eq(view._reachable_overlay.get_child_count(), 3)

	view.show_reachable([Vector2i(0, 0)])
	assert_eq(view._reachable_overlay.get_child_count(), 1, "a new call must replace the old overlay")


func test_show_ghost_paths_spawns_a_marker_per_cell_across_every_path() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0)]])
	assert_eq(view._ghost_overlay.get_child_count(), 4, "2 cells per path, 2 paths")


func test_reachable_and_ghost_overlays_coexist() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])

	assert_eq(view._reachable_overlay.get_child_count(), 2, "ghosts must not clobber reachable")
	assert_eq(view._ghost_overlay.get_child_count(), 2)


func test_clear_overlays_removes_everything() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])
	view.clear_overlays()
	assert_eq(view._reachable_overlay.get_child_count(), 0)
	assert_eq(view._ghost_overlay.get_child_count(), 0)


func test_overlays_never_touch_the_static_board() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, MaterialTable.default_table())
	var static_count: int = view._static.get_child_count()

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])

	assert_eq(view._static.get_child_count(), static_count, "the overlay must not rebuild the board")
