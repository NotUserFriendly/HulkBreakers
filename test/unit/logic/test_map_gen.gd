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
	# taskblock-16 Pass B2: `blockers` holds real Part objects — Dictionary
	# `==` on Object values is reference equality, so this compares each
	# cell's own blocker id instead (see test_determinism_check.gd's own
	# identical fix).
	var a_blocker_ids: Dictionary = {}
	for cell: Vector2i in a.blockers:
		a_blocker_ids[cell] = (a.blockers[cell] as Part).id
	var b_blocker_ids: Dictionary = {}
	for cell: Vector2i in b.blockers:
		b_blocker_ids[cell] = (b.blockers[cell] as Part).id
	return (
		a.terrain == b.terrain
		and a.opacity == b.opacity
		and a_blocker_ids == b_blocker_ids
		and a.occupant_id == b.occupant_id
	)


func test_generate_is_seed_deterministic() -> void:
	var same_seed_a: Grid = MapGen.generate(12345, WIDTH, HEIGHT)
	var same_seed_b: Grid = MapGen.generate(12345, WIDTH, HEIGHT)
	assert_true(_grids_equal(same_seed_a, same_seed_b), "same seed must produce an identical grid")

	var seed_one: Grid = MapGen.generate(1, WIDTH, HEIGHT)
	var seed_two: Grid = MapGen.generate(2, WIDTH, HEIGHT)
	assert_false(_grids_equal(seed_one, seed_two), "different seeds should (almost always) diverge")


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
				if grid.blockers.has(cell):
					cover_count += 1
		var density: float = float(cover_count) / float(open_count)
		assert_between(
			density, 0.08, 0.30, "seed %d: cover density %.3f out of band" % [map_seed, density]
		)


func _attached_barrel_count(pallet: Part) -> int:
	var count := 0
	for socket: Socket in pallet.sockets:
		if socket.socket_type == &"BARREL_SLOT" and socket.occupant != null:
			count += 1
	return count


## taskblock-16 B1: "a barrel_pallet generates with 0-4 goo_barrels on it
## (seeded)" — same seed must roll the same barrel counts, and every
## rolled count must land in the documented 0-4 range.
func test_barrel_pallet_barrel_count_is_deterministic_and_in_range() -> void:
	var counts_a: Array[int] = []
	var counts_b: Array[int] = []
	for map_seed in range(SEED_COUNT):
		var grid_a: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		var grid_b: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		for cell: Vector2i in grid_a.blockers:
			var part: Part = grid_a.blockers[cell]
			if part.id == &"barrel_pallet":
				counts_a.append(_attached_barrel_count(part))
		for cell: Vector2i in grid_b.blockers:
			var part: Part = grid_b.blockers[cell]
			if part.id == &"barrel_pallet":
				counts_b.append(_attached_barrel_count(part))

	assert_true(
		counts_a.size() > 0, "at least one barrel_pallet must appear across %d seeds" % SEED_COUNT
	)
	assert_eq(counts_a, counts_b, "the same seed must roll the same barrel counts")
	for count: int in counts_a:
		assert_between(count, 0, 4, "a barrel_pallet must carry 0-4 barrels")


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


## `_split_and_carve` only splits a leaf once BOTH its dimensions clear
## `MIN_LEAF_SIZE * 2` (16) — a grid as small as BattleScene's own (12x10)
## never clears that bar, so it always carves exactly one room. Both spawn
## zones must still land on distinct, real cells there too: this was a
## reproduced bug (runNotes.md — "the red unit may be spawning in a
## non-navigable space") where SPAWN_B silently overwrote every SPAWN_A
## cell in the single-room case, so a caller scanning for SPAWN_A found
## nothing and had to fall back to a coordinate no longer guaranteed to be
## inside carved-open ground.
func test_spawn_zones_are_distinct_even_in_a_single_room_grid() -> void:
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, 12, 10)
		var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_A)
		var spawn_b: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_B)
		assert_true(spawn_a.size() > 0, "seed %d: spawn zone A must exist" % map_seed)
		assert_true(spawn_b.size() > 0, "seed %d: spawn zone B must exist" % map_seed)


func test_spawn_zones_are_walkable() -> void:
	var grid: Grid = MapGen.generate(3, WIDTH, HEIGHT)
	var pf := Pathfinder.new(grid, {Enums.TerrainType.WALL: -1.0})
	for cell: Vector2i in _find_cells(grid, Enums.TerrainType.SPAWN_A):
		assert_true(pf.is_walkable(cell))
	for cell: Vector2i in _find_cells(grid, Enums.TerrainType.SPAWN_B):
		assert_true(pf.is_walkable(cell))
