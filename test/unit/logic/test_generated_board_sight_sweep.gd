extends GutTest

## taskblock-64 Pass A2 — **the seed sweep, on the board a bout actually generates.**
##
## Pass A1's fixture answered `yes` to every close-range case it walked and the block treated
## that as "blindness does not reproduce". It walked **orthogonally adjacent** cells only —
## the narrowing `BR63.05` itself states — and `UtilityContext._nearest_known_enemy` measures
## `Grid.distance_chebyshev`, so *"an enemy one cell away"* in the supervisor's log **includes
## the four diagonals**. A diagonal pair at Chebyshev 1 has two cells between it that are not
## endpoints and are not exempt, so the premise *"nothing on that line can block"* does not
## hold for it.
##
## This sweeps a real generated board rather than a fixture, reports **every blind pair inside
## Chebyshev 3 with the geometry that blinded it named**, and breaks the count down by
## distance so the one-cell case is separated from the rest.

## The seed the supervisor's bout ran, at the size a bout generates.
const SWEEP_SEED: int = 642296523
const SWEEP_WIDTH: int = 40
const SWEEP_ROWS: int = 30
## How far apart two cells can be and still count as "close range" for this sweep.
const SWEEP_RADIUS: int = 3


## Every cell a unit could actually be standing on. A pair of unfloored cells has no bearing on
## whether two units can see each other, and sweeping them would bury the signal.
func _standable_cells(grid: Grid) -> Array[Vector2i]:
	var pathfinder := Pathfinder.new(grid)
	var cells: Array[Vector2i] = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if pathfinder.is_walkable(cell):
				cells.append(cell)
	return cells


## **What stood in the way**, named rather than counted.
##
## Runs `RayCaster.obstructed`'s own three loops rather than `cast_geometry`, and names the
## **box's own part** rather than the surface it hangs off. Both matter:
##
## - `cast_geometry` disagrees with `obstructed` here — it answered `null` for 56 of the blind
##   pairs in this sweep — so blaming with it would have left the largest bucket unexplained.
## - A ladder socketed into a `ship_floor`'s `LEDGE_W` is reached through the floor's
##   placement list, so blaming the surface root reports `ship_floor` for a 2.0-tall ladder
##   panel and hides the cause completely.
func _blamed(grid: Grid, a: Vector2i, b: Vector2i) -> String:
	var from: Vector3 = LoS.sight_point(grid, a)
	var to: Vector3 = LoS.sight_point(grid, b)
	var excluded: Array[Part] = LoS._endpoints(grid, a, b)
	var span: Vector3 = to - from
	var distance: float = span.length()
	var dir: Vector3 = span / distance
	var limit: float = distance - 0.0001

	for cell: Vector2i in grid.blockers:
		if RayCaster._blocker_in_the_way(grid, cell, from, dir, limit, excluded):
			return "%s (blocker)" % grid.blocker_part_at(cell).id

	var y_low: float = minf(from.y, to.y)
	var y_high: float = maxf(from.y, to.y)
	for surface: Surface in grid.placements():
		if surface.part == null or excluded.has(surface.part):
			continue
		if not BodyProjector.projects(surface.part):
			continue
		if not PartPicker.near_ray(surface.cell, from, dir, surface.height):
			continue
		if RayCaster._below_or_above(surface, y_low, y_high):
			continue
		var places: Array[BoxPlacement] = UnitGeometry.surface_placements(surface)
		for placement: BoxPlacement in places:
			var hit: Dictionary = UnitPicker.ray_box_hit(placement, from, dir)
			if not hit.is_empty() and float(hit["t"]) <= limit:
				var via: String = (
					"" if placement.part == surface.part else " on %s" % surface.part.id
				)
				return "%s (surface%s)" % [placement.part.id, via]
	return "?"


func test_close_range_sight_on_a_generated_board() -> void:
	var grid: Grid = MapCorpus.read(SWEEP_SEED, SWEEP_WIDTH, SWEEP_ROWS)
	var cells: Array[Vector2i] = _standable_cells(grid)
	gut.p(
		"seed %d at %dx%d: %d standable cells" % [SWEEP_SEED, SWEEP_WIDTH, SWEEP_ROWS, cells.size()]
	)

	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		seen[cell] = true

	# distance -> [pairs, blind]
	var totals: Dictionary = {}
	var blame: Dictionary = {}
	var samples: Array[String] = []
	for a: Vector2i in cells:
		for dy in range(-SWEEP_RADIUS, SWEEP_RADIUS + 1):
			for dx in range(-SWEEP_RADIUS, SWEEP_RADIUS + 1):
				var b: Vector2i = a + Vector2i(dx, dy)
				# Canonical ordering, so each unordered pair is asked exactly once.
				if b.y < a.y or (b.y == a.y and b.x <= a.x):
					continue
				if not seen.has(b):
					continue
				var distance: int = Grid.distance_chebyshev(a, b)
				if not totals.has(distance):
					totals[distance] = [0, 0]
				totals[distance][0] += 1
				if LoS.has_los(grid, a, b):
					continue
				totals[distance][1] += 1
				var who: String = _blamed(grid, a, b)
				blame[who] = int(blame.get(who, 0)) + 1
				if distance == 1 and samples.size() < 12:
					samples.append("%s->%s blocked by %s" % [a, b, who])

	for distance in range(1, SWEEP_RADIUS + 1):
		var row: Array = totals.get(distance, [0, 0])
		var pairs: int = row[0]
		var blind: int = row[1]
		var share: float = 0.0 if pairs == 0 else 100.0 * float(blind) / float(pairs)
		gut.p("  chebyshev %d: %d pairs, %d blind (%.2f%%)" % [distance, pairs, blind, share])

	var blamed_ids: Array = blame.keys()
	blamed_ids.sort_custom(func(x: String, y: String) -> bool: return blame[x] > blame[y])
	gut.p("  blamed geometry, most first:")
	for who: String in blamed_ids:
		gut.p("    %-24s %d" % [who, blame[who]])

	gut.p("  sample chebyshev-1 blind pairs:")
	for line: String in samples:
		gut.p("    %s" % line)

	assert_true(cells.size() > 0, "the sweep needs a board with somewhere to stand")


## **The one-cell case, split orthogonal from diagonal.** The whole of Pass A1 rests on
## orthogonal adjacency being unblockable, and it is; the number that matters is what the other
## four neighbours do.
func test_one_cell_blindness_splits_orthogonal_from_diagonal() -> void:
	var grid: Grid = MapCorpus.read(SWEEP_SEED, SWEEP_WIDTH, SWEEP_ROWS)
	var cells: Array[Vector2i] = _standable_cells(grid)
	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		seen[cell] = true

	var orthogonal: Array[int] = [0, 0]
	var diagonal: Array[int] = [0, 0]
	for a: Vector2i in cells:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var b: Vector2i = a + offset
			if not seen.has(b):
				continue
			var bucket: Array[int] = orthogonal if (offset.x == 0 or offset.y == 0) else diagonal
			bucket[0] += 1
			if not LoS.has_los(grid, a, b):
				bucket[1] += 1

	gut.p("  orthogonally adjacent: %d pairs, %d blind" % [orthogonal[0], orthogonal[1]])
	gut.p("  diagonally adjacent:   %d pairs, %d blind" % [diagonal[0], diagonal[1]])

	assert_eq(
		orthogonal[1],
		0,
		"the endpoint exemption makes an orthogonal neighbour unblockable — Pass A1's premise"
	)


## **The two loops must agree on the board that exposed the disagreement.** `BR64.01`.
##
## `test_sight_geometry.gd` sweeps this on seed 4242, which turned out not to contain the case
## at all. This seed does: it is the one the 56 divergent pairs were measured on, and it is the
## only board here carrying `TALL_ROOM_LEVEL` walls, whose `_stand_wall` placement height is the
## other place the two paths could drift (`_blocker_in_the_way` reads
## `blocker_height_for_cell`, `_consider_assembly` reads `true_height_for_cell`).
func test_the_sight_predicate_and_the_ray_march_agree_on_this_board() -> void:
	var grid: Grid = MapCorpus.read(SWEEP_SEED, SWEEP_WIDTH, SWEEP_ROWS)
	var cells: Array[Vector2i] = _standable_cells(grid)
	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		seen[cell] = true

	var compared := 0
	var blocked := 0
	var disagreements: Array[String] = []
	for a: Vector2i in cells:
		for dy in range(-SWEEP_RADIUS, SWEEP_RADIUS + 1):
			for dx in range(-SWEEP_RADIUS, SWEEP_RADIUS + 1):
				var b: Vector2i = a + Vector2i(dx, dy)
				if b.y < a.y or (b.y == a.y and b.x <= a.x):
					continue
				if not seen.has(b):
					continue
				# The real exemption, not a re-derivation of it — see the note in
				# `test_sight_geometry.gd`.
				var excluded: Array[Part] = LoS._endpoints(grid, a, b)
				var from: Vector3 = LoS.sight_point(grid, a)
				var to: Vector3 = LoS.sight_point(grid, b)
				var span: Vector3 = to - from
				var distance: float = span.length()
				if distance <= 0.0001:
					continue
				var any_hit: bool = RayCaster.obstructed(grid, from, to, excluded)
				# **`span`, not `span / distance`.** `cast_geometry` normalises what it is
				# given, so handing it an already-normalised vector normalises twice and lands
				# one float ULP away from the `span / length` that `obstructed` computes
				# internally. That is invisible until a ray passes through a box's exact corner,
				# where one ULP decides hit from miss — measured on this seed at
				# `(21,7)->(24,9)`, grazing a forklift's corner vertex at (21.45, 2.10, 7.30).
				# Neither loop is wrong there; the query is ill-posed. Passing the raw span is
				# what makes the two directions bit-identical and the comparison meaningful.
				var nearest: RayHit = RayCaster.cast_geometry(
					grid, from, span, excluded, distance - 0.0001
				)
				compared += 1
				if any_hit:
					blocked += 1
				if any_hit != (nearest != null) and disagreements.size() < 12:
					disagreements.append(
						(
							"%s->%s obstructed=%s march=%s"
							% [a, b, any_hit, "null" if nearest == null else str(nearest.part.id)]
						)
					)

	gut.p(
		(
			"  compared %d pairs, %d blocked, %d disagreements"
			% [compared, blocked, disagreements.size()]
		)
	)
	for line: String in disagreements:
		gut.p("    %s" % line)

	assert_gt(blocked, 0, "agreement proves nothing on a board where nothing blocks")
	assert_eq(
		disagreements,
		[] as Array[String],
		"RayCaster's header: the thing LoS sees and the thing a round meets cannot drift apart"
	)
