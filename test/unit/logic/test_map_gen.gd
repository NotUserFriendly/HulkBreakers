extends GutTest

const WIDTH := 32
const HEIGHT := 24
const SEED_COUNT := 50


func _find_cells(grid: Grid, terrain_code: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain_code:
				result.append(cell)
	return result


func _grids_equal(a: Grid, b: Grid) -> bool:
	if a.width != b.width or a.rows != b.rows:
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


## taskblock-36 Pass D's own acceptance test claimed "a fresh MapGen map is
## entirely level 0" — deliberately false as of taskblock-37 Pass D, which
## exists specifically to make `MapGen` author real elevation (docs/PLAN.md
## "MapGen authors real levels... until now it writes 0 everywhere").
## Replaced by the two things that must hold now instead: a generated map
## genuinely contains more than one level somewhere (across a spread of
## seeds — `RAISED_ROOM_PROBABILITY` is seeded per room, not guaranteed on
## any single one), and every raised area a real non-climbing unit could
## need to reach is actually ramp-reachable from spawn, not silently
## stranded.
func test_a_generated_map_contains_more_than_one_level() -> void:
	var found_a_raised_cell := false
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		for y in range(grid.rows):
			for x in range(grid.width):
				if grid.get_level(Vector2i(x, y)) > 0:
					found_a_raised_cell = true
					break
			if found_a_raised_cell:
				break
		if found_a_raised_cell:
			break
	assert_true(
		found_a_raised_cell, "at least one of %d seeds must produce real elevation" % SEED_COUNT
	)


## Every raised region as a whole (not every individual raised CELL —
## scattered cover, exactly like it can on any ordinary room, can still
## legitimately wall off an isolated tile or two inside one; that's the
## same pre-existing "cover blocks movement" contract every other cell on
## the map is already held to, not a claim about ramps at all) must have
## at least one entry point reachable from spawn_a through a non-climbing
## Pathfinder — "since climbing is capability-gated and most units lack
## it, ramps are what make a raised area generally reachable" (docs/
## PLAN.md). `MapGen` doesn't author any deliberate climb-only pocket, so
## every raised region found here is expected to connect.
func test_every_raised_area_is_ramp_reachable_across_many_seeds() -> void:
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_A)
		var pf := Pathfinder.new(grid)
		var reachable: Array[Vector2i] = pf.reachable(spawn_a[0], 9999.0)
		var reachable_set: Dictionary = {}
		for cell: Vector2i in reachable:
			reachable_set[cell] = true

		for region: Array[Vector2i] in _raised_regions(grid):
			var region_reachable := false
			for cell: Vector2i in region:
				if reachable_set.has(cell):
					region_reachable = true
					break
			assert_true(
				region_reachable,
				(
					"seed %d: raised region at %s must have SOME ramp-reachable entry point"
					% [map_seed, region[0]]
				)
			)


## Every level>0 cell grouped into 4-connected components — one entry per
## physically contiguous raised region, regardless of how MapGen happened
## to carve the rooms that produced it.
func _raised_regions(grid: Grid) -> Array:
	var seen: Dictionary = {}
	var regions: Array = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var start := Vector2i(x, y)
			if grid.get_level(start) <= 0 or seen.has(start):
				continue
			var region: Array[Vector2i] = []
			var frontier: Array[Vector2i] = [start]
			seen[start] = true
			while not frontier.is_empty():
				var cell: Vector2i = frontier.pop_back()
				region.append(cell)
				for offset: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var neighbor: Vector2i = cell + offset
					if (
						grid.in_bounds(neighbor)
						and grid.get_level(neighbor) > 0
						and not seen.has(neighbor)
					):
						seen[neighbor] = true
						frontier.append(neighbor)
			regions.append(region)
	return regions


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

		var pf := Pathfinder.new(grid)
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
		for y in range(grid.rows):
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
		for y in range(grid.rows):
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
## taskblock-39 Pass B: `_carve_room` now carves into a private
## `MapGenScratch`, not a real `Grid`.
func test_carved_rooms_are_at_least_seven_on_their_min_dimension() -> void:
	var rng := RandomNumberGenerator.new()
	for room_seed in range(SEED_COUNT):
		rng.seed = room_seed
		var rooms: Array[Rect2i] = []
		# A leaf exactly at the split threshold's boundary — the smallest a
		# leaf can ever be handed to `_carve_room` in practice.
		MapGen._carve_room(
			Grid.new(20, 20),
			MapGenScratch.new(20, 20),
			Rect2i(Vector2i.ZERO, Vector2i(9, 9)),
			rng,
			rooms
		)
		var room: Rect2i = rooms[0]
		assert_true(
			mini(room.size.x, room.size.y) >= 7,
			"room_seed %d: room %s must be >= 7 on its min dimension" % [room_seed, room.size]
		)


## taskblock-16 Pass C: "hallway width... target 3-5." Same direct-call
## pattern as the room-size test above — width is a property of the
## carve itself, not something separable from the merged terrain output.
## taskblock-39 Pass B: scratch already defaults every cell to WALL on
## construction — no manual fill needed the way a real `Grid` used to.
func test_carved_corridors_are_three_to_five_wide() -> void:
	var rng := RandomNumberGenerator.new()
	for corridor_seed in range(SEED_COUNT):
		rng.seed = corridor_seed
		var scratch := MapGenScratch.new(30, 30)
		MapGen._carve_corridor(Grid.new(30, 30), scratch, Vector2i(2, 2), Vector2i(20, 2), rng)

		# The corridor runs along y=2; measure the open band's thickness at
		# a cross-section clear of the L-turn (x=10, still on the first,
		# horizontal leg).
		var thickness := 0
		for y in range(scratch.rows):
			if scratch.get_terrain(Vector2i(10, y)) == Enums.TerrainType.OPEN:
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
		var scratch := MapGenScratch.new(WIDTH, HEIGHT)

		var rooms: Array[Rect2i] = []
		MapGen._split_and_carve(
			Grid.new(WIDTH, HEIGHT),
			scratch,
			Rect2i(Vector2i.ZERO, Vector2i(WIDTH, HEIGHT)),
			rng,
			rooms
		)

		assert_true(
			rooms.size() >= 3, "seed %d: expected >= 3 rooms, got %d" % [map_seed, rooms.size()]
		)

		var room_cell_count := 0
		for room: Rect2i in rooms:
			room_cell_count += room.size.x * room.size.y
		var open_cell_count := 0
		for y in range(HEIGHT):
			for x in range(WIDTH):
				if scratch.get_terrain(Vector2i(x, y)) == Enums.TerrainType.OPEN:
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
	for y in range(grid.rows):
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


## taskblock-38 Pass B: "MapGen writes floor parts... terrain/level become
## derived from placement" — the real acceptance is that the finished
## surfaces store matches the finished terrain/level cell for cell, across
## a whole generated map, not just a sample. taskblock-39 Pass B: this also
## covers "surfaces are emitted with no double-placement rejections" —
## a cell where `GridPlacement.place` silently returned null would show up
## here as `surfaces.size() != 1`.
func test_generated_map_surfaces_match_terrain_and_level_cell_for_cell() -> void:
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		for y in range(grid.rows):
			for x in range(grid.width):
				var cell := Vector2i(x, y)
				var surfaces: Array[Surface] = grid.surfaces_at(cell)
				if grid.get_terrain(cell) == Enums.TerrainType.VOID:
					assert_true(
						surfaces.is_empty(), "seed %d: VOID %s must be unfloored" % [map_seed, cell]
					)
					continue
				assert_eq(
					surfaces.size(),
					1,
					"seed %d: %s must carry exactly one floor surface" % [map_seed, cell]
				)
				var expected_id: StringName = (
					&"ramp" if grid.get_terrain(cell) == Enums.TerrainType.RAMP else &"ship_floor"
				)
				assert_eq(
					surfaces[0].part.id,
					expected_id,
					"seed %d: %s surface part mismatch" % [map_seed, cell]
				)
				var expected_height: float = grid.get_level(cell) * UnitGeometry.LEVEL_HEIGHT
				if grid.get_terrain(cell) == Enums.TerrainType.RAMP:
					expected_height += RampGeometry.STANDING_OFFSET
				assert_almost_eq(
					surfaces[0].height,
					expected_height,
					0.0001,
					"seed %d: %s surface height mismatch" % [map_seed, cell]
				)


## taskblock-39 Pass B's own literal acceptance: "carving the same cell
## twice succeeds and leaves one surface, not an error" — scratch has no
## attachment grammar to fight at all (it's a plain array), and `_emit`
## only ever visits the finished result once, so this holds by
## construction now rather than needing an idempotency fix of its own.
func test_carving_the_same_cell_twice_leaves_exactly_one_surface() -> void:
	var grid := Grid.new(3, 3)
	var scratch := MapGenScratch.new(3, 3)
	var cell := Vector2i(1, 1)
	MapGen._set_open(grid, scratch, cell)
	MapGen._set_open(grid, scratch, cell)  # a re-carved corridor visits the same cell twice

	MapGen._emit(grid, scratch, {})

	var surfaces: Array[Surface] = grid.surfaces_at(cell)
	assert_eq(surfaces.size(), 1, "a re-carve must leave exactly one surface, not stack or error")
	assert_eq(surfaces[0].part.id, &"ship_floor")


## taskblock-39 Pass B: the forced fallback corridor now runs entirely in
## scratch — no `Grid`/`Grid.surfaces` involved in carving at all, so
## nothing about the placement model can reject it.
func test_ensure_spawns_connected_fallback_connects_disconnected_spawns() -> void:
	var grid := Grid.new(10, 3)
	var scratch := MapGenScratch.new(10, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a := Vector2i(0, 1)
	var b := Vector2i(9, 1)
	MapGen._set_open(grid, scratch, a)
	MapGen._set_open(grid, scratch, b)
	# Everything between stays WALL (scratch's own default fill) --
	# deliberately disconnected, forcing the fallback.

	var pf := Pathfinder.new(scratch.as_temporary_grid())
	assert_true(pf.astar(a, b).is_empty(), "sanity: the two spawns start disconnected")

	MapGen._ensure_spawns_connected(grid, scratch, a, b, rng)

	var pf_after := Pathfinder.new(scratch.as_temporary_grid())
	assert_false(
		pf_after.astar(a, b).is_empty(), "the fallback must actually connect the two spawns"
	)


## taskblock-38 Pass C: docs/PLAN.md's corrected ramp profile — two tiles,
## not one. `inner` (bordering the room) is the upper step at
## `RAISED_ROOM_LEVEL - 0.5`; `outer`, one further out along the same
## approach, is the lower step at `RAISED_ROOM_LEVEL - 1.0` (real ground
## for a level-1 room). Both share one facing (the direction of ascent).
## taskblock-39 Pass B: `_connect_with_a_ramp` now carves scratch and
## records facing into `ramp_facings` again — surfaces aren't placed until
## `_emit` runs, at the very end.
func test_connect_with_a_ramp_places_two_tiles_with_shared_facing_and_correct_levels() -> void:
	var scratch := MapGenScratch.new(6, 3)
	var room := Rect2i(Vector2i(3, 1), Vector2i(2, 1))
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			scratch.set_level(Vector2i(x, y), MapGen.RAISED_ROOM_LEVEL)
	# `MapGenScratch` defaults every cell to WALL (unlike the old bare
	# `Grid.new()`, which defaulted to OPEN) -- the ring cells this ramp
	# approach needs must be carved open explicitly, matching what real
	# BSP carving would already have done by the time `_author_levels`
	# (and therefore `_connect_with_a_ramp`) runs.
	scratch.set_terrain(Vector2i(2, 1), Enums.TerrainType.OPEN)
	scratch.set_terrain(Vector2i(1, 1), Enums.TerrainType.OPEN)

	var ramp_facings: Dictionary = {}
	MapGen._connect_with_a_ramp(scratch, room, ramp_facings)

	assert_eq(
		scratch.get_terrain(Vector2i(2, 1)), Enums.TerrainType.RAMP, "the room-bordering tile"
	)
	assert_eq(scratch.get_terrain(Vector2i(1, 1)), Enums.TerrainType.RAMP, "one tile further out")
	assert_almost_eq(scratch.get_level(Vector2i(2, 1)), MapGen.RAISED_ROOM_LEVEL - 0.5, 0.0001)
	assert_almost_eq(scratch.get_level(Vector2i(1, 1)), MapGen.RAISED_ROOM_LEVEL - 1.0, 0.0001)
	assert_true(ramp_facings.has(Vector2i(2, 1)))
	assert_true(ramp_facings.has(Vector2i(1, 1)))
	assert_almost_eq(ramp_facings[Vector2i(2, 1)], ramp_facings[Vector2i(1, 1)], 0.0001)


## taskblock-38 Pass C: a stranded RAMP tile (its own room already flooded
## away, or its other tile cut off) must revert fully to plain OPEN ground
## at level 0, the same as a stranded room interior — otherwise the tile
## bordering a room sits at a genuinely non-zero level
## (`RAISED_ROOM_LEVEL - 0.5`) forever, an orphaned "raised" island of one
## tile the reachability test can actually see (a real bug this pass's own
## corrected profile exposed — tb37's single-tile ramp had the identical
## gap, just never observable, since it was always authored at level 0).
func test_repair_stranded_elevation_reverts_an_unreachable_ramp_tile_to_plain_ground() -> void:
	var grid := Grid.new(4, 1)
	var scratch := MapGenScratch.new(4, 1)
	var rooms: Array[Rect2i] = [Rect2i(Vector2i(0, 0), Vector2i(1, 1))]
	# A wall seals the anchor at (0, 0) off from everything past it -- the
	# ramp tile at (2, 0) has nothing reachable on either side.
	scratch.set_terrain(Vector2i(1, 0), Enums.TerrainType.WALL)
	scratch.set_terrain(Vector2i(2, 0), Enums.TerrainType.RAMP)
	scratch.set_level(Vector2i(2, 0), MapGen.RAISED_ROOM_LEVEL - 0.5)

	MapGen._repair_stranded_elevation(grid, scratch, rooms)

	assert_eq(scratch.get_terrain(Vector2i(2, 0)), Enums.TerrainType.OPEN)
	assert_almost_eq(scratch.get_level(Vector2i(2, 0)), 0.0, 0.0001)


## A ring position with no room for a second tile behind it (map edge on
## every side here) is never used — no ramp anywhere, not a malformed
## single-tile one. `_repair_stranded_elevation`'s own flood-and-flatten
## safety net is what catches the room this leaves stranded.
func test_connect_with_a_ramp_places_nothing_when_no_approach_has_room_for_two_tiles() -> void:
	var scratch := MapGenScratch.new(2, 3)
	var room := Rect2i(Vector2i(1, 1), Vector2i(1, 1))
	scratch.set_level(Vector2i(1, 1), MapGen.RAISED_ROOM_LEVEL)
	# Every ring cell is carved OPEN (matching what a real carve would have
	# done) so this genuinely tests "no ring position has room for a SECOND
	# tile" — the map edge is one cell away on every side — rather than the
	# uninteresting "nothing here is open at all" (`MapGenScratch` defaults
	# every cell to WALL, unlike the old bare `Grid.new()`).
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]:
		scratch.set_terrain(cell, Enums.TerrainType.OPEN)

	var ramp_facings: Dictionary = {}
	MapGen._connect_with_a_ramp(scratch, room, ramp_facings)

	for y in range(scratch.rows):
		for x in range(scratch.width):
			assert_ne(
				scratch.get_terrain(Vector2i(x, y)),
				Enums.TerrainType.RAMP,
				"no ring position here supports a two-tile ramp"
			)
	assert_true(ramp_facings.is_empty())


func test_spawn_zones_are_walkable() -> void:
	var grid: Grid = MapGen.generate(3, WIDTH, HEIGHT)
	var pf := Pathfinder.new(grid)
	for cell: Vector2i in _find_cells(grid, Enums.TerrainType.SPAWN_A):
		assert_true(pf.is_walkable(cell))
	for cell: Vector2i in _find_cells(grid, Enums.TerrainType.SPAWN_B):
		assert_true(pf.is_walkable(cell))


## taskblock-39 Pass B's own literal acceptance: "map_gen.gd contains no
## reads or writes of Grid's terrain/level API — carving touches only its
## own scratch." `_place_spawn_zones`/`_mark_zone` (SPAWN_A/SPAWN_B are a
## real-`Grid`-only overlay, never scratch's concern) and `_emit` (the ONE
## place scratch becomes real) are the only legitimate exceptions.
func test_map_gen_touches_grids_terrain_level_api_only_in_spawn_marking_and_emit() -> void:
	var allowed_functions: Array[String] = ["_place_spawn_zones", "_mark_zone", "_emit"]
	var file := FileAccess.open("res://src/logic/map_gen.gd", FileAccess.READ)
	assert_not_null(file, "sanity: map_gen.gd must exist to check at all")
	var current_function := ""
	var offending: Array[String] = []
	while not file.eof_reached():
		var line: String = file.get_line()
		var stripped: String = line.strip_edges()
		if stripped.begins_with("static func "):
			current_function = stripped.trim_prefix("static func ").split("(")[0]
		var touches_terrain_level: bool = (
			"grid.set_terrain(" in line
			or "grid.get_terrain(" in line
			or "grid.set_level(" in line
			or "grid.get_level(" in line
		)
		if touches_terrain_level and current_function not in allowed_functions:
			offending.append("%s: %s" % [current_function, stripped])
	assert_eq(
		offending,
		[] as Array[String],
		"terrain/level API used outside spawn-marking/emit: %s" % [offending]
	)
