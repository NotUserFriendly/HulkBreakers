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


## tb31 Pass C: a wall is now OPEN ground carrying a blocker Part too —
## structural, not `_scatter_cover`'s own roll, and VOID (unreachable
## rock, not floor at all) didn't exist when this band was tuned. Both
## excluded from the density measurement so it keeps meaning what it
## always meant: how much of the REAL walkable floor got a scattered
## cover roll, not "how much of the map is solid."
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
				if grid.get_terrain(cell) == Enums.TerrainType.VOID:
					continue
				var blocker: Variant = grid.blockers.get(cell)
				if blocker != null and (blocker as Part).id == &"wall":
					continue
				open_count += 1
				if blocker != null:
					cover_count += 1
		var density: float = float(cover_count) / float(open_count)
		assert_between(
			density, 0.08, 0.30, "seed %d: cover density %.3f out of band" % [map_seed, density]
		)


## BR30.10: every WALL cell that borders at least one non-WALL cell must
## carry a real, indestructible blocker Part — otherwise `ShotPlane.build`
## (which reads only `state.units`/`state.grid.blockers`, never
## `grid.opacity`) has nothing standing in for that wall, and a shot
## resolves as if it wasn't there. A WALL cell with no non-WALL neighbor
## (buried in solid, unreachable rock) deliberately gets no blocker — it
## can never be the nearest hit along any real ray, so skipping it is a
## pure perf win, not a behavior change; this test locks that split in
## rather than letting a future change silently regress to "stamp every
## wall cell" (which would multiply `ShotPlane.build`'s own unculled
## per-shot scan by however much solid rock a map has).
## tb31 Pass C: WALL is only ever a scratch marker now — `_finalize_walls_
## and_void` resolves every remaining WALL cell into either a real,
## destructible wall Part on OPEN ground (exposed — reachable from the
## playable area) or VOID (buried in unreachable rock, no Part at all,
## the same perf reasoning BR30.10 originally established for skipping
## it). No WALL cell survives `generate()` — this checks the settled
## OPEN+wall-Part / VOID split its output actually produces instead.
func test_generate_resolves_every_wall_cell_into_a_destructible_part_or_void() -> void:
	var saw_wall_part := false
	var saw_void := false
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		for y in range(grid.height):
			for x in range(grid.width):
				var cell := Vector2i(x, y)
				assert_ne(
					grid.get_terrain(cell),
					Enums.TerrainType.WALL,
					"seed %d: %s — no raw WALL cell may survive generate()" % [map_seed, cell]
				)
				if grid.get_terrain(cell) == Enums.TerrainType.VOID:
					saw_void = true
					assert_false(
						grid.blockers.has(cell),
						"seed %d: VOID %s must carry no Part" % [map_seed, cell]
					)
					assert_eq(
						grid.get_opacity(cell),
						0.0,
						"seed %d: VOID %s must not block LoS" % [map_seed, cell]
					)
					continue
				var blocker: Variant = grid.blockers.get(cell)
				if blocker != null and (blocker as Part).id == &"wall":
					saw_wall_part = true
					assert_eq(
						grid.get_terrain(cell),
						Enums.TerrainType.OPEN,
						"seed %d: wall %s sits on OPEN ground" % [map_seed, cell]
					)
					assert_true(
						(blocker as Part).is_destructible,
						"seed %d: wall %s must be destructible (tb31 Pass C)" % [map_seed, cell]
					)
	assert_true(saw_wall_part, "expected at least one wall Part across %d seeds" % SEED_COUNT)
	assert_true(saw_void, "expected at least one VOID cell across %d seeds" % SEED_COUNT)


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


## taskblock-16 Pass C: "rooms >= 7 on their min dimension." Rooms and
## corridors share one terrain code once carved, so the only way to
## measure a room's OWN dimensions (not the connected blob it ends up
## part of) is at the point `_carve_room` produces one — same pattern
## other logic tests use to check a "private" static helper directly
## (e.g. `AimView._decal_basis`, `ResolutionPlayer._play_slide`).
func test_carved_rooms_are_at_least_seven_on_their_min_dimension() -> void:
	var rng := RandomNumberGenerator.new()
	for room_seed in range(SEED_COUNT):
		rng.seed = room_seed
		var rooms: Array[Rect2i] = []
		# A leaf exactly at the split threshold's boundary — the smallest a
		# leaf can ever be handed to `_carve_room` in practice.
		MapGen._carve_room(Grid.new(20, 20), Rect2i(Vector2i.ZERO, Vector2i(9, 9)), rng, rooms)
		var room: Rect2i = rooms[0]
		assert_true(
			mini(room.size.x, room.size.y) >= 7,
			"room_seed %d: room %s must be >= 7 on its min dimension" % [room_seed, room.size]
		)


## taskblock-16 Pass C: "hallway width... target 3-5." Same direct-call
## pattern as the room-size test above — width is a property of the
## carve itself, not something separable from the merged terrain output.
func test_carved_corridors_are_three_to_five_wide() -> void:
	var rng := RandomNumberGenerator.new()
	for corridor_seed in range(SEED_COUNT):
		rng.seed = corridor_seed
		var grid := Grid.new(30, 30)
		# `generate()` starts every cell as WALL before carving anything —
		# Grid.new's own default (OPEN) would make the whole column read
		# as "open" regardless of what the corridor actually carved.
		for y in range(grid.height):
			for x in range(grid.width):
				grid.set_terrain(Vector2i(x, y), Enums.TerrainType.WALL)
		MapGen._carve_corridor(grid, Vector2i(2, 2), Vector2i(20, 2), rng)

		# The corridor runs along y=2; measure the open band's thickness at
		# a cross-section clear of the L-turn (x=10, still on the first,
		# horizontal leg).
		var thickness := 0
		for y in range(grid.height):
			if grid.get_terrain(Vector2i(10, y)) == Enums.TerrainType.OPEN:
				thickness += 1
		assert_between(
			thickness,
			MapGen.CORRIDOR_WIDTH_MIN,
			MapGen.CORRIDOR_WIDTH_MAX,
			(
				"corridor_seed %d: corridor thickness %d out of [%d, %d]"
				% [corridor_seed, thickness, MapGen.CORRIDOR_WIDTH_MIN, MapGen.CORRIDOR_WIDTH_MAX]
			)
		)


## taskblock-17 Pass A: "the check that would have caught this" — a
## default-size map must actually split into multiple rooms with real
## hallway between them, not silently collapse to one leaf that never
## cleared `MIN_LEAF_SIZE * 2` (taskblock-16 raised `MIN_ROOM_SIZE`,
## which raised the split threshold past what `WIDTH`x`HEIGHT` could
## clear more than once — every "default-size" map in this file was
## quietly one room for the whole taskblock). `_split_and_carve` called
## directly (same pattern as the room-size/corridor-width tests above) so
## the real room rects are available to sum — rooms and corridors share
## one terrain code once carved, so "hallway cells" can only be measured
## as "open cells the room rects don't already account for."
func test_default_size_map_splits_into_multiple_rooms_with_hallways() -> void:
	for map_seed in range(SEED_COUNT):
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed
		var grid := Grid.new(WIDTH, HEIGHT)
		for y in range(HEIGHT):
			for x in range(WIDTH):
				grid.set_terrain(Vector2i(x, y), Enums.TerrainType.WALL)

		var rooms: Array[Rect2i] = []
		MapGen._split_and_carve(grid, Rect2i(Vector2i.ZERO, Vector2i(WIDTH, HEIGHT)), rng, rooms)

		assert_true(
			rooms.size() >= 3, "seed %d: expected >= 3 rooms, got %d" % [map_seed, rooms.size()]
		)

		var room_cell_count := 0
		for room: Rect2i in rooms:
			room_cell_count += room.size.x * room.size.y
		var open_cell_count := 0
		for y in range(HEIGHT):
			for x in range(WIDTH):
				if grid.get_terrain(Vector2i(x, y)) == Enums.TerrainType.OPEN:
					open_cell_count += 1
		var hallway_cell_count: int = open_cell_count - room_cell_count
		assert_true(
			hallway_cell_count > 0,
			(
				"seed %d: expected hallway cells beyond room interiors, got %d"
				% [map_seed, hallway_cell_count]
			)
		)


## tb31 Pass C: opacity no longer lines up with a WALL/OPEN terrain split
## at all — a wall is OPEN ground carrying a Part, and it's the Part's
## PRESENCE (not the terrain label) that keeps opacity at the 1.0 the
## initial full-grid fill gave it. The real invariant now: opaque exactly
## where a wall Part sits, transparent everywhere else (VOID, plain open
## ground, scattered cover — cover has never set opacity).
func test_opaque_exactly_where_a_wall_part_sits_transparent_everywhere_else() -> void:
	var grid: Grid = MapGen.generate(7, WIDTH, HEIGHT)
	var saw_wall := false
	var saw_open := false
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var blocker: Variant = grid.blockers.get(cell)
			if blocker != null and (blocker as Part).id == &"wall":
				assert_eq(grid.get_opacity(cell), 1.0)
				saw_wall = true
			else:
				assert_eq(grid.get_opacity(cell), 0.0)
				saw_open = true
	assert_true(saw_wall)
	assert_true(saw_open)


## `_split_and_carve` only splits a leaf once BOTH its dimensions clear
## `MIN_LEAF_SIZE * 2` (24, taskblock-16 Pass C) — a grid this small
## (12x10, taskblock-17 Pass A: `BattleScene`'s own default before it was
## fixed to 40x30) never clears that bar, so it always carves exactly one
## room. Both spawn
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
