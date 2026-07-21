extends GutTest


func _open_grid(size: int) -> Grid:
	return Grid.new(size, size)


func test_los_symmetric_on_open_ground() -> void:
	var grid := _open_grid(7)
	var pairs := [
		[Vector2i(0, 0), Vector2i(6, 6)],
		[Vector2i(0, 0), Vector2i(6, 0)],
		[Vector2i(1, 5), Vector2i(5, 1)],
		[Vector2i(2, 2), Vector2i(2, 2)],
	]
	for pair: Array in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		assert_true(LoS.has_los(grid, a, b), "a->b should see on open ground: %s -> %s" % [a, b])
		assert_true(LoS.has_los(grid, b, a), "b->a should see on open ground: %s -> %s" % [b, a])


func test_wall_blocks_los_both_directions() -> void:
	var grid := _open_grid(7)
	grid.set_terrain(Vector2i(3, 3), 1)
	grid.set_opacity(Vector2i(3, 3), 1.0)

	var a := Vector2i(0, 3)
	var b := Vector2i(6, 3)
	assert_false(LoS.has_los(grid, a, b), "wall between a and b should block a->b")
	assert_false(LoS.has_los(grid, b, a), "wall between a and b should block b->a")


func test_los_clear_when_no_wall_in_path() -> void:
	var grid := _open_grid(7)
	grid.set_terrain(Vector2i(3, 3), 1)
	grid.set_opacity(Vector2i(3, 3), 1.0)

	# A path that never crosses (3,3): straight along row 0.
	assert_true(LoS.has_los(grid, Vector2i(0, 0), Vector2i(6, 0)))


func test_los_ignores_opacity_of_endpoint_cells() -> void:
	var grid := _open_grid(5)
	var a := Vector2i(0, 0)
	var b := Vector2i(4, 0)
	grid.set_opacity(a, 1.0)
	grid.set_opacity(b, 1.0)
	assert_true(
		LoS.has_los(grid, a, b), "opacity of the shooter's/target's own cell must not self-block"
	)


func test_corner_blocking_rule_on_exact_diagonal() -> void:
	# Grid.line(0,0 -> 2,2) passes through the corner shared by (1,0),(0,1),(1,1),(2,1),(1,2).
	# A wall on either bordering cell of a corner crossing must block the diagonal shot.
	var grid := _open_grid(5)
	grid.set_opacity(Vector2i(1, 0), 1.0)
	assert_false(
		LoS.has_los(grid, Vector2i(0, 0), Vector2i(2, 2)),
		"wall at one corner-bordering cell blocks the diagonal"
	)
	assert_false(
		LoS.has_los(grid, Vector2i(2, 2), Vector2i(0, 0)), "must block symmetrically in reverse"
	)


func test_corner_blocking_rule_other_bordering_cell() -> void:
	var grid := _open_grid(5)
	grid.set_opacity(Vector2i(0, 1), 1.0)
	assert_false(LoS.has_los(grid, Vector2i(0, 0), Vector2i(2, 2)))


func test_cover_does_not_block_los() -> void:
	var grid := _open_grid(7)
	# taskblock-16 Pass B2: cover is a real Part in `blockers` now — this
	# cell's own opacity stays 0.0 (an open floor tile with a crate on
	# it), the same "cover, but not opaque" case the old cover_value
	# scalar used to set up directly.
	var cover := Part.new()
	cover.id = &"crate"
	grid.blockers[Vector2i(3, 3)] = cover
	assert_true(
		LoS.has_los(grid, Vector2i(0, 3), Vector2i(6, 3)), "a blocker must not affect vision"
	)


## tb31 Pass C: VOID is the OPPOSITE of a wall — non-navigable
## (`Pathfinder`, tested separately) but never opaque, "a shot passes into
## it, there's nothing there." `Grid.new()` defaults every cell to OPEN
## (opacity 0) already, so this pins the terrain-TYPE change is what
## actually matters here, not just a bare default.
func test_void_does_not_block_los() -> void:
	var grid := _open_grid(7)
	grid.set_terrain(Vector2i(3, 3), Enums.TerrainType.VOID)
	assert_true(
		LoS.has_los(grid, Vector2i(0, 3), Vector2i(6, 3)), "VOID must not affect vision either"
	)


func test_visible_cells_open_ground_matches_chebyshev_disc() -> void:
	var grid := _open_grid(11)
	var origin := Vector2i(5, 5)
	var range_val := 2
	var visible: Array[Vector2i] = LoS.visible_cells(grid, origin, range_val)
	assert_eq(visible.size(), (range_val * 2 + 1) * (range_val * 2 + 1))
	assert_has(visible, origin)
	assert_has(visible, Vector2i(3, 3))
	assert_has(visible, Vector2i(7, 7))
	assert_does_not_have(visible, Vector2i(8, 5))


func test_visible_cells_excludes_cells_behind_wall() -> void:
	var grid := _open_grid(7)
	# A wall segment at x=3 spanning the whole column blocks everything beyond it.
	for y in range(7):
		grid.set_opacity(Vector2i(3, y), 1.0)
	var origin := Vector2i(0, 3)
	var visible: Array[Vector2i] = LoS.visible_cells(grid, origin, 6)
	assert_does_not_have(visible, Vector2i(6, 3))
	assert_has(visible, Vector2i(2, 3))
