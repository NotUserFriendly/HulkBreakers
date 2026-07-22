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


func test_set_get_cell_data_roundtrip() -> void:
	var cell := Vector2i(1, 3)
	_grid.set_terrain(cell, 2)
	_grid.set_opacity(cell, 1.0)
	_grid.set_occupant_id(cell, 7)
	# taskblock-16 Pass B2: `blockers` (real Part objects) is the one
	# source of truth for cover now — no separate scalar to round-trip.
	var cover := Part.new()
	cover.id = &"test_cover"
	_grid.blockers[cell] = cover
	assert_eq(_grid.get_terrain(cell), 2)
	assert_eq(_grid.get_opacity(cell), 1.0)
	assert_eq(_grid.get_occupant_id(cell), 7)
	assert_eq(_grid.blockers[cell], cover)
	# Unrelated cell stays default.
	assert_eq(_grid.get_terrain(Vector2i(0, 0)), 0)


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
