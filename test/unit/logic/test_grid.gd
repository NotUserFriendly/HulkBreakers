extends GutTest

var _grid: Grid


func before_each() -> void:
	_grid = Grid.new(5, 5)


func test_in_bounds() -> void:
	assert_true(_grid.in_bounds(Vector2i(0, 0)))
	assert_true(_grid.in_bounds(Vector2i(4, 4)))
	assert_false(_grid.in_bounds(Vector2i(-1, 0)))
	assert_false(_grid.in_bounds(Vector2i(5, 0)))
	assert_false(_grid.in_bounds(Vector2i(0, 5)))


func test_default_cell_values() -> void:
	var cell := Vector2i(2, 2)
	assert_eq(_grid.get_terrain(cell), 0)
	assert_eq(_grid.get_opacity(cell), 0.0)
	assert_eq(_grid.get_occupant_id(cell), -1)
	assert_false(_grid.blockers.has(cell))
	assert_eq(_grid.get_level(cell), 0, "taskblock-36 Pass D: a fresh cell defaults to level 0")


func test_set_get_cell_data_roundtrip() -> void:
	var cell := Vector2i(1, 3)
	_grid.set_terrain(cell, 2)
	_grid.set_opacity(cell, 1.0)
	_grid.set_occupant_id(cell, 7)
	_grid.set_level(cell, 2)
	# taskblock-16 Pass B2: `blockers` (real Part objects) is the one
	# source of truth for cover now — no separate scalar to round-trip.
	var cover := Part.new()
	cover.id = &"test_cover"
	_grid.blockers[cell] = cover
	assert_eq(_grid.get_terrain(cell), 2)
	assert_eq(_grid.get_opacity(cell), 1.0)
	assert_eq(_grid.get_occupant_id(cell), 7)
	assert_eq(_grid.get_level(cell), 2)
	assert_eq(_grid.blockers[cell], cover)
	# Unrelated cell stays default.
	assert_eq(_grid.get_terrain(Vector2i(0, 0)), 0)
	assert_eq(_grid.get_level(Vector2i(0, 0)), 0)


## taskblock-36 Pass D: `dup()` must carry a cell's own level onto the
## clone — the same "a preview must see the real world, including any
## forced scenario" guarantee every other per-cell array already gets.
func test_dup_copies_level() -> void:
	_grid.set_level(Vector2i(2, 2), 3)
	var cloned: Grid = _grid.dup()
	assert_eq(cloned.get_level(Vector2i(2, 2)), 3)
	cloned.set_level(Vector2i(2, 2), 0)
	assert_eq(
		_grid.get_level(Vector2i(2, 2)), 3, "mutating the clone must never touch the original"
	)


## taskblock-38 Pass A: a fresh cell has no surfaces — `surfaces_at` returns
## a real, empty, typed array rather than requiring a `has()` check first.
func test_surfaces_at_defaults_empty() -> void:
	assert_eq(_grid.surfaces_at(Vector2i(2, 2)), [] as Array[Surface])


func test_add_surface_appends_in_order() -> void:
	var cell := Vector2i(1, 1)
	var floor_surface := Surface.new(Part.new(), 0.0)
	var catwalk_surface := Surface.new(Part.new(), 1.0)
	_grid.add_surface(cell, floor_surface)
	_grid.add_surface(cell, catwalk_surface)
	assert_eq(_grid.surfaces_at(cell), [floor_surface, catwalk_surface])


## `dup()` must deep-copy each cell's own surfaces (a fresh Part per
## surface, same "a preview must never touch the real Part" guarantee
## `blockers`/`field_items` already carry) — mutating the clone's surface
## part must never reach back into the original.
func test_dup_copies_surfaces_independently() -> void:
	var part := Part.new()
	part.id = &"floor"
	part.hp = 3
	_grid.add_surface(Vector2i(2, 2), Surface.new(part, 1.0, 0.5))

	var cloned: Grid = _grid.dup()
	var cloned_surfaces: Array[Surface] = cloned.surfaces_at(Vector2i(2, 2))
	assert_eq(cloned_surfaces.size(), 1)
	assert_eq(cloned_surfaces[0].height, 1.0)
	assert_eq(cloned_surfaces[0].facing, 0.5)
	assert_eq(cloned_surfaces[0].part.id, &"floor")
	assert_ne(cloned_surfaces[0].part, part, "the clone must hold its own Part, not the original")

	cloned_surfaces[0].part.hp = 0
	assert_eq(
		_grid.surfaces_at(Vector2i(2, 2))[0].part.hp,
		3,
		"mutating the clone's surface part must never touch the original"
	)


func test_neighbors_center_cell_has_eight() -> void:
	var n: Array[Vector2i] = _grid.neighbors(Vector2i(2, 2))
	assert_eq(n.size(), 8)
	assert_has(n, Vector2i(3, 2))
	assert_has(n, Vector2i(1, 2))
	assert_has(n, Vector2i(2, 3))
	assert_has(n, Vector2i(2, 1))
	assert_has(n, Vector2i(3, 3))
	assert_has(n, Vector2i(1, 1))


func test_neighbors_corner_cell_excludes_out_of_bounds() -> void:
	var n: Array[Vector2i] = _grid.neighbors(Vector2i(0, 0))
	assert_eq(n.size(), 3)
	for cell: Vector2i in n:
		assert_true(_grid.in_bounds(cell))


func test_distance_chebyshev() -> void:
	assert_eq(Grid.distance_chebyshev(Vector2i(0, 0), Vector2i(3, 1)), 3)
	assert_eq(Grid.distance_chebyshev(Vector2i(0, 0), Vector2i(2, 2)), 2)
	assert_eq(Grid.distance_chebyshev(Vector2i(2, 2), Vector2i(2, 2)), 0)


func test_distance_manhattan() -> void:
	assert_eq(Grid.distance_manhattan(Vector2i(0, 0), Vector2i(3, 1)), 4)
	assert_eq(Grid.distance_manhattan(Vector2i(0, 0), Vector2i(2, 2)), 4)
	assert_eq(Grid.distance_manhattan(Vector2i(2, 2), Vector2i(2, 2)), 0)


func test_line_handles_the_same_cell_horizontal_and_vertical_cases() -> void:
	var same_cell: Array[Vector2i] = Grid.line(Vector2i(2, 2), Vector2i(2, 2))
	assert_eq(same_cell, [Vector2i(2, 2)], "same cell")

	var horizontal: Array[Vector2i] = Grid.line(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(
		horizontal, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], "horizontal"
	)

	var vertical: Array[Vector2i] = Grid.line(Vector2i(0, 0), Vector2i(0, 3))
	assert_eq(
		vertical, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)], "vertical"
	)


func test_line_exact_diagonal_includes_both_bordering_cells() -> void:
	var l: Array[Vector2i] = Grid.line(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(
		l,
		[
			Vector2i(0, 0),
			Vector2i(1, 0),
			Vector2i(0, 1),
			Vector2i(1, 1),
			Vector2i(2, 1),
			Vector2i(1, 2),
			Vector2i(2, 2),
		]
	)


func test_line_endpoints_are_first_and_last() -> void:
	var l: Array[Vector2i] = Grid.line(Vector2i(0, 0), Vector2i(4, 2))
	assert_eq(l[0], Vector2i(0, 0))
	assert_eq(l[l.size() - 1], Vector2i(4, 2))


func test_line_is_symmetric() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(4, 2)
	var forward: Array[Vector2i] = Grid.line(a, b)
	var backward: Array[Vector2i] = Grid.line(b, a)
	backward.reverse()
	assert_eq(forward, backward)


func test_line_symmetric_on_exact_diagonal() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(2, 2)
	var forward: Array[Vector2i] = Grid.line(a, b)
	var backward: Array[Vector2i] = Grid.line(b, a)
	backward.reverse()
	assert_eq(forward, backward)


## taskblock-36 Pass D: "Grid.height no longer exists under that name
## anywhere, tests included (a grep is the test)" — `rows` replaced it in
## the same commit that added `level`, so the trap of "height" meaning row
## count right next to a cell's own real elevation never had a window to
## exist in.
func test_grid_height_no_longer_exists_anywhere() -> void:
	# This file's own name is excluded — it necessarily quotes the banned
	# string literally, in this very function, to check for it.
	var allowed_files: Array[String] = ["test_grid.gd"]
	var offending: Array[String] = []
	_scan_dir_for_grid_height("res://src", allowed_files, offending)
	_scan_dir_for_grid_height("res://test", allowed_files, offending)
	assert_eq(offending, [] as Array[String], "grid.height still referenced in: %s" % [offending])


func _scan_dir_for_grid_height(
	path: String, allowed_files: Array[String], offending: Array[String]
) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir_for_grid_height(full_path, allowed_files, offending)
		elif entry.ends_with(".gd") and not allowed_files.has(entry):
			var text: String = FileAccess.get_file_as_string(full_path)
			if text.contains("grid.height"):
				offending.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## tb32 Pass C: "something physical, but not a unit" — a PART hit-kind
## target resolves fresh from Grid at RESOLUTION time.
func test_shootable_part_at_returns_the_blocker_when_present() -> void:
	var part := Part.new()
	part.id = &"wall"
	part.hp = 10
	part.max_hp = 10
	_grid.blockers[Vector2i(2, 2)] = part

	assert_eq(_grid.shootable_part_at(Vector2i(2, 2)), part)


func test_shootable_part_at_falls_back_to_the_first_loose_part_field_item() -> void:
	var part := Part.new()
	part.id = &"dropped_arm"
	part.hp = 4
	part.max_hp = 4
	_grid.field_items[Vector2i(3, 3)] = [Matrix.new(), part]

	assert_eq(_grid.shootable_part_at(Vector2i(3, 3)), part)


func test_shootable_part_at_returns_null_for_a_loose_matrix_only() -> void:
	_grid.field_items[Vector2i(1, 1)] = [Matrix.new()]

	assert_null(_grid.shootable_part_at(Vector2i(1, 1)))


func test_shootable_part_at_returns_null_with_nothing_at_the_cell() -> void:
	assert_null(_grid.shootable_part_at(Vector2i(0, 0)))
