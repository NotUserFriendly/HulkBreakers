class_name Pathfinder
extends RefCounted

## Pathfinding over a Grid using a Movement-Point (MP) budget. Pathfinder only
## knows MP costs — AP→MP conversion is a combat-layer concern (Appendix E).

const DEFAULT_COST: float = 1.0

## taskblock-37 Pass C: "climb up" / "hop down" (docs/PLAN.md's own
## settled cost table) are absolute action costs, not a modifier stacked
## onto ordinary terrain cost.
const CLIMB_COST: float = 4.0
const HOP_DOWN_COST: float = 1.0
## Climbing is capped at one level by default (docs/PLAN.md: "a capability
## or part may raise that later" — nothing does yet, taskblock-37's own
## scope fence).
const MAX_CLIMB_LEVELS: int = 1
## Hop-down is safe up to two levels; a deeper drop isn't a legal edge this
## pass (fall damage/knockdown are later work, explicitly out of scope).
const MAX_HOP_DOWN_LEVELS: int = 2

var _grid: Grid
## terrain(int) -> float MP cost; missing = DEFAULT_COST, negative = blocked.
var _terrain_costs: Dictionary
## taskblock-37 Pass C: whether THIS pathfinding request's own mover can
## climb (`Shell.can_climb()`) — a property of the unit doing the moving,
## not of the grid, so it lives on the instance rather than `move_cost`
## taking it per call. Defaults false: every existing call site that isn't
## updated to pass a real unit's capability keeps its exact prior
## behaviour (never silently grants climbing).
var _can_climb: bool


func _init(grid: Grid, terrain_costs: Dictionary = {}, can_climb: bool = false) -> void:
	_grid = grid
	_terrain_costs = terrain_costs
	_can_climb = can_climb


## The plain per-cell terrain/occupancy cost of standing on `cell` — the
## whole of what `move_cost` used to be before taskblock-37 Pass C made it
## edge- (not just cell-) aware. `is_walkable` and `move_cost` both start
## here; level/ramp/climb reasoning is layered on top in `move_cost` alone,
## since "can a unit ever occupy this cell" and "what does stepping onto it
## from a SPECIFIC neighbor cost" are different questions once height
## enters the picture.
##
## taskblock-16 Pass B: `grid.blockers` (cover objects: scrap piles, goo
## barrels, pillars, ...) now blocks movement too, same as a unit does —
## the fix for "a unit can sit inside a piece of cover." Kept as its own
## check, never folded into `occupant_id`: that field is a Unit id
## everywhere else in this codebase (matched 1:1 against `Unit.id`, `-1`
## sentinel), and a field object is never a unit — a real cell can now be
## blocked by EITHER without the two concepts needing to share one field.
##
## tb31 Pass C: reads the blocker's own `hp` now, not just its presence —
## a DESTROYED blocker (wall or cover) is passable. Before this, a dead
## crate (or, with BR30.10's wall geometry, a destroyed wall) still walled
## off its own tile forever: `ShotPlane`/`BodyProjector` already skip a
## 0-hp Part when resolving a shot (`body_projector.gd`'s own hp<=0 check),
## but nothing ever told `Pathfinder` the blocker was gone. This is the
## shared fix both walls (Pass C's own destructibility) and every existing
## piece of scatter-cover benefit from — one mechanism, not two. Mangle/
## wreck states (a destroyed blocker clearing to passable-but-difficult
## rubble instead of fully clear ground) are explicitly deferred to a
## later authoring pass (PLAN.md) — this pass's own contract is exactly
## "destroyed clears to fully passable," nothing partial.
func _base_cost(cell: Vector2i) -> float:
	if not _grid.in_bounds(cell):
		return -1.0
	if _grid.get_occupant_id(cell) != -1:
		return -1.0
	if _grid.blockers.has(cell) and (_grid.blockers[cell] as Part).hp > 0:
		return -1.0
	var terrain: int = _grid.get_terrain(cell)
	if _terrain_costs.has(terrain):
		var cost: float = _terrain_costs[terrain]
		return cost if cost >= 0.0 else -1.0
	return DEFAULT_COST


## MP cost to step from `from` onto `to` (adjacent cells, though nothing
## here assumes it), or -1.0 if the edge doesn't exist at all — `to` isn't
## walkable, or the level delta between the two is a genuine ledge this
## mover can't cross (a climb beyond `MAX_CLIMB_LEVELS`, any climb at all
## without `_can_climb`, or a drop beyond `MAX_HOP_DOWN_LEVELS`).
##
## taskblock-37 Pass C: `docs/PLAN.md`'s settled cost table, verbatim —
## - a RAMP edge (either endpoint tagged `Enums.TerrainType.RAMP`) is
##   ordinary pathing at the plain terrain cost, whatever the level delta:
##   "a sloped tile costs 1 MP like any other; the path just changes
##   height as it goes." No special-casing beyond that check.
## - same level: unchanged, the plain terrain cost (the vast majority of
##   edges, and everything before this pass).
## - climbing UP a level with no ramp: capability-gated, `CLIMB_COST` per
##   level, capped at `MAX_CLIMB_LEVELS` — a non-climber simply has no
##   such edge, not an illegal-but-attempted one.
## - dropping DOWN with no ramp: always legal up to `MAX_HOP_DOWN_LEVELS`,
##   flat `HOP_DOWN_COST` regardless of capability — the taskblock's own
##   "hop-down at 1 MP against 8 MP to climb back makes one-way routes for
##   free," deliberately asymmetric.
## - a deeper drop, or a climb beyond the cap, is simply not an edge —
##   `_grid.get_level` alone decides this from the two cells, no per-unit
##   fall-damage/knockdown modeling belongs here (later work, with perks
##   to avoid it).
func move_cost(from: Vector2i, to: Vector2i) -> float:
	var base: float = _base_cost(to)
	if base < 0.0:
		return -1.0
	if (
		_grid.get_terrain(from) == Enums.TerrainType.RAMP
		or _grid.get_terrain(to) == Enums.TerrainType.RAMP
	):
		return base
	var level_delta: int = _grid.get_level(to) - _grid.get_level(from)
	if level_delta == 0:
		return base
	if level_delta > 0:
		if not _can_climb or level_delta > MAX_CLIMB_LEVELS:
			return -1.0
		return CLIMB_COST
	if -level_delta > MAX_HOP_DOWN_LEVELS:
		return -1.0
	return HOP_DOWN_COST


func is_walkable(cell: Vector2i) -> bool:
	return _base_cost(cell) >= 0.0


## docs/10 taskblock03 D2: the total MP a full path (inclusive of its own
## starting cell, same shape as astar()'s return) actually costs — the
## starting cell itself is free, the mover already stands there.
func path_cost(path: Array[Vector2i]) -> float:
	var total: float = 0.0
	for i in range(1, path.size()):
		total += move_cost(path[i - 1], path[i])
	return total


func _min_possible_cost() -> float:
	var m: float = DEFAULT_COST
	for cost: float in _terrain_costs.values():
		if cost >= 0.0 and cost < m:
			m = cost
	return m


## docs/10 taskblock04 B: with a per-cell MP cost and a Chebyshev heuristic,
## a diagonal step costs exactly what an orthogonal one does — every
## ordering of the same step multiset ties on `g`, and without a tie-break
## the frontier returns whichever the open set coughs up first, typically a
## staircase. This is purely cosmetic: it never changes what a path costs
## (B1's own constraint — no fractional MP, no irrational diagonal costs),
## only which same-cost path among several ties gets returned. True if
## `candidate` is strictly smoother than `best`: fewer total direction
## changes first; on a further tie, a path whose own last step continues
## its heading beats one that just turned onto it.
static func _smoother(
	candidate_changes: int, candidate_turned: bool, best_changes: int, best_turned: bool
) -> bool:
	if candidate_changes != best_changes:
		return candidate_changes < best_changes
	return int(candidate_turned) < int(best_turned)


## Shortest MP-cost path from a to b, inclusive of both endpoints. Empty array
## if no path exists (or b is unwalkable). `a` is never checked for
## walkability — the mover already stands there, occupying its own cell, so
## gating on that would make every real in-game path request fail.
func astar(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if a == b:
		return [a]
	if not is_walkable(b):
		return []

	var heuristic_scale: float = _min_possible_cost()
	var open_set: Array[Vector2i] = [a]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {a: 0.0}
	var f_score: Dictionary = {a: Grid.distance_chebyshev(a, b) * heuristic_scale}
	# docs/10 taskblock04 B3: the direction of the last step INTO a cell on
	# its currently-best path (ZERO at the start cell, which has no
	# incoming step to compare a later turn against), and that path's total
	# turn count — both carried forward so a later tie-break never has to
	# walk `came_from` back up to re-derive them.
	var heading: Dictionary = {a: Vector2i.ZERO}
	var turn_count: Dictionary = {a: 0}
	var last_turned: Dictionary = {a: false}

	while not open_set.is_empty():
		var current: Vector2i = open_set[0]
		var current_index: int = 0
		for i in range(1, open_set.size()):
			var cand: Vector2i = open_set[i]
			if f_score.get(cand, INF) < f_score.get(current, INF):
				current = cand
				current_index = i

		if current == b:
			return _reconstruct_path(came_from, current)
		open_set.remove_at(current_index)

		for neighbor: Vector2i in _grid.neighbors(current):
			var cost: float = move_cost(current, neighbor)
			if cost < 0.0:
				continue
			var tentative_g: float = g_score[current] + cost
			var edge_dir: Vector2i = neighbor - current
			var turned: bool = heading[current] != Vector2i.ZERO and heading[current] != edge_dir
			var tentative_changes: int = turn_count[current] + int(turned)

			var better: bool = tentative_g < g_score.get(neighbor, INF)
			if not better and tentative_g == g_score.get(neighbor, INF):
				better = _smoother(
					tentative_changes,
					turned,
					turn_count.get(neighbor, 0),
					last_turned.get(neighbor, false)
				)

			if better:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = (
					tentative_g + Grid.distance_chebyshev(neighbor, b) * heuristic_scale
				)
				heading[neighbor] = edge_dir
				turn_count[neighbor] = tentative_changes
				last_turned[neighbor] = turned
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return []


func _reconstruct_path(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [end]
	var current: Vector2i = end
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path


## All cells reachable from origin within an MP budget (Dijkstra), including
## origin itself at zero cost. Blocked cells and cells over budget are excluded.
func reachable(origin: Vector2i, mp: float) -> Array[Vector2i]:
	var dist: Dictionary = {origin: 0.0}
	var frontier: Array[Vector2i] = [origin]
	var result: Array[Vector2i] = [origin]

	while not frontier.is_empty():
		var current: Vector2i = frontier[0]
		var current_index: int = 0
		for i in range(1, frontier.size()):
			var cand: Vector2i = frontier[i]
			if dist[cand] < dist[current]:
				current = cand
				current_index = i
		frontier.remove_at(current_index)

		for neighbor: Vector2i in _grid.neighbors(current):
			var cost: float = move_cost(current, neighbor)
			if cost < 0.0:
				continue
			var total: float = dist[current] + cost
			if total <= mp and total < dist.get(neighbor, INF):
				dist[neighbor] = total
				frontier.append(neighbor)
				if not result.has(neighbor):
					result.append(neighbor)

	return result


## tb33 Pass B (BR32.10): the same Dijkstra flood as `reachable()`, but
## "give me the first cell matching X" instead of "give me everything" —
## `stop_at` (`Callable(Vector2i) -> bool`) is evaluated once per cell, in
## ascending path-cost order, the instant it's POPPED (Dijkstra's own
## invariant: a popped cell's distance is already final, given no
## negative edges — `move_cost()` only ever returns `>= 0.0` or a skipped
## `-1.0`), so this returns the genuinely NEAREST match, not just the
## first one merely discovered. Evaluated lazily, cell by cell, so an
## expensive `stop_at` (a real `ShotPlane` build, say) never runs on more
## cells than it has to. `radius_cap` bounds the flood — a target with no
## match anywhere reachable doesn't scan the whole map. Returns the
## matching cell, or `null` if the flood exhausts `radius_cap` without one.
func nearest_matching(origin: Vector2i, radius_cap: float, stop_at: Callable) -> Variant:
	var dist: Dictionary = {origin: 0.0}
	var frontier: Array[Vector2i] = [origin]

	while not frontier.is_empty():
		var current: Vector2i = frontier[0]
		var current_index: int = 0
		for i in range(1, frontier.size()):
			var cand: Vector2i = frontier[i]
			if dist[cand] < dist[current]:
				current = cand
				current_index = i
		frontier.remove_at(current_index)

		if stop_at.call(current):
			return current

		for neighbor: Vector2i in _grid.neighbors(current):
			var cost: float = move_cost(current, neighbor)
			if cost < 0.0:
				continue
			var total: float = dist[current] + cost
			if total <= radius_cap and total < dist.get(neighbor, INF):
				dist[neighbor] = total
				frontier.append(neighbor)

	return null


## tb33 Pass B: the longest PREFIX of `path` (inclusive of its own start)
## affordable within `mp` — for a queued move that must fit THIS turn's
## own budget, as opposed to `path_cost()`'s "what does the WHOLE path
## cost" question (`MoveAction.is_legal()`'s own concern, which rejects
## the entire action if the full path is unaffordable rather than
## partially completing it at the queueing stage). Same walk `path_cost()`
## already does, just stopping the instant the running total would
## exceed budget instead of summing to the end.
func truncate_to_budget(path: Array[Vector2i], mp: float) -> Array[Vector2i]:
	if path.is_empty():
		return []
	var truncated: Array[Vector2i] = [path[0]]
	var total: float = 0.0
	for i in range(1, path.size()):
		var cost: float = move_cost(path[i - 1], path[i])
		if cost < 0.0 or total + cost > mp:
			break
		total += cost
		truncated.append(path[i])
	return truncated
