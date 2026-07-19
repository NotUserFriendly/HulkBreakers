class_name Pathfinder
extends RefCounted

## Pathfinding over a Grid using a Movement-Point (MP) budget. Pathfinder only
## knows MP costs — AP→MP conversion is a combat-layer concern (Appendix E).

const DEFAULT_COST: float = 1.0

var _grid: Grid
## terrain(int) -> float MP cost; missing = DEFAULT_COST, negative = blocked.
var _terrain_costs: Dictionary


func _init(grid: Grid, terrain_costs: Dictionary = {}) -> void:
	_grid = grid
	_terrain_costs = terrain_costs


## MP cost to step onto `cell`, or -1.0 if the cell is not walkable (out of
## bounds, occupied, blocked by a field object, or mapped to a negative
## terrain cost).
##
## taskblock-16 Pass B: `grid.blockers` (cover objects: scrap piles, goo
## barrels, pillars, ...) now blocks movement too, same as a unit does —
## the fix for "a unit can sit inside a piece of cover." Kept as its own
## check, never folded into `occupant_id`: that field is a Unit id
## everywhere else in this codebase (matched 1:1 against `Unit.id`, `-1`
## sentinel), and a field object is never a unit — a real cell can now be
## blocked by EITHER without the two concepts needing to share one field.
func move_cost(cell: Vector2i) -> float:
	if not _grid.in_bounds(cell):
		return -1.0
	if _grid.get_occupant_id(cell) != -1:
		return -1.0
	if _grid.blockers.has(cell):
		return -1.0
	var terrain: int = _grid.get_terrain(cell)
	if _terrain_costs.has(terrain):
		var cost: float = _terrain_costs[terrain]
		return cost if cost >= 0.0 else -1.0
	return DEFAULT_COST


func is_walkable(cell: Vector2i) -> bool:
	return move_cost(cell) >= 0.0


## docs/10 taskblock03 D2: the total MP a full path (inclusive of its own
## starting cell, same shape as astar()'s return) actually costs — the
## starting cell itself is free, the mover already stands there.
func path_cost(path: Array[Vector2i]) -> float:
	var total: float = 0.0
	for i in range(1, path.size()):
		total += move_cost(path[i])
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
			var cost: float = move_cost(neighbor)
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
			var cost: float = move_cost(neighbor)
			if cost < 0.0:
				continue
			var total: float = dist[current] + cost
			if total <= mp and total < dist.get(neighbor, INF):
				dist[neighbor] = total
				frontier.append(neighbor)
				if not result.has(neighbor):
					result.append(neighbor)

	return result
