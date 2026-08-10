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
## taskblock-37 Pass E follow-up (supervisor): a real height cap now, not
## an integer level count — `Grid.level` itself is continuous, so a climb
## can be any real rise up to this many level-equivalents (still 1.0
## world unit at `UnitGeometry.LEVEL_HEIGHT`'s own default).
const MAX_CLIMB_LEVELS: float = 1.0
## taskblock-53 Pass C4: what a ladder edge multiplies the ordinary climb cost by.
##
## **Flagged, not designed**, and the first value here was backwards. The taskblock asks
## that a ladder cost *more than a ramp*; it should also cost **less than free-climbing**,
## or nobody would ever build one — a ladder exists to make a face easier, not harder.
## At 0.5 a ladder level costs 2.0 against a ramp's 1.0 and a bare climb's 4.0, which
## orders the three the way the fiction does.
##
## The first attempt used 1.5, making a ladder the most expensive way up. It also made
## tall ladders unusable: the whole rise is one edge, so a four-level ladder cost 16 and
## simply failed its affordability check. Recorded because the number looked defensible
## right up until a test climbed something tall.
##
## tb62 Pass C1: the reader that used to duplicate this scaling — `ClimbAction._cost` — is
## retired, and **this expression is now the only place a vertical step is priced.** Shaping
## cost by how tall a climb is stays entirely available here: `move_cost` sees an edge's full
## rise, so a superlinear or banded price is a change to this function and nothing else.
const LADDER_COST_SCALE: float = 0.5
## Hop-down is safe up to two levels; a deeper drop isn't a legal edge this
## pass (fall damage/knockdown are later work, explicitly out of scope).
const MAX_HOP_DOWN_LEVELS: float = 2.0

## taskblock-47 Pass A: how many floods and A* searches have run since the last
## reset. **Diagnostics only, never read by a decision** — the standing posture for
## counters in this codebase.
##
## Counted here rather than at the call sites because a flood is the unit of work
## that actually costs: `reachable`, `reachable_costs`, `astar` and everything built
## on them all bottom out in one, and a counter per caller would drift the moment a
## new caller appeared.
static var floods: int = 0

var _grid: Grid
## taskblock-37 Pass C: whether THIS pathfinding request's own mover can
## climb (`Shell.can_climb()`) — a property of the unit doing the moving,
## not of the grid, so it lives on the instance rather than `move_cost`
## taking it per call. Defaults false: every existing call site that isn't
## updated to pass a real unit's capability keeps its exact prior
## behaviour (never silently grants climbing).
var _can_climb: bool
## tb60 Pass A: the free rise THIS request's mover walks up — `Unit.step_height()`, a
## per-unit stat, on the instance for exactly the reason `_can_climb` is: it is a property
## of who is moving, not of the grid.
##
## Defaults to `Unit.BASE_STEP_HEIGHT` rather than to 0.0. The opposite posture from
## `_can_climb`, and deliberately: a 0.0 default would mean an un-updated call site silently
## refuses to walk up a stair, which is a *false negative about ordinary movement* rather
## than the false grant of a capability the `can_climb` default guards against. The
## unmodified body's own number is the honest default.
var _step_height: float

## tb62 Pass C2: **where the mover actually is, when that is not where its cell is.**
##
## A unit partway up a climb stands on its own cell at a height the cell does not have —
## that is the whole of what "a climb has a position along it" means. Every edge out of that
## cell has to be priced from the **body's** height, not the floor's, or a unit halfway up a
## ladder is quoted the full rise it has already half paid for.
##
## `NAN` means "no override" and is the default, so a pathfinder built for a grid rather than
## for a unit behaves exactly as it always did. It is also what an ordinary standing unit
## produces in effect: `Unit.height` equals `true_height_for_cell` for anyone not mid-climb,
## so the override is a no-op for every unit in every existing test.
##
## **Only the origin cell is overridden.** A search fans out across cells whose heights are
## the floor's by definition; the mover's own body height is a fact about exactly one cell.
var _origin_cell: Vector2i = Vector2i.ZERO
var _origin_height: float = NAN

## tb62 Pass D: **a unit never blocks itself.**
##
## `_base_cost` refuses any occupied cell, which is right for everyone else and wrong for the
## mover — its own cell is the one cell it is guaranteed to be able to stand on. Forward
## floods never noticed, because `reachable_costs` exempts its origin from cost-checking by
## construction. A **reverse** flood does notice: asking "which cells can reach where I am
## standing" gated every answer on entering a cell the asker was occupying, so the honest
## answer was always "none".
##
## Set by `for_unit` alone. A pathfinder built for a grid rather than a unit has no such cell
## and behaves exactly as before.
var _ignore_occupant_at: Variant = null


static func reset_diagnostics() -> void:
	floods = 0


func _init(grid: Grid, can_climb: bool = false, step_height: float = Unit.BASE_STEP_HEIGHT) -> void:
	_grid = grid
	_can_climb = can_climb
	_step_height = step_height


## **The one way a pathfinder is built for a real unit**, so a caller cannot read one
## mobility property off a unit and default the other. Every `Pathfinder.new(grid,
## unit.shell.can_climb())` in this codebase became this call at tb60 Pass A — the drift it
## prevents is the whole reason it exists rather than a second argument at fifteen sites.
## tb62 Pass C2: it also carries **where the unit's body actually is**, which for a unit
## partway up a climb is not where its cell's floor is. See `_origin_height`.
static func for_unit(grid: Grid, unit: Unit) -> Pathfinder:
	if unit == null:
		return Pathfinder.new(grid)
	var pathfinder := Pathfinder.new(grid, unit.shell.can_climb(), unit.step_height())
	pathfinder._origin_cell = unit.cell
	pathfinder._origin_height = unit.height
	pathfinder._ignore_occupant_at = unit.cell
	return pathfinder


## Read/write access to `_ignore_occupant_at` for a caller that needs to flood *toward* an
## occupied cell (`MapNavigability.cells_that_can_reach`). Deliberately a pair of methods
## rather than a public field: the exemption is a temporary borrow, and a caller that takes it
## has to give it back.
func ignored_occupant_cell() -> Variant:
	return _ignore_occupant_at


func set_ignored_occupant_cell(cell: Variant) -> void:
	_ignore_occupant_at = cell


## The height an edge leaving `cell` starts from: the mover's own body height when `cell` is
## where the mover is standing, and the cell's walkable floor otherwise.
##
## Identical answers for anyone not mid-climb, since `Unit.height` is synced from
## `true_height_for_cell` everywhere a unit finishes a move.
func _height_leaving(cell: Vector2i) -> float:
	if cell == _origin_cell and not is_nan(_origin_height):
		return _origin_height
	return UnitGeometry.true_height_for_cell(cell, _grid)


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
## taskblock-38 Pass D: "a cell with no surface has no edge into it at
## all" — real walkability comes from a placed, `walkable`-tagged
## `Surface`, not the terrain enum.
##
## taskblock-39 Pass C: the legacy fallback (a hand-built fixture Grid
## with no placed surfaces, answered from the pre-placement terrain/level
## formula through a migration bridge, taskblock-39 Pass D: retired
## outright) is gone — every fixture in this codebase now places real
## surfaces (`GridFixture`), so this reads the
## Surface path unconditionally.
##
## tb31 Pass C: reads the blocker's own `hp` now, not just its presence —
## a DESTROYED blocker (wall or cover) is passable. Before this, a dead
## crate (or, with BR30.10's wall geometry, a destroyed wall) still walled
## off its own cell forever: `ShotPlane`/`BodyProjector` already skip a
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
	if _grid.get_occupant_id(cell) != -1 and cell != _ignore_occupant_at:
		return -1.0
	if _grid.blockers.has(cell) and (_grid.blocker_part_at(cell) as Part).hp > 0:
		return -1.0
	return DEFAULT_COST if Surface.first_walkable(_grid.surfaces_at(cell)) != null else -1.0


## MP cost to step from `from` onto `to` (adjacent cells, though nothing
## here assumes it), or -1.0 if the edge doesn't exist at all — `to` isn't
## walkable, or the level delta between the two is a genuine ledge this
## mover can't cross (a climb beyond `MAX_CLIMB_LEVELS`, any climb at all
## without `_can_climb`, or a drop beyond `MAX_HOP_DOWN_LEVELS`).
##
## taskblock-38 Pass C: `docs/PLAN.md`'s settled cost table, verbatim —
## - **a rise (either way) within the mover's own `step_height` is ordinary
##   pathing at the plain terrain cost.** tb60 Pass A: this replaced the
##   ramp check that used to sit here — "either endpoint carries a
##   `Surface.RAMP_TAG`-tagged surface" — and the replacement is a better
##   rule, not a translation of the old one. A stair is now two ordinary
##   tiles at ordinary heights, and what makes them walkable is *how far up
##   they are*, never what they are labelled. A cosmetic ramp part still
##   exists and still renders as a slope; it simply gets no traversal
##   privilege the geometry does not earn.
## - same height: unchanged, the plain terrain cost (the vast majority of
##   edges).
## - climbing UP with no ramp: capability-gated, `CLIMB_COST` scaled by how
##   much of a full level's rise this edge actually covers, capped at
##   `MAX_CLIMB_LEVELS` — a non-climber simply has no such edge, not an
##   illegal-but-attempted one. **Partial MP costs round up** (docs/
##   PLAN.md, settled, not a fork) — a 1.2 MP climb charges 2.
## - dropping DOWN with no ramp: always legal up to `MAX_HOP_DOWN_LEVELS`,
##   flat `HOP_DOWN_COST` regardless of capability or how far within that
##   cap it actually drops — the taskblock's own settled table gives
##   hop-down no half variant, and "hop-down at 1 MP against 8 MP to climb
##   back makes one-way routes for free" is deliberately asymmetric.
## - a deeper drop, or a climb beyond the cap, is simply not an edge — no
##   per-unit fall-damage/knockdown modeling belongs here (later work,
##   with perks to avoid it).
##
## Height now comes from each cell's own placed `Surface`
## (`UnitGeometry.true_height_for_cell`), never a per-cell level field
## directly (taskblock-39 Pass D retired that field outright).
##
## taskblock-39 Pass C: the legacy fallback (the migration bridge's own
## pre-placement ramp/climb formula, for a hand-built fixture Grid with no
## placed surfaces) is gone, same reason as `_base_cost`.
func move_cost(from: Vector2i, to: Vector2i) -> float:
	var base: float = _base_cost(to)
	if base < 0.0:
		return -1.0
	var from_height: float = _height_leaving(from)
	var to_height: float = UnitGeometry.true_height_for_cell(to, _grid)
	var rise: float = to_height - from_height
	# **The one continuous comparison.** Up or down, within the step: it is a walk.
	# Symmetric on purpose — a stair you can climb is a stair you can descend, and an
	# asymmetric free rise would re-introduce exactly the one-way ground `BR46.02` was
	# about, one tenth of a level at a time.
	if absf(rise) <= _step_height + Unit.STEP_EPSILON:
		return base
	var level_delta: float = rise / UnitGeometry.LEVEL_HEIGHT
	if level_delta > 0.0:
		# taskblock-53 Pass C4: **one term, not a second branch.** A ladder standing at
		# `from` makes this edge crossable for a shell with no climbing capability at
		# all, and replaces the bare-face rise cap with the ladder's own reach — the
		# same rule `ClimbAction.is_legal` applies, read from the one shared formula so
		# the planner's idea of a legal edge and the action's cannot drift.
		var on_ladder: bool = Surface.ladder_serves_climb(_grid, from, to)
		if not on_ladder and (not _can_climb or level_delta > MAX_CLIMB_LEVELS):
			return -1.0
		# **Flagged, not designed** (CLAUDE.md): "ladder traversal should cost more than
		# a ramp. That number is flagged, not designed." A ladder edge costs the ordinary
		# climb, which already exceeds a ramp's `base`, times `LADDER_COST_SCALE`.
		var climb: float = CLIMB_COST * level_delta
		return ceil(climb * LADDER_COST_SCALE) if on_ladder else ceil(climb)
	if -level_delta <= MAX_HOP_DOWN_LEVELS:
		return HOP_DOWN_COST
	# taskblock-63 Pass D1: **a ladder is a route in both directions, and until a +4
	# generation height existed nothing had ever asked it to be.**
	#
	# The up branch above has consulted `ladder_serves_climb` since taskblock-53; the down
	# branch capped at `MAX_HOP_DOWN_LEVELS` and consulted nothing. That was invisible while
	# the tallest authored rise was one level — a one-level drop is under the cap, so the
	# ladder never mattered — and a **+4 shelf is impassable in both directions** without
	# this: too tall to climb bare, too tall to drop, so the ground below it is unreachable
	# rather than merely hard to leave. Measured at 40x30: five seeds carrying regions of
	# 65 to 286 cells, every one of them low ground ringed by a rise of exactly 4.0.
	#
	# **The ladder is read at the destination**, mirroring the up branch's "at the climber's
	# feet": climbing down, the thing you are climbing down onto is what has to reach you.
	# One shared formula, consulted from both ends, so a ladder cannot be a route one way and
	# scenery the other.
	if not Surface.ladder_serves_climb(_grid, to, from):
		return -1.0
	# **The same price in both directions, and that is a placeholder rather than a design.**
	# Nothing in this codebase says what climbing *down* a ladder should cost relative to
	# climbing up it, and inventing an asymmetry would be inventing a balance number. Reusing
	# the up expression keeps one formula and no new constant; if descent should be cheaper,
	# that is a knob here and nothing else changes.
	return ceil(CLIMB_COST * -level_delta * LADDER_COST_SCALE)


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
	floods += 1
	if a == b:
		return [a]
	if not is_walkable(b):
		return []

	# taskblock-39 Pass C: used to be the minimum of _terrain_costs' own
	# entries (a variable-cost terrain concept the legacy bridge alone
	# served) — every real edge now costs at least DEFAULT_COST (HOP_DOWN_
	# COST ties it, CLIMB_COST exceeds it), so that's the admissible floor.
	var heuristic_scale: float = DEFAULT_COST
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
	var result: Array[Vector2i] = [origin]
	for cell: Vector2i in reachable_costs(origin, mp):
		if cell != origin:
			result.append(cell)
	return result


## taskblock-46 Pass C: the same flood, keeping the distances it already computes.
##
## `cell -> path cost from origin`, always including `origin` at 0.0. **`reachable()`
## has always built this and thrown it away**, which is why straight-line distance
## got used in places that wanted path distance: the real number looked expensive
## and was already in hand.
##
## `origin` itself is never cost-checked, so a flood may be rooted on an occupied or
## blocked cell — which is what lets a caller ask "how far is everything from THAT
## unit" about a cell the unit is standing in. Edges are still gated normally
## (`move_cost` reads the destination), so nothing walks through anything.
func reachable_costs(origin: Vector2i, mp: float) -> Dictionary:
	floods += 1
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

		for neighbor: Vector2i in _grid.neighbors(current):
			var cost: float = move_cost(current, neighbor)
			if cost < 0.0:
				continue
			var total: float = dist[current] + cost
			if total <= mp and total < dist.get(neighbor, INF):
				dist[neighbor] = total
				frontier.append(neighbor)

	return dist


## taskblock-63 Pass C: **`reachable_costs` with every edge walked backwards** —
## `cell -> what it costs to travel FROM that cell TO `origin``, always including
## `origin` itself at 0.0.
##
## **These are two different questions and the forward one had been answering both.**
## `reachable_costs(target)` says *how far the target could walk to here*;
## this says *how far I must walk to the target*. On symmetric ground they agree
## exactly and the difference never showed. **On one-way ground they disagree
## exactly** — dropping off a shelf is cheap and climbing back is not — and a terraced
## board is made of one-way ground, so the outward flood read a cell under a shelf as
## nearly as good as one on it.
##
## **The relaxation is the whole trick.** Dijkstra needs a settled node to expand
## from, so the flood still grows outward from `origin`; what changes is that the edge
## priced when reaching `neighbor` is `move_cost(neighbor, current)` — the step that
## would be taken *toward* the origin — rather than the step away from it. Same
## complexity, one flood, no per-candidate pathfind.
##
## **`exempt_origin` is not optional decoration and taskblock-61 already paid for
## learning that.** `_base_cost` refuses an occupied cell, and `move_cost(from, to)`
## checks the DESTINATION — so in a reverse flood the one cell whose occupancy is ever
## tested as a destination is `origin` itself. Flooding toward a cell somebody is
## standing in (which "how far to the enemy" always is) therefore answers "nothing can
## reach it" for every cell on the board unless the origin is exempted. Every other
## cell on the board is only ever a *source* here, so nothing else needs exempting and
## nothing walks through anyone.
##
## Note the asymmetry with `reachable_costs`, which needs no such flag: an outward
## flood never has to *enter* its own root.
func costs_to_reach(origin: Vector2i, mp: float, exempt_origin: bool = false) -> Dictionary:
	floods += 1
	var restore: Variant = _ignore_occupant_at
	if exempt_origin:
		_ignore_occupant_at = origin
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

		for neighbor: Vector2i in _grid.neighbors(current):
			var cost: float = move_cost(neighbor, current)
			if cost < 0.0:
				continue
			var total: float = dist[current] + cost
			if total <= mp and total < dist.get(neighbor, INF):
				dist[neighbor] = total
				frontier.append(neighbor)

	_ignore_occupant_at = restore
	return dist


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
