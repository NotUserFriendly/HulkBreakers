class_name SearchRoute
extends RefCounted

## taskblock-46 Pass C: `PATROL`'s route, and which point it should head for next.
##
## Split out from the planner because it is the only search verb with **state**, and
## state is the part worth being able to test without playing a turn. The other
## three verbs are a curve over a published input and need nothing remembered.
##
## ## Points are derived, never authored
##
## A patrol assigned at roster time would need a map the roster has never seen, so
## the route is generated lazily from wherever the unit finds itself. Generation is
## **deterministic without an RNG** — candidates are sorted before anything is
## chosen — which matters because `docs/00` requires the same seed to produce the
## same battle, and a route that varied per run would break that without ever
## looking like the cause.
##
## Farthest-point selection, greedily: the cell furthest from the origin, then
## repeatedly whichever candidate is furthest from everything already chosen. That
## spreads a handful of points across the reachable area instead of clustering them,
## which is what makes patrolling look like covering ground rather than pacing.
##
## ## Oldest visit wins, and that is the whole scheduling rule
##
## No authored order, no index to advance, no wrap-around. Three consequences fall
## out of it for free:
##
## - every point gets visited, because not being visited is what makes a point win;
## - it cannot ping-pong between two while a third is ignored, which an
##   advance-the-index scheme does the moment anything interrupts it;
## - a point that turns out to be unreachable **ages out of contention on its own**
##   — it stays "oldest" only until the unit gives up and stands somewhere else,
##   and no detect-and-remove step is needed.

## How many points a route has. Two is a pace, four starts to look like a job;
## flagged, not tuned.
const POINT_COUNT := 3
## How far from its origin a unit will lay out a route, in MP. Flagged.
const ROUTE_RADIUS := 10.0
## How close counts as standing on a point. A patrol point is a place, not a tile.
const ARRIVAL_RADIUS := 1


## Lays out a route around `origin`. Returns fewer than `POINT_COUNT` points — or
## none at all — when the reachable area is too small to spread them, which the
## caller must treat as "this unit has nowhere to patrol" rather than as an error.
static func generate(grid: Grid, origin: Vector2i, can_climb: bool = false) -> Array[Vector2i]:
	var pathfinder := Pathfinder.new(grid, can_climb)
	var costs: Dictionary = pathfinder.reachable_costs(origin, ROUTE_RADIUS)
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in costs:
		if cell != origin:
			candidates.append(cell)
	if candidates.is_empty():
		return []
	# **Sorted before anything is chosen.** `reachable_costs` returns a Dictionary,
	# and relying on its key order would make the route depend on flood order rather
	# than on the map — reproducible today and quietly not tomorrow.
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return (a.x * 100000 + a.y) < (b.x * 100000 + b.y)
	)

	var chosen: Array[Vector2i] = []
	while chosen.size() < POINT_COUNT and not candidates.is_empty():
		var best: Vector2i = candidates[0]
		var best_spread: int = -1
		for cell: Vector2i in candidates:
			var spread: int = Grid.distance_chebyshev(cell, origin)
			for taken: Vector2i in chosen:
				spread = mini(spread, Grid.distance_chebyshev(cell, taken))
			if spread > best_spread:
				best_spread = spread
				best = cell
		# A candidate that is not actually spread from what we have adds nothing but
		# a second name for the same place.
		if best_spread <= ARRIVAL_RADIUS:
			break
		chosen.append(best)
		candidates.erase(best)
	return chosen


## The point this unit should be heading for — **the one visited longest ago**, with
## never-visited counting as longest. Null when the unit has no route.
##
## Ties break on the point's own coordinates rather than on iteration order, so two
## equally-stale points do not hand the choice to whatever the array happened to
## look like.
static func next_point(unit: Unit) -> Variant:
	if unit == null or unit.patrol_points.is_empty():
		return null
	var best: Variant = null
	var best_visit: int = 0
	for point: Vector2i in unit.patrol_points:
		var visited: int = int(unit.patrol_visits.get(point, -1))
		if best == null or visited < best_visit:
			best = point
			best_visit = visited
			continue
		if (
			visited == best_visit
			and (
				(point.x * 100000 + point.y)
				< ((best as Vector2i).x * 100000 + (best as Vector2i).y)
			)
		):
			best = point
	return best


## Records that `unit` is standing on (or beside) one of its points this round.
## Called once per plan, before the next point is chosen, so a unit that has just
## arrived immediately stops being drawn back to where it already is.
static func record_arrival(unit: Unit, round_number: int) -> void:
	if unit == null:
		return
	for point: Vector2i in unit.patrol_points:
		if Grid.distance_chebyshev(unit.cell, point) <= ARRIVAL_RADIUS:
			unit.patrol_visits[point] = round_number
