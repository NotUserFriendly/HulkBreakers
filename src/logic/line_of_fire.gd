class_name LineOfFire
extends RefCounted

## tb33 Pass B: bounds for `approach_path`'s own Dijkstra flood — margin
## added to an authored weapon range, or a small flat default with no
## range to anchor on. Both flagged, not tuned design numbers.
const APPROACH_MARGIN := 5.0
const APPROACH_DEFAULT_RADIUS := 10.0

## tb33: line of FIRE, not line of SIGHT. `LoS` (`los.gd`) answers "can I
## see it" over pure opacity, by design ("cover never blocks vision — only
## opacity does; cover is a hit-resolution concern"). This answers "would
## a shot from here actually hit it" — the single canonical shot resolver
## (`ShotPlane`), never a parallel visibility system of its own. Root cause
## this exists to fix: tb31 C turned walls into cover-`Part`s that
## `ShotPlane` blocks (and ordinary scatter cover always has, since
## taskblock16) but that `LoS.has_los` has no reason to agree with — an AI
## reasoning about a "clear" line via sight alone could commit to a shot
## whose real geometry hits a wall or a piece of cover instead
## (BR30.10: 81% of impacts in one live mission landed on a wall instead
## of the intended target).


## The frontmost thing a shot from `from_cell` toward `target` would
## actually hit, excluding `shooter`'s own body — `null` if the line
## passes clean through everything, target included. Shared by
## `has_clear_line_of_fire` and `UnitAI._ally_in_firing_line`: one
## first-hit resolution built from the exact same `ShotPlane.build`/
## `center_of` path `AttackAction.apply()` itself resolves against, never
## a second, re-derived approximation of that geometry.
static func first_hit(
	shooter: Unit, target: Unit, from_cell: Vector2i, state: CombatState
) -> Region:
	var direction := Vector2(target.cell - from_cell)
	if direction.is_zero_approx():
		return null
	var origin := Vector2(from_cell.x, from_cell.y)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	return _first_hit_excluding(plane, aim_point, shooter)


## tb35 Pass A3 (BR27.09): `first_hit` builds a real `ShotPlane` per call —
## `_any_reachable_has_lof` and `_engagement_score` (`unit_ai.gd`) each
## independently resolve the shot from every reachable cell within one AI
## turn, so the same cell's shot got resolved twice or more, every turn.
## `cache`, when the caller supplies one (a plain `Dictionary` keyed by
## `from_cell`, shared across a whole reachable-cell sweep), makes every
## repeat lookup for a cell free; `null` (the default, every existing
## caller) resolves fresh every time, unchanged.
static func cached_first_hit(
	shooter: Unit, target: Unit, from_cell: Vector2i, state: CombatState, cache: Variant = null
) -> Region:
	if cache == null:
		return first_hit(shooter, target, from_cell, state)
	var memo: Dictionary = cache
	if not memo.has(from_cell):
		memo[from_cell] = first_hit(shooter, target, from_cell, state)
	return memo[from_cell]


## Clear iff the first thing the shot would actually hit is the target
## itself — a wall, a piece of cover, or the wrong unit as the first hit
## is blocked, exactly as a real fired shot would be.
static func has_clear_line_of_fire(
	shooter: Unit, target: Unit, from_cell: Vector2i, state: CombatState, cache: Variant = null
) -> bool:
	var region: Region = cached_first_hit(shooter, target, from_cell, state, cache)
	return region != null and region.body == target


## docs/09 taskblock07 Pass A1: `ShotPlane.resolve_projectile` is that
## file's own internal lookup, forbidden to every other caller in `src/` —
## the same rect-lookup `UnitAI` used to keep locally before this class
## existed. Excludes a body by identity (the shooter's own, which sits at
## the ray's own near-zero depth and would otherwise register as hitting
## itself before anything downrange ever does), not a part list.
## tb35 Pass B (BR34.06): floors at `depth >= 0`, same fix and same reason
## as `ShotPlane.resolve_projectile`'s own doc comment — this walker is a
## second, parallel implementation of that exact rect-lookup (forced by
## `resolve_projectile`'s own single-file restriction, `shot_plane.gd`'s
## own doc comment), so it carried the identical unfloored-depth bug
## independently. Unfloored, a wall many tiles behind the CANDIDATE cell
## (not the shooter's own body, so the identity exclusion above never
## catches it) sorted ahead of the real target and won on almost every
## candidate — which is why `has_clear_line_of_fire` read "no clear line"
## almost everywhere post-tb31's dense walls, not because real geometry
## actually blocked every shot: the AI holding every turn (BR34.06) was
## this same defect, not a separate one.
static func _first_hit_excluding(
	plane: Array[Region], point: Vector2, exclude_body: Unit
) -> Region:
	for region: Region in plane:
		if region.depth < 0.0:
			continue
		if region.body == exclude_body:
			continue
		if region.rect.has_point(point):
			return region
	return null


## tb33 Pass B (BR32.10): when nothing reachable this turn has a shot at
## all, the fix is to walk toward the nearest cell that WOULD — not the
## greedy least-bad reachable cell a single-turn scorer would otherwise
## settle for, which is what leaves a unit stuck facing a concave/
## U-shaped wall forever (the path around it can genuinely require a step
## that INCREASES raw distance to the enemy before it decreases, the one
## move a per-turn reachability scorer structurally can't make). Dijkstra
## to the nearest cell with real LOF (`Pathfinder.nearest_matching`,
## lazy — the expensive LOF check only runs on cells as they're actually
## popped, never the whole map), capped at `weapon`'s own authored range
## plus a margin so a hopeless, fully walled-off target doesn't scan the
## entire map; the resulting path is truncated to `budget` (this turn's
## own MP) — the same fallback re-fires next turn, walking the rest of
## the path, until a reachable cell genuinely has LOF and the normal fire
## path takes over. Returns an empty array if no cell within range has
## LOF; if one is found but `budget` can't afford even the first step
## toward it, returns a single-element path (just the unit's own current
## cell — `truncate_to_budget`'s own "inclusive of its own start"
## contract) rather than an empty one. Either way the caller's own
## `size() >= 2` check treats it as "nothing to do this turn," falling
## through to the existing hold/overwatch/end-turn fallback.
static func approach_path(
	unit: Unit, enemy: Unit, state: CombatState, pf: Pathfinder, weapon: Part, budget: float
) -> Array[Vector2i]:
	var radius_cap: float = (
		weapon.weapon_def.max_range + APPROACH_MARGIN
		if weapon != null and weapon.weapon_def != null and weapon.weapon_def.max_range > 0.0
		else APPROACH_DEFAULT_RADIUS
	)
	var target: Variant = pf.nearest_matching(
		unit.cell,
		radius_cap,
		func(cell: Vector2i) -> bool: return has_clear_line_of_fire(unit, enemy, cell, state)
	)
	if target == null:
		return []
	var full_path: Array[Vector2i] = pf.astar(unit.cell, target)
	return pf.truncate_to_budget(full_path, budget)


## tb35 Pass B (BR34.06): `approach_path` above is capped at the weapon's own
## range plus a margin, by design — but that leaves a unit that starts
## genuinely far from any LOF cell (nothing at all within the cap) with no
## way to make progress, holding forever even though a real route exists
## somewhere on the map. This is the fallback for exactly that case: real
## A* toward a cell next to `enemy`, no LOF requirement at all — deliberately
## NOT a greedy per-turn distance scorer (that reproduces the BR32.10
## concave/U-shaped-wall freeze `approach_path` itself exists to avoid,
## since a one-step hill-climb can get stuck the instant no reachable cell
## reduces raw distance further). `astar` already routes around obstacles by
## construction, so it doesn't share that failure mode, and it costs one
## pathfind per neighbor of `enemy`'s cell — never a per-cell LOF probe.
static func closing_path(
	unit: Unit, enemy: Unit, state: CombatState, pf: Pathfinder, budget: float
) -> Array[Vector2i]:
	var best_path: Array[Vector2i] = []
	var best_cost: float = INF
	for neighbor: Vector2i in state.grid.neighbors(enemy.cell):
		var candidate: Array[Vector2i] = pf.astar(unit.cell, neighbor)
		if candidate.size() < 2:
			continue
		var cost: float = pf.path_cost(candidate)
		if cost < best_cost:
			best_cost = cost
			best_path = candidate
	if best_path.is_empty():
		return []
	return pf.truncate_to_budget(best_path, budget)
