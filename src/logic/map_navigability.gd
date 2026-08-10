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
	return cells_that_can_reach(grid, origin, Pathfinder.new(grid, false, step_height))


## tb62 Pass D: **the same reverse flood, for a caller that has a real mover.**
##
## `_reverse_flood` judges a map against a bare step height, which is right for a generator
## with no roster. A planner asking *"if I go there, can I get back?"* has an actual unit, and
## a unit that can climb has return routes a bare pathfinder does not — so answering that
## question with the conservative mover would refuse descents that are perfectly recoverable
## for the body actually making them.
##
## One flood, not one per candidate. **The naive form is O(cells^2)** and this is the
## established cheap shape: a cell can reach `origin` exactly when `origin` reaches it
## backwards.
static func cells_that_can_reach(
	grid: Grid, origin: Vector2i, pathfinder: Pathfinder, exempt_origin: bool = false
) -> Dictionary:
	# `exempt_origin` is for flooding toward a cell somebody is standing in — "can I get to
	# the enemy" is a question about a cell that is occupied by definition, and gating it on
	# entering that cell answers "no" every time.
	var restore: Variant = pathfinder.ignored_occupant_cell()
	if exempt_origin:
		pathfinder.set_ignored_occupant_cell(origin)
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
	pathfinder.set_ignored_occupant_cell(restore)
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


## Every walkable cell that **no spawn can reach at all** — the blind spot `one_way_cells`
## has by construction, and the other half of the question this class exists to ask.
##
## `BR60.01`: `one_way_cells` floods out from a spawn, floods back, and reports the
## difference — *"you can get in and not out."* **A region you can never get into is not in
## the outward flood, so it can never be in that difference.** `stranding_cells` therefore
## returns empty on boards carrying hundreds of cells of unreachable raised ground, and does:
## measured at 40x30, **twelve regions across sixty seeds, the largest 235 cells**, identical
## before and after tb60's ramp retirement.
##
## The complement is the whole check — flood out from every spawn, union the results, and
## report every walkable cell left over. Same `move_cost` edges as `flood`, so this cannot
## develop its own idea of a legal step.
##
## **A cell carrying a live blocker is not walkable ground and never appears here.**
## `Pathfinder._base_cost` refuses it, so a crate on a lone raised cell — unreachable by
## construction, and somewhere no unit could stand whatever the terrain did — is correctly
## invisible to a check about *ground*. `test_map_gen.gd::_raised_regions` excludes them for
## exactly that reason and says so in its own header.
##
## A map with no spawns reports clean, the same posture `stranding_cells` takes and for the
## same reason: an authored fragment is incomplete, not broken.
static func unreachable_cells(
	grid: Grid, step_height: float = Unit.BASE_STEP_HEIGHT
) -> Array[Vector2i]:
	var spawns: Array[Vector2i] = spawn_cells(grid)
	if spawns.is_empty():
		return []
	var reached: Dictionary = {}
	for spawn: Vector2i in spawns:
		for cell: Variant in flood(grid, spawn, step_height):
			reached[cell] = true

	var pathfinder := Pathfinder.new(grid, false, step_height)
	var orphaned: Array[Vector2i] = []
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			if reached.has(cell):
				continue
			if not pathfinder.is_walkable(cell):
				continue
			orphaned.append(cell)
	orphaned.sort()
	return orphaned


## `unreachable_cells` grouped into 4-connected components, largest first — what a sweep
## reports when "312 cells" needs to become "one 235-cell shelf and a scattering of ledges"
## before a human can act on it. Region membership is contiguity alone; two regions may sit
## at the same height and are still two regions if you cannot walk between them.
static func unreachable_regions(grid: Grid, step_height: float = Unit.BASE_STEP_HEIGHT) -> Array:
	var pending: Dictionary = {}
	for cell: Vector2i in unreachable_cells(grid, step_height):
		pending[cell] = true

	var regions: Array = []
	# Iterated in row-major order rather than over `pending`'s own key order, so the region
	# list is a property of the board and not of dictionary insertion.
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var start := Vector2i(x, y)
			if not pending.has(start):
				continue
			var region: Array[Vector2i] = []
			var frontier: Array[Vector2i] = [start]
			pending.erase(start)
			while not frontier.is_empty():
				var cell: Vector2i = frontier.pop_back()
				region.append(cell)
				for offset: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var neighbour: Vector2i = cell + offset
					if not pending.has(neighbour):
						continue
					pending.erase(neighbour)
					frontier.append(neighbour)
			region.sort()
			regions.append(region)
	# Largest first, and **tie-broken on the top-left cell** — `sort_custom` is not a stable
	# sort, so size alone would let two equal regions swap between runs and a pinned sweep
	# would flap for no reason at all.
	regions.sort_custom(
		func(a: Array, b: Array) -> bool:
			if a.size() != b.size():
				return a.size() > b.size()
			return (a[0] as Vector2i) < (b[0] as Vector2i)
	)
	return regions


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
