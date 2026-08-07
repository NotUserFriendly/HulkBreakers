class_name MapNavigability
extends RefCounted

## taskblock-53 Pass D: **the invariant a generator owes — every cell you can walk into, you
## can walk back out of.**
##
## ## Why symmetric connectivity cannot see the defect
##
## `BR46.02`: descent is free and ascent is capability-gated, so a lowered region is a one-way
## door for every unit that currently exists. Spawn zones stay mutually reachable — the map is
## connected in the ordinary sense on **60 of 60** seeds — so an ordinary flood reports a clean
## board while a unit that wanders into a pit is out of the mission and still taking turns.
##
## The check that sees it is **asymmetric**: flood out from a spawn, then from each cell
## reached flood back, and ask whether the spawn is still in the set.
##
## ## Stranding is a legitimate outcome; unnavigable *generated* ground is not
##
## taskblock-53's governing decision. Players will knock enemies off ledges and shoot legs off
## so a target cannot pursue — **that is the game working**. What is a defect is a *generator*
## producing ground with no route out when nobody chose it. So this invariant belongs to map
## generation, never to runtime: nothing here is consulted during a bout.
##
## Deliberately runs a **non-climbing** `Pathfinder`. The whole point is that a map must be
## navigable by a unit with no climbing capability — checking with `can_climb` would pass maps
## that only a part nothing in the repo carries could traverse.
##
## ## tb60 Pass A: and against the LOWEST step height in play
##
## `step_height` is now a per-unit stat (`Unit.step_height`), so a rise can be free for one
## unit and a wall for another on the same board. The invariant has to assume the worst case
## or it certifies boards the shortest-legged unit cannot leave — which is `BR46.02` again,
## wearing a stat instead of a capability. Every entry point takes it, defaulting to
## `Unit.BASE_STEP_HEIGHT` (the unmodified body) rather than to something permissive;
## a caller holding a real roster passes `Unit.lowest_step_height(units)`.


## An unbounded flood: every cell reachable from `origin` under ordinary movement.
##
## `Pathfinder.reachable` is MP-bounded because a unit has a budget; navigability is a question
## about the *map*, so this walks the same `move_cost` edges with no budget at all. Sharing the
## edge function is what keeps this honest — a check with its own idea of a legal step would
## eventually disagree with the movement it is meant to guarantee.
static func flood(
	grid: Grid, origin: Vector2i, step_height: float = Unit.BASE_STEP_HEIGHT
) -> Dictionary:
	var pathfinder := Pathfinder.new(grid, false, step_height)
	var seen: Dictionary = {origin: true}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for neighbour: Vector2i in grid.neighbors(cell):
			if seen.has(neighbour):
				continue
			if pathfinder.move_cost(cell, neighbour) < 0.0:
				continue
			seen[neighbour] = true
			frontier.append(neighbour)
	return seen


## Every cell reachable from `origin` that cannot reach `origin` again — the one-way ground.
## Empty means the map is navigable from there.
##
## **The naive form is O(cells^2)**: flood out, then flood back from every cell reached. On a
## 40x30 board with most cells walkable that is a million floods' worth of work per seed, and a
## sweep over 40 seeds would be unusable. Instead the return flood runs **once**, from the
## origin, over *reversed* edges — a cell can reach the origin exactly when the origin can
## reach it backwards. Same answer, two floods instead of thousands.
static func one_way_cells(
	grid: Grid, origin: Vector2i, step_height: float = Unit.BASE_STEP_HEIGHT
) -> Array[Vector2i]:
	var outward: Dictionary = flood(grid, origin, step_height)
	var inward: Dictionary = _reverse_flood(grid, origin, step_height)
	var stranded: Array[Vector2i] = []
	for cell: Variant in outward:
		if not inward.has(cell):
			stranded.append(cell)
	stranded.sort()
	return stranded


## The flood that answers "which cells can reach `origin`", by walking every edge backwards:
## a step from `cell` to `neighbour` is admitted when `move_cost(neighbour, cell)` is legal.
static func _reverse_flood(grid: Grid, origin: Vector2i, step_height: float) -> Dictionary:
	var pathfinder := Pathfinder.new(grid, false, step_height)
	var seen: Dictionary = {origin: true}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for neighbour: Vector2i in grid.neighbors(cell):
			if seen.has(neighbour):
				continue
			if pathfinder.move_cost(neighbour, cell) < 0.0:
				continue
			seen[neighbour] = true
			frontier.append(neighbour)
	return seen


## Every spawn-marked cell on the board, in row-major order so a sweep is reproducible.
static func spawn_cells(grid: Grid) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_spawn_marker(cell) != Enums.SpawnMarker.NONE:
				cells.append(cell)
	return cells


## The whole-map verdict: one-way cells reachable from **any** spawn, deduplicated. A map with
## no spawns has nothing to flood from and reports clean rather than erroring — an authored
## fragment is not a broken map, it is an incomplete one, and `MapSerializer.describe_problems`
## is where that is said.
static func stranding_cells(
	grid: Grid, step_height: float = Unit.BASE_STEP_HEIGHT
) -> Array[Vector2i]:
	var found: Dictionary = {}
	for spawn: Vector2i in spawn_cells(grid):
		for cell: Vector2i in one_way_cells(grid, spawn, step_height):
			found[cell] = true
	var cells: Array[Vector2i] = []
	for cell: Variant in found:
		cells.append(cell)
	cells.sort()
	return cells
