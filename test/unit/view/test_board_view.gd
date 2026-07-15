extends GutTest

## docs/10: BoardView is pure presentation — a ground plane sized to the
## grid, plus one box per blocker box. It never mutates Grid.


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

	assert_eq(view.get_child_count(), 2, "ground plane + the one blocker box")


func test_build_clears_previous_children_on_rebuild() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, MaterialTable.default_table())
	var first_count: int = view.get_child_count()
	view.build(grid, MaterialTable.default_table())

	assert_eq(view.get_child_count(), first_count, "rebuilding must not accumulate children")


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

	assert_eq(view.get_child_count(), 1, "only the ground plane; a dead blocker contributes nothing")
