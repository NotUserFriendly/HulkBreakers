class_name LineOfFire
extends RefCounted

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
## `has_clear_line_of_fire` and the planner's ally-in-line check: one
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
	# taskblock-37 Pass A: `from_cell` is a CANDIDATE cell, not necessarily
	# `shooter.cell` (this evaluates hypothetical reachable cells too) — its
	# own real level, not the shooter's cached one, is the honest origin
	# height for a shot fired from THAT cell specifically. No real muzzle
	# exists here (no weapon in view yet, only a candidate position), so
	# ground level is the origin height, same as `elevation_for`'s own
	# no-muzzle convention elsewhere.
	# taskblock-39 Pass C: reads the real placed `Surface`, not `Grid.level`.
	var origin_height: float = UnitGeometry.true_height_for_cell(from_cell, state.grid)
	var elevation: Dictionary = ShotPlane.elevation_for(
		origin, origin_height, from_cell, target.cell, state.grid
	)
	var plane: Array[Region] = ShotPlane.build(elevation.origin, elevation.direction, state)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	return _first_hit_excluding(plane, aim_point, shooter)


## tb35 Pass A3 (BR27.09): `first_hit` builds a real `ShotPlane` per call —
## the retired planner's reachability scan and its engagement scorer each
## independently resolved the shot from every reachable cell within one AI
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
## taskblock-44 Pass B: `field`, when supplied, is a `VisibilityField` built for
## `target` — a conservative prefilter that can only ever answer "definitely no
## line", never "yes". A cell it rejects skips the `ShotPlane` build entirely; a
## cell it accepts is resolved exactly as before. **`ShotPlane` stays final**:
## nothing here lets the field's opinion stand in for a real cast, which is what
## keeps this from becoming a second visibility system that could disagree with
## the canonical one.
static func has_clear_line_of_fire(
	shooter: Unit,
	target: Unit,
	from_cell: Vector2i,
	state: CombatState,
	cache: Variant = null,
	field: VisibilityField = null
) -> bool:
	if field != null and not field.allows(from_cell):
		return false
	var region: Region = cached_first_hit(shooter, target, from_cell, state, cache)
	return region != null and region.body == target


## docs/09 taskblock07 Pass A1: `ShotPlane.resolve_projectile` is that
## file's own internal lookup, forbidden to every other caller in `src/` —
## the same rect-lookup the AI planner used to keep locally before this class
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
