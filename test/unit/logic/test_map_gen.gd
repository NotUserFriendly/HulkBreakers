extends GutTest

const WIDTH := 32
const HEIGHT := 24
const SEED_COUNT := 50


func _find_cells(grid: Grid, terrain_code: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain_code:
				result.append(cell)
	return result


func _grids_equal(a: Grid, b: Grid) -> bool:
	if a.width != b.width or a.height != b.height:
		return false
	return a.terrain == b.terrain and a.opacity == b.opacity and a.cover_value == b.cover_value and a.occupant_id == b.occupant_id


func test_same_seed_is_byte_identical() -> void:
	var grid_a: Grid = MapGen.generate(12345, WIDTH, HEIGHT)
	var grid_b: Grid = MapGen.generate(12345, WIDTH, HEIGHT)
	assert_true(_grids_equal(grid_a, grid_b), "same seed must produce an identical grid")


func test_different_seed_is_not_identical() -> void:
	var grid_a: Grid = MapGen.generate(1, WIDTH, HEIGHT)
	var grid_b: Grid = MapGen.generate(2, WIDTH, HEIGHT)
	assert_false(_grids_equal(grid_a, grid_b), "different seeds should (almost always) diverge")


func test_spawn_zones_reachable_across_many_seeds() -> void:
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_A)
		var spawn_b: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_B)
		assert_true(spawn_a.size() > 0, "seed %d: spawn zone A must exist" % map_seed)
		assert_true(spawn_b.size() > 0, "seed %d: spawn zone B must exist" % map_seed)

		var pf := Pathfinder.new(grid, {Enums.TerrainType.WALL: -1.0})
		var path: Array[Vector2i] = pf.astar(spawn_a[0], spawn_b[0])
		assert_true(path.size() > 0, "seed %d: spawn zones must be path-connected" % map_seed)


func test_cover_density_within_target_band() -> void:
	# Target band: 8%-30% of open floor cells carry cover. Documented tunable
	# (Appendix C notes exposure/cover weights are tune-later values).
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		var open_count := 0
		var cover_count := 0
		for y in range(grid.height):
			for x in range(grid.width):
				var cell := Vector2i(x, y)
				if grid.get_terrain(cell) == Enums.TerrainType.WALL:
					continue
				open_count += 1
				if grid.get_cover_value(cell) > 0.0:
					cover_count += 1
		var density: float = float(cover_count) / float(open_count)
		assert_between(density, 0.08, 0.30, "seed %d: cover density %.3f out of band" % [map_seed, density])


func test_walls_are_opaque_and_open_cells_are_not() -> void:
	var grid: Grid = MapGen.generate(7, WIDTH, HEIGHT)
	var saw_wall := false
	var saw_open := false
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == Enums.TerrainType.WALL:
				assert_eq(grid.get_opacity(cell), 1.0)
				saw_wall = true
			else:
				assert_eq(grid.get_opacity(cell), 0.0)
				saw_open = true
	assert_true(saw_wall)
	assert_true(saw_open)


func test_spawn_zones_are_walkable() -> void:
	var grid: Grid = MapGen.generate(3, WIDTH, HEIGHT)
	var pf := Pathfinder.new(grid, {Enums.TerrainType.WALL: -1.0})
	for cell: Vector2i in _find_cells(grid, Enums.TerrainType.SPAWN_A):
		assert_true(pf.is_walkable(cell))
	for cell: Vector2i in _find_cells(grid, Enums.TerrainType.SPAWN_B):
		assert_true(pf.is_walkable(cell))
