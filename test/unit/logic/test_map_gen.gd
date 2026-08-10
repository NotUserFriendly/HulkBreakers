extends GutTest

const WIDTH := 32
const HEIGHT := 24
const SEED_COUNT := 50

## **The known-unreachable set — currently empty, and kept anyway** (tb60).
##
## `BR60.01`: `MapNavigability` asks *"can you get out"*, so a raised region you can never get
## **into** is invisible to the invariant. At 40x30 — **the size the game actually plays** —
## six regions of 50 to 235 cells reproduce, identically before and after this block.
##
## **At this file's 32x24 they do not, and the history of that is the point.** They appeared
## here for exactly one build: raising the step height to 0.4 shortened stairs, which left more
## rooms raised and therefore more of them exposed, and seed 29 surfaced a 34-cell region. Then
## making spawn zones height-uniform moved a zone onto the shelf it had been straddling, and it
## vanished again. **Neither change touched the defect** — both changed how likely the board is
## to hand you an accidental way in.
##
## **So the list is empty and the assertion is still equality, not `is_empty()`.** A new entry
## is a regression *or* another glimpse of `BR60.01`, and either wants a human reading it
## rather than a silently-passing sweep. **The real fix is to run this sweep at the bout board
## size**, where it would reproduce every time; that is taskblock-61's, not this block's, and
## `BR60.01` says so.
const KNOWN_UNREACHABLE: Array[String] = []


func _find_cells(grid: Grid, marker: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_spawn_marker(cell) == marker:
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
		a_blocker_ids[cell] = a.blocker_part_at(cell).id
	var b_blocker_ids: Dictionary = {}
	for cell: Vector2i in b.blockers:
		b_blocker_ids[cell] = b.blocker_part_at(cell).id
	return (
		a.spawn_marker == b.spawn_marker
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
## taskblock-39 Pass D: `Grid.level` is deleted — elevation now reads back
## through `UnitGeometry.true_height_for_cell`, the same real placed-Surface
## height every other reader uses (no second, terrain-array copy of "how
## high is this cell" survives to check against).
func test_a_generated_map_contains_more_than_one_level() -> void:
	var found_a_raised_cell := false
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, HEIGHT)
		for y in range(grid.rows):
			for x in range(grid.width):
				if UnitGeometry.true_height_for_cell(Vector2i(x, y), grid) > 0.0:
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
## legitimately wall off an isolated cell or two inside one; that's the
## same pre-existing "cover blocks movement" contract every other cell on
## the map is already held to, not a claim about ramps at all) must have
## at least one entry point reachable from spawn_a through a non-climbing
## Pathfinder — "since climbing is capability-gated and most units lack
## it, ramps are what make a raised area generally reachable" (docs/
## PLAN.md). `MapGen` doesn't author any deliberate climb-only pocket, so
## every raised region found here is expected to connect.
func test_every_raised_area_is_reachable_except_the_one_br60_01_names() -> void:
	var unreachable: Array[String] = []
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, HEIGHT)
		var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.SpawnMarker.SPAWN_A)
		var pf := Pathfinder.new(grid)
		var reachable_set: Dictionary = {}
		for cell: Vector2i in pf.reachable(spawn_a[0], 9999.0):
			reachable_set[cell] = true

		for region: Array[Vector2i] in _raised_regions(grid):
			var region_reachable := false
			for cell: Vector2i in region:
				if reachable_set.has(cell):
					region_reachable = true
					break
			if not region_reachable:
				unreachable.append(
					"seed %d at %s (%d cells)" % [map_seed, region[0], region.size()]
				)

	assert_eq(
		unreachable,
		KNOWN_UNREACHABLE,
		(
			"raised regions with no reachable entry changed — a NEW one is a regression, and a "
			+ (
				"MISSING one means BR60.01 is fixed and this list should shrink:\n%s"
				% "\n".join(unreachable)
			)
		)
	)


## Every level>0 cell grouped into 4-connected components — one entry per
## physically contiguous raised region, regardless of how MapGen happened
## to carve the rooms that produced it. taskblock-39 Pass D: reads real
## placed-Surface height (`UnitGeometry.true_height_for_cell`), `Grid.level`
## no longer exists to read directly.
##
## tb60 Pass A: **a cell carrying a live blocker is not raised ground, and is skipped.**
## The caller's own doc already said so in prose — "scattered cover can still legitimately
## wall off an isolated cell or two, that is the same cover-blocks-movement contract every
## other cell is held to" — but this function never implemented the exclusion, so a lone
## raised cell with a crate on it counted as a whole unreachable "region". It is unreachable
## by construction (`Pathfinder._base_cost` refuses any cell with a live blocker) and no unit
## could stand there whatever the terrain did, so a check about *ground* must not see it.
##
## **Measured, because it is a test change and those need justifying.** Across the 50 seeds
## at this board size the old ramp generator produced **zero** such regions and the stair
## generator produces **six — every one of them exactly one cell carrying exactly one
## blocker.** No multi-cell region changed reachability either way. So this is cover landing
## somewhere new, not elevation becoming unreachable.
func _raised_regions(grid: Grid) -> Array:
	var seen: Dictionary = {}
	var regions: Array = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var start := Vector2i(x, y)
			if UnitGeometry.true_height_for_cell(start, grid) <= 0.0 or seen.has(start):
				continue
			if _is_blocked(grid, start):
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
						and UnitGeometry.true_height_for_cell(neighbor, grid) > 0.0
						and not seen.has(neighbor)
						and not _is_blocked(grid, neighbor)
					):
						seen[neighbor] = true
						frontier.append(neighbor)
			regions.append(region)
	return regions


## The same question `Pathfinder._base_cost` asks — a DESTROYED blocker is passable, so
## presence alone is not the test. Read from the one place rather than re-stated, so a
## change to what "blocked" means cannot leave this helper behind.
func _is_blocked(grid: Grid, cell: Vector2i) -> bool:
	return grid.blockers.has(cell) and (grid.blocker_part_at(cell) as Part).hp > 0


func test_generate_is_seed_deterministic() -> void:
	# **`MapGen.generate`, not `MapCorpus.read`.** The corpus caches by seed and would hand
	# back the same object twice, making this assertion pass unconditionally — the suite
	# would silently lose its only check that generation is reproducible.
	var same_seed_a: Grid = MapGen.generate(12345, WIDTH, HEIGHT)
	var same_seed_b: Grid = MapGen.generate(12345, WIDTH, HEIGHT)
	assert_true(_grids_equal(same_seed_a, same_seed_b), "same seed must produce an identical grid")

	var seed_one: Grid = MapGen.generate(1, WIDTH, HEIGHT)
	var seed_two: Grid = MapGen.generate(2, WIDTH, HEIGHT)
	assert_false(_grids_equal(seed_one, seed_two), "different seeds should (almost always) diverge")


func test_spawn_zones_reachable_across_many_seeds() -> void:
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, HEIGHT)
		var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.SpawnMarker.SPAWN_A)
		var spawn_b: Array[Vector2i] = _find_cells(grid, Enums.SpawnMarker.SPAWN_B)
		assert_true(spawn_a.size() > 0, "seed %d: spawn zone A must exist" % map_seed)
		assert_true(spawn_b.size() > 0, "seed %d: spawn zone B must exist" % map_seed)

		var pf := Pathfinder.new(grid)
		var path: Array[Vector2i] = pf.astar(spawn_a[0], spawn_b[0])
		assert_true(path.size() > 0, "seed %d: spawn zones must be path-connected" % map_seed)


## tb31 Pass C: a wall is now OPEN ground carrying a blocker Part too —
## structural, not `_scatter_cover`'s own roll, and empty space (unreachable
## rock, not floor at all) didn't exist when this band was tuned. Both
## excluded from the density measurement so it keeps meaning what it
## always meant: how much of the REAL walkable floor got a scattered
## cover roll, not "how much of the map is solid."
func test_cover_density_within_target_band() -> void:
	# Target band: 8%-30% of open floor cells carry cover. Documented tunable
	# (Appendix C notes exposure/cover weights are tune-later values).
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, HEIGHT)
		var open_count := 0
		var cover_count := 0
		for y in range(grid.rows):
			for x in range(grid.width):
				var cell := Vector2i(x, y)
				if Surface.first_walkable(grid.surfaces_at(cell)) == null:
					continue
				var blocker: Variant = grid.blocker_part_at(cell)
				if blocker != null and (blocker as Part).id == &"wall":
					continue
				open_count += 1
				if blocker != null:
					cover_count += 1
		var density: float = float(cover_count) / float(open_count)
		assert_between(
			density, 0.08, 0.30, "seed %d: cover density %.3f out of band" % [map_seed, density]
		)


## BR30.10: every uncarved cell that borders at least one carved cell must
## carry a real, indestructible blocker Part — otherwise `ShotPlane.build`
## (which reads only `state.units`/`state.grid.blockers`) has nothing
## standing in for that wall, and a shot
## resolves as if it wasn't there. An uncarved cell with no carved neighbor
## (buried in solid, unreachable rock) deliberately gets no blocker — it
## can never be the nearest hit along any real ray, so skipping it is a
## pure perf win, not a behavior change; this test locks that split in
## rather than letting a future change silently regress to "stamp every
## wall cell" (which would multiply `ShotPlane.build`'s own unculled
## per-shot scan by however much solid rock a map has).
## tb31 Pass C: an uncarved cell is only ever a scratch marker —
## `_finalize_walls_and_empty` resolves every remaining uncarved cell into
## either a real, destructible wall Part on real floored ground (exposed —
## reachable from the playable area) or empty space (buried in unreachable
## rock, no Part at all, the same perf reasoning BR30.10 originally
## established for skipping it).
## taskblock-39 Pass D: `Grid.terrain` and its physical-state codes are
## deleted — nothing on the real emitted `Grid` distinguishes "uncarved"
## from anything else any more, so the "no raw WALL cell survives" half of
## this test no longer has a claim to make; only the settled floored+wall-
## Part / unfloored split its placement output actually produces is left
## to check.
func test_generate_resolves_every_cell_into_a_destructible_wall_part_or_empty_space() -> void:
	var saw_wall_part := false
	var saw_empty := false
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, HEIGHT)
		for y in range(grid.rows):
			for x in range(grid.width):
				var cell := Vector2i(x, y)
				var floored: bool = Surface.first_walkable(grid.surfaces_at(cell)) != null
				if not floored:
					saw_empty = true
					assert_false(
						grid.blockers.has(cell),
						"seed %d: empty %s must carry no Part" % [map_seed, cell]
					)
					continue
				var blocker: Variant = grid.blocker_part_at(cell)
				if blocker != null and (blocker as Part).id == &"wall":
					saw_wall_part = true
					assert_true(
						(blocker as Part).is_destructible,
						"seed %d: wall %s must be destructible (tb31 Pass C)" % [map_seed, cell]
					)
	assert_true(saw_wall_part, "expected at least one wall Part across %d seeds" % SEED_COUNT)
	assert_true(saw_empty, "expected at least one empty cell across %d seeds" % SEED_COUNT)


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
			var part: Part = grid_a.blocker_part_at(cell)
			if part.id == &"barrel_pallet":
				counts_a.append(_attached_barrel_count(part))
		for cell: Vector2i in grid_b.blockers:
			var part: Part = grid_b.blocker_part_at(cell)
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
## taskblock-39 Pass B: scratch already defaults every cell to UNCARVED on
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
			if scratch.get_terrain(Vector2i(10, y)) == MapGenScratch.CellKind.OPEN:
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
				if scratch.get_terrain(Vector2i(x, y)) == MapGenScratch.CellKind.OPEN:
					open_cell_count += 1
		var hallway_cell_count: int = open_cell_count - room_cell_count
		assert_true(
			hallway_cell_count > 0,
			(
				"seed %d: expected hallway cells beyond room interiors, got %d"
				% [map_seed, hallway_cell_count]
			)
		)


## tb31 Pass C: opacity no longer lines up with an uncarved/open terrain
## split at all — a wall is real floored ground carrying a Part, and it's
## the Part's PRESENCE (not a terrain label) that keeps opacity at the 1.0
## the initial full-grid fill gave it. The real invariant now: opaque
## exactly where a wall Part sits, transparent everywhere else (empty
## space, plain floored ground, scattered cover — cover has never set
## opacity).
## taskblock-58 Pass C: this asserted that `Grid.opacity` read 1.0 exactly where a `wall` Part sat
## and 0.0 everywhere else — two parallel claims about the same cell, kept in step by the
## generator remembering to write both. The array is retired, so the claim becomes the thing it
## was standing in for: **a wall stops a sight line at eye height, and a cell with nothing on it
## does not.**
func test_sight_is_stopped_exactly_where_a_wall_part_sits() -> void:
	var grid: Grid = MapCorpus.read(7, WIDTH, HEIGHT)
	var spans: SightSpans = SightSpans.of(grid)
	var saw_wall := false
	var saw_open := false
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var eye: float = UnitGeometry.true_height_for_cell(cell, grid) + LoS.SIGHT_HEIGHT
			var blocker: Variant = grid.blocker_part_at(cell)
			if blocker != null and (blocker as Part).id == &"wall":
				assert_true(spans.blocks(cell, eye), "%s holds a wall and must stop sight" % cell)
				saw_wall = true
			elif blocker == null:
				assert_false(
					spans.blocks(cell, eye), "%s holds nothing and must not stop sight" % cell
				)
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
		var grid: Grid = MapCorpus.read(map_seed, 12, 10)
		var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.SpawnMarker.SPAWN_A)
		var spawn_b: Array[Vector2i] = _find_cells(grid, Enums.SpawnMarker.SPAWN_B)
		assert_true(spawn_a.size() > 0, "seed %d: spawn zone A must exist" % map_seed)
		assert_true(spawn_b.size() > 0, "seed %d: spawn zone B must exist" % map_seed)


## taskblock-38 Pass B: "MapGen writes floor parts... terrain/level become
## derived from placement" — the real acceptance is that every finished
## cell carries a real, correctly-typed floor surface (or none, if
## unfloored), across a whole generated map, not just a sample.
## taskblock-39 Pass B: this also covers "surfaces are emitted with no
## double-placement rejections" — a cell where `GridPlacement.place`
## silently returned null would show up here as `surfaces.size() != 1`.
## taskblock-39 Pass D: `Grid.terrain`/`Grid.level` are deleted, so this can
## no longer compare the placed surface against a second, parallel terrain/
## level source of truth — reconstructing that source's own formula by hand
## in a test is exactly the "re-derive it instead of reading the real thing
## back" trap CLAUDE.md warns against for view math, and the same logic
## tb60 Pass A: **and now every generated surface is a `ship_floor`, full stop.** The
## `is_ramp_at` stand-in this comment used to describe is deleted along with the ramp it
## checked for; a stair is ordinary floor tiles at fractional heights, so "correctly typed"
## has exactly one answer and the test says so directly.
##
## **And it counts WALKABLE surfaces, not every surface.** A ladder is a placed `Surface` too
## and is deliberately not walkable, so a repair ladder shares its cell with the floor under
## it — two surfaces, one floor, which is correct. This never surfaced before because the
## repair path reached for a ramp whenever the rise was under two levels and therefore
## almost never built a ladder at all; with the ramp gone the ladder is the only repair, and
## the assertion was counting the wrong thing all along.
func test_generated_map_cells_carry_at_most_one_correctly_typed_floor_surface() -> void:
	for map_seed in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, HEIGHT)
		for y in range(grid.rows):
			for x in range(grid.width):
				var cell := Vector2i(x, y)
				var floors: Array[Surface] = []
				for surface: Surface in grid.surfaces_at(cell):
					if Surface.WALKABLE_TAG in surface.part.tags:
						floors.append(surface)
				if floors.is_empty():
					continue
				assert_eq(
					floors.size(),
					1,
					"seed %d: %s must carry exactly one floor surface" % [map_seed, cell]
				)
				assert_eq(
					floors[0].part.id,
					&"ship_floor",
					"seed %d: %s surface part mismatch" % [map_seed, cell]
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

	MapGen._emit(grid, scratch)

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
	# Everything between stays UNCARVED (scratch's own default fill) --
	# deliberately disconnected, forcing the fallback.

	var pf := Pathfinder.new(scratch.as_temporary_grid())
	assert_true(pf.astar(a, b).is_empty(), "sanity: the two spawns start disconnected")

	MapGen._ensure_spawns_connected(grid, scratch, a, b, rng, Unit.BASE_STEP_HEIGHT)

	var pf_after := Pathfinder.new(scratch.as_temporary_grid())
	assert_false(
		pf_after.astar(a, b).is_empty(), "the fallback must actually connect the two spawns"
	)


## taskblock-38 Pass C: docs/PLAN.md's corrected ramp profile — two cells,
## not one. `inner` (bordering the room) is the upper step at
## `RAISED_ROOM_LEVEL - 0.5`; `outer`, one further out along the same
## approach, is the lower step at `RAISED_ROOM_LEVEL - 1.0` (real ground
## for a level-1 room). Both share one facing (the direction of ascent).
## taskblock-39 Pass B: `_connect_with_a_ramp` now carves scratch and
## records facing into `ramp_facings` again — surfaces aren't placed until
## `_emit` runs, at the very end.
func test_connect_with_a_stair_lays_evenly_spaced_treads_no_taller_than_the_step_height() -> void:
	var scratch := MapGenScratch.new(8, 3)
	var room := Rect2i(Vector2i(5, 1), Vector2i(2, 1))
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			scratch.set_level(Vector2i(x, y), MapGen.RAISED_ROOM_LEVEL)
	# `MapGenScratch` defaults every cell to UNCARVED -- the ring cells the stair runs
	# through must be carved open explicitly, matching what real BSP carving would already
	# have done by the time `_author_levels` (and therefore `_connect_with_a_stair`) runs.
	for x in range(0, 5):
		scratch.set_terrain(Vector2i(x, 1), MapGenScratch.CellKind.OPEN)

	MapGen._connect_with_a_stair(scratch, room, Unit.BASE_STEP_HEIGHT)

	# **Read as a run of differences, not as magic numbers.** What the pass promises is that no
	# step in the flight exceeds the step height; the specific heights are just how that
	# promise happens to be spelled at this rise and this constant. The tread count is derived
	# here for the same reason -- a retune of `BASE_STEP_HEIGHT` should move this fixture, not
	# redden it, and it has already moved once.
	var treads: int = maxi(1, int(ceil(1.0 / Unit.BASE_STEP_HEIGHT))) - 1
	var flight: Array[float] = [float(MapGen.RAISED_ROOM_LEVEL)]
	for i in range(treads):
		flight.append(scratch.get_level(Vector2i(4 - i, 1)))
	flight.append(0.0)  # the ground the flight lands on

	for i in range(1, flight.size()):
		var step: float = absf(flight[i - 1] - flight[i]) * UnitGeometry.LEVEL_HEIGHT
		assert_lte(
			step,
			Unit.BASE_STEP_HEIGHT + Unit.STEP_EPSILON,
			"step %d of the flight (%.3f) must be walkable without climbing" % [i, step]
		)
	var step: float = 1.0 / float(treads + 1)
	assert_almost_eq(
		flight[1], 1.0 - step, 0.0001, "the tread bordering the room is one step below its floor"
	)
	assert_almost_eq(
		flight[treads], step, 0.0001, "and the outermost tread is one step above ground"
	)
	# The cell past the flight was never touched -- a stair is exactly as long as it needs to
	# be. `4 - treads` is the first cell beyond the outermost tread.
	assert_almost_eq(scratch.get_level(Vector2i(4 - treads, 1)), 0.0, 0.0001)


## **The step count is derived, so a larger step height builds a shorter stair** -- the
## property that makes `BASE_STEP_HEIGHT` a tunable rather than a number the generator was
## built around. At 0.5 the same 1.0 rise needs 2 steps, so 1 tread.
func test_a_larger_step_height_builds_a_shorter_stair() -> void:
	var scratch := MapGenScratch.new(8, 3)
	var room := Rect2i(Vector2i(5, 1), Vector2i(2, 1))
	for x in range(room.position.x, room.position.x + room.size.x):
		scratch.set_level(Vector2i(x, 1), MapGen.RAISED_ROOM_LEVEL)
	for x in range(0, 5):
		scratch.set_terrain(Vector2i(x, 1), MapGenScratch.CellKind.OPEN)

	MapGen._connect_with_a_stair(scratch, room, 0.5)

	assert_almost_eq(scratch.get_level(Vector2i(4, 1)), 0.5, 0.0001, "one tread, halfway up")
	assert_almost_eq(scratch.get_level(Vector2i(3, 1)), 0.0, 0.0001, "and nothing beyond it")


## A stranded stair tread (its own room already flattened, or its far end cut off) must
## revert to plain ground at level 0, the same as a stranded room interior — otherwise the
## tread bordering a room sits at a genuinely non-zero level forever, an orphaned "raised"
## island of one cell the reachability test can actually see.
##
## tb60 Pass A: the cell is `OPEN` at a fractional level now rather than a `RAMP` kind, which
## is why the repair needed two branches before and needs one now. The defect it guards
## against is unchanged.
func test_repair_stranded_elevation_reverts_an_unreachable_tread_to_plain_ground() -> void:
	var grid := Grid.new(4, 1)
	var scratch := MapGenScratch.new(4, 1)
	var rooms: Array[Rect2i] = [Rect2i(Vector2i(0, 0), Vector2i(1, 1))]
	# A wall seals the anchor at (0, 0) off from everything past it -- the tread at (2, 0)
	# has nothing reachable on either side.
	scratch.set_terrain(Vector2i(1, 0), MapGenScratch.CellKind.UNCARVED)
	scratch.set_terrain(Vector2i(2, 0), MapGenScratch.CellKind.OPEN)
	scratch.set_level(Vector2i(2, 0), MapGen.RAISED_ROOM_LEVEL - 0.5)

	MapGen._repair_stranded_elevation(grid, scratch, rooms, Unit.BASE_STEP_HEIGHT)

	assert_eq(scratch.get_terrain(Vector2i(2, 0)), MapGenScratch.CellKind.OPEN)
	assert_almost_eq(scratch.get_level(Vector2i(2, 0)), 0.0, 0.0001)


## A ring position with no room for the full flight behind it (map edge on every side here)
## is never used — **no stair anywhere, not a malformed partial one that climbs halfway and
## stops at a wall.** A partial flight is worse than none, because it reads as a route.
## `_repair_stranded_elevation`'s own flood-and-flatten safety net is what catches the room
## this leaves stranded.
func test_connect_with_a_stair_places_nothing_when_no_approach_has_room_for_the_flight() -> void:
	var scratch := MapGenScratch.new(2, 3)
	var room := Rect2i(Vector2i(1, 1), Vector2i(1, 1))
	scratch.set_level(Vector2i(1, 1), MapGen.RAISED_ROOM_LEVEL)
	# Every ring cell is carved OPEN (matching what a real carve would have done) so this
	# genuinely tests "no ring position has room for the run" — the map edge is one cell away
	# on every side — rather than the uninteresting "nothing here is open at all".
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]:
		scratch.set_terrain(cell, MapGenScratch.CellKind.OPEN)

	MapGen._connect_with_a_stair(scratch, room, Unit.BASE_STEP_HEIGHT)

	for y in range(scratch.rows):
		for x in range(scratch.width):
			if Vector2i(x, y) == Vector2i(1, 1):
				continue  # the room itself
			assert_almost_eq(
				scratch.get_level(Vector2i(x, y)),
				0.0,
				0.0001,
				"no ring position here supports the flight, so nothing was raised"
			)


func test_spawn_zones_are_walkable() -> void:
	var grid: Grid = MapCorpus.read(3, WIDTH, HEIGHT)
	var pf := Pathfinder.new(grid)
	for cell: Vector2i in _find_cells(grid, Enums.SpawnMarker.SPAWN_A):
		assert_true(pf.is_walkable(cell))
	for cell: Vector2i in _find_cells(grid, Enums.SpawnMarker.SPAWN_B):
		assert_true(pf.is_walkable(cell))


## taskblock-39 Pass D: `Grid.terrain`/`get_terrain`/`set_terrain` are
## renamed to `Grid.spawn_marker`/`get_spawn_marker`/`set_spawn_marker` — a
## pure game-marker overlay `_place_spawn_zones`/`_mark_zone` are the only
## legitimate writers of. `Grid.level`/`get_level`/`set_level` are deleted
## outright, with nothing left to replace them (physical elevation now
## lives entirely in placed `Surface`s, per `MapGenScratch`'s own doc
## comment) — a reference to any of those retired names anywhere in this
## file is a leftover of the old model, not exempted here at all.
func test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking() -> void:
	var allowed_functions: Array[String] = ["_place_spawn_zones", "_mark_zone"]
	var file := FileAccess.open("res://src/logic/map_gen.gd", FileAccess.READ)
	assert_not_null(file, "sanity: map_gen.gd must exist to check at all")
	var current_function := ""
	var offending: Array[String] = []
	while not file.eof_reached():
		var line: String = file.get_line()
		var stripped: String = line.strip_edges()
		if stripped.begins_with("static func "):
			current_function = stripped.trim_prefix("static func ").split("(")[0]
		var touches_retired_api: bool = (
			"grid.set_terrain(" in line
			or "grid.get_terrain(" in line
			or "grid.set_level(" in line
			or "grid.get_level(" in line
		)
		var touches_spawn_marker: bool = (
			"grid.set_spawn_marker(" in line or "grid.get_spawn_marker(" in line
		)
		if touches_retired_api:
			offending.append("%s: %s (retired Grid API)" % [current_function, stripped])
		elif touches_spawn_marker and current_function not in allowed_functions:
			offending.append("%s: %s" % [current_function, stripped])
	assert_eq(
		offending,
		[] as Array[String],
		(
			"spawn-marker API used outside spawn-marking, or retired terrain/level API found: %s"
			% [offending]
		)
	)
