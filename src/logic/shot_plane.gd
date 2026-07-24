class_name ShotPlane
extends RefCounted

## The line-of-fire projection (docs/02): every unit and every piece of
## destructible cover along one direction, flattened into a single
## depth-sorted Array[Region]. `resolve_ray` (docs/09 taskblock06 Pass A,
## reshaped taskblock07 Pass A) is THE hit-resolution entry point — a real
## ray in, a `HitResult` out, and (taskblock07 Pass A1) the only production
## caller of `resolve_projectile` left anywhere in `src/` is this file
## itself: `resolve_projectile` is the internal rect-lookup `resolve_ray`
## runs, never a second, parallel resolution path a caller reaches for
## directly. That's what makes the no-drift invariant real rather than
## aspirational — there is no other door in.


## taskblock-37 Pass A: the shared seam every production firing action
## (`AttackAction`/`BurstAction`/`Overwatch`/`Suppression`/`LineOfFire`/
## `TacticsController`) now builds its own real 3D origin/direction
## through, instead of each re-deriving "target cell's own real height"
## independently. `origin_flat` is the shooter's own cell-space lateral
## position (already how every caller computes it: a real muzzle's `(x,
## z) / CELL_SIZE`, or a bare cell when no weapon-specific muzzle exists
## yet); `origin_height` is that shooter's own real world height (a real
## muzzle's `y`, or `grid.get_level(origin_cell) * UnitGeometry.
## LEVEL_HEIGHT` where no muzzle exists) — used only for `origin`'s own
## Vector3 (`build`'s absolute-height convention needs it there).
##
## The TILT itself is deliberately NOT "target's raw ground height minus
## the shooter's own absolute muzzle height" — a standing shooter's
## muzzle already sits above ITS OWN cell's ground by a real amount
## (shoulder/grip height), and that offset must not read as a downward
## tilt at an equal-level target 0.9 world units "below" the muzzle. The
## tilt is the LEVEL DIFFERENCE between the two cells (`Unit.level`'s own
## source, `Grid.level`) — exactly `0.0` whenever `origin_cell` and
## `target_cell` share a level, matching every flat shot before this
## pass, and nonzero only when they genuinely don't. This is exactly what
## tb36's own verification confirmed: two standing bodies' real muzzle
## heights differ by precisely `(target_level - origin_level) *
## LEVEL_HEIGHT`, since both carry the same baseline muzzle-above-own-
## level offset.
##
## `vertical_slope` — rise per unit of ground distance, the same
## quantity `resolve_ray` used to reconstruct locally before tb36 Pass C
## folded it into `build`'s own shear — is returned alongside `origin`/
## `direction` because `DamageResolver.resolve_shot` still needs it as an
## explicit scalar for its OWN separate, ricochet-carrying height test
## (`_find_next`); it is NOT re-derived a second way there, just handed
## across the boundary this function already computed it at.
static func elevation_for(
	origin_flat: Vector2,
	origin_height: float,
	origin_cell: Vector2i,
	target_cell: Vector2i,
	grid: Grid
) -> Dictionary:
	var flat: Vector2 = Vector2(target_cell) - origin_flat
	var level_delta: float = grid.get_level(target_cell) - grid.get_level(origin_cell)
	var height_delta: float = level_delta * UnitGeometry.LEVEL_HEIGHT
	var vertical_slope: float = 0.0 if flat.is_zero_approx() else height_delta / flat.length()
	return {
		"origin": Vector3(origin_flat.x, origin_height, origin_flat.y),
		"direction": Vector3(flat.x, height_delta, flat.y),
		"vertical_slope": vertical_slope,
	}


## Projects every living unit and every standing cover part in `state` into
## one plane, offset so each entity's local Regions land at its cell's true
## position relative to `origin`, and sorted nearest-shooter-first.
##
## taskblock-36 Pass A: `origin`/`direction` are `Vector3` now — pure
## plumbing, height carried but not yet consumed by everyday level callers.
## `BodyProjector.project`/`project_assembly` get the real 3D `dir3`, not a
## flattened slice — Pass B's own visibility test picks that up for free.
##
## taskblock-36 Pass C: `dir` is re-normalized in 2D after slicing off the
## vertical component (not left at whatever magnitude `dir3`'s own
## horizontal slice happens to have — a steep `direction` would otherwise
## shrink the whole plane's lateral/depth scale, the same bug Pass B fixed
## in `BodyProjector._project_box`).
##
## taskblock-37 Pass A: `shear` — default `false` — is `resolve_ray`'s OWN
## private convention, not this function's general contract. Region's own
## documented invariant is "rect's Y axis is real world height" (region.gd),
## and every OTHER production caller (`AttackAction`/`BurstAction`/
## `Overwatch`/`Suppression`/`LineOfFire`/`TacticsController`) reads a
## region's rect as an ABSOLUTE aim point — `center_of`, `first_hit`,
## `torso_region.rect.get_center()` all hand that value on to something
## else expecting real world height (`AimPlaneGeometry.world_point_at_
## depth`, `Dartboard.sample`, `self_obstruction`'s own `muzzle_height`
## test). tb36 Pass C's own `_shear` (still below) — subtracting `origin.y
## + vertical_slope * depth` to express "height relative to the ray's own
## path" — was undetected as `resolve_ray`-only because, before this pass,
## no OTHER caller ever passed a nonzero `origin.y`/`direction.y`; the
## moment a caller here started passing a shooter's real muzzle height,
## every `Region` it read back shifted by that same height, breaking the
## "absolute world height" contract those callers depend on. `resolve_ray`
## is the one caller that opts in (`shear = true`) — it queries at
## `Vector2.ZERO` for exactly that reason, never reading the resulting
## rect as an absolute point itself.
static func build(
	origin: Vector3, direction: Vector3, state: CombatState, shear: bool = false
) -> Array[Region]:
	var dir3: Vector3 = direction.normalized()
	var raw_horizontal := Vector2(dir3.x, dir3.z)
	var horizontal_len: float = raw_horizontal.length()
	var dir: Vector2 = raw_horizontal.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var origin_flat := Vector2(origin.x, origin.z)
	var vertical_slope: float = dir3.y / horizontal_len if horizontal_len > 0.0 else 0.0
	var regions: Array[Region] = []

	for unit: Unit in state.units:
		if not unit.alive:
			continue
		var offset := _offset(unit.cell, origin_flat, dir, perp)
		for region: Region in BodyProjector.project(unit, dir3):
			_place(region, offset)
			# taskblock-36 Pass D: `BodyProjector.project` composes a unit's
			# whole body in BODY-LOCAL space — it has no notion of `cell` or
			# `level` at all (that's `UnitGeometry`'s own, entirely separate
			# placement system, docs/10 "render is hitbox"). A unit's real
			# elevation only enters HERE, the one place a cell's world
			# position already gets composed in (`_offset`/`_place` above).
			# taskblock-37 Pass D: reads `unit.height` directly (already the
			# resolved, ramp-aware real height) rather than re-deriving it
			# from `unit.level * LEVEL_HEIGHT` — a unit resting on a ramp
			# tile is genuinely partway up, and "render is hitbox" means the
			# shot plane must agree with `UnitGeometry`'s own placements.
			region.rect.position.y += unit.height
			if shear:
				_shear(region, origin.y, vertical_slope)
			region.body = unit
			regions.append(region)

	for cell: Vector2i in state.grid.blockers:
		var part: Part = state.grid.blockers[cell]
		var offset := _offset(cell, origin_flat, dir, perp)
		# docs/10 taskblock04 C2: a field object can be a whole part TREE (a
		# dropped assembly — plate, weapon and all), not just one box, so
		# every attached part has to project too, not only the root's own
		# volume.
		for region: Region in BodyProjector.project_assembly(part, dir3):
			_place(region, offset)
			# taskblock-36 Pass D: a piece of cover sitting on an elevated
			# cell raises exactly like a unit standing there would.
			# taskblock-37 Pass E follow-up (supervisor, found during the
			# level-precision audit): was `grid.get_level(cell) *
			# LEVEL_HEIGHT` directly, missing a RAMP tile's own +0.5 rest
			# offset — `BoardView._spawn_blocker` already renders cover on a
			# ramp at its true (ramp-aware) height, so the shot plane must
			# resolve against that SAME real height, not a lower one, or a
			# hit on ramp-standing cover lands somewhere the rendered box
			# never actually occupies.
			region.rect.position.y += UnitGeometry.true_height_for_cell(cell, state.grid)
			if shear:
				_shear(region, origin.y, vertical_slope)
			region.body = part
			regions.append(region)

	regions.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)
	return regions


## taskblock-25 Pass D (docs/PLAN.md "Phase M — Melee"): "a stab hits if a
## disc of the weapon's width intersects a region... can't thread a gap
## narrower than its width." `radius <= 0.0` is exactly `rect.has_point` —
## every existing (ranged, point) caller is unchanged. A stepping stone to
## a real shapecast (docs/PLAN.md Pass D: "parameterize by a SHAPE, sphere
## as the first/simplest, not sphere-specific math") — this is the one
## place that math lives, so a later convex-shape swap-in touches only
## here.
static func disc_overlaps_rect(rect: Rect2, point: Vector2, radius: float) -> bool:
	if radius <= 0.0:
		return rect.has_point(point)
	var closest := Vector2(
		clampf(point.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(point.y, rect.position.y, rect.position.y + rect.size.y)
	)
	return point.distance_to(closest) <= radius


## Walks a depth-sorted plane and returns the frontmost Region containing
## `point` (or, taskblock-25 Pass D, overlapped by a disc of `radius`
## centered on `point`), or null if the shot passes clean through every
## one of them. `exclude_parts` skips any region belonging to those parts
## entirely — taskblock-22 Pass H2's own `self_obstruction` below uses
## this to keep a shooter's own body (at its own near-zero depth) from
## ever registering as its own obstruction.
## tb35 Pass B: `floor_at_zero`, default false, opt-in. `ShotPlane.build`'s
## own sort (`shot_plane.gd:45`) is a bare `a.depth < b.depth` with no
## floor, by design (the aim window legitimately reads negative-depth
## regions, `AimController.window_depth`'s own doc comment) — and depth
## itself is only "distance downrange from a real shooter" once a plane has
## gone through `build`'s own per-cell offset; called directly on a raw
## `BodyProjector.project` plane (every fixture in this file's own test
## suite, plus `test_reference_humanoid.gd`/`test_body_assembler.gd` etc.),
## depth is body-local instead, and a near-side face legitimately dips
## negative without meaning "behind the shooter" at all — flooring there
## unconditionally hides real, intended hits (found live: the lateral-armor
## fixture in `test_body_assembler.gd` broke this way). So the floor is
## opt-in, and only the callers below that resolve against a genuine
## `build`-produced, shooter-anchored plane turn it on: a region actually
## behind the ray's own origin has no business winning a "what does this
## shot hit" resolution there — unfloored, it sorts ahead of every real
## forward obstacle and wins outright once it isn't the shooter's own
## excluded body, which is exactly how a real fired shot (BR27.02: 12/12
## chaingun pulls) and the AI's own `LineOfFire.first_hit` predicate
## (BR34.06: the AI reading "no clear line" almost everywhere) both ended
## up resolving against a wall many tiles behind the shooter instead of the
## real target ahead of it.
static func resolve_projectile(
	plane: Array[Region],
	point: Vector2,
	exclude_parts: Array[Part] = [],
	radius: float = 0.0,
	floor_at_zero: bool = false
) -> Region:
	for region: Region in plane:
		if floor_at_zero and region.depth < 0.0:
			continue
		if exclude_parts.has(region.part):
			continue
		if disc_overlaps_rect(region.rect, point, radius):
			return region
	return null


## tb34 Pass C: "map the cursor to aim-plane coordinates and find the
## containing Region — the same rect-containment `ShotPlane` already
## resolves with." A plain public alias for `resolve_projectile` (which
## every OTHER caller in `src/` is forbidden from reaching directly —
## `test_resolve_projectile_is_called_only_from_shot_plane_itself`) so
## hover-to-part picking gets the identical lookup RESOLVES itself uses,
## never a second, re-derived hit test, without having to become a second
## exception to that rule.
static func region_at(plane: Array[Region], point: Vector2) -> Region:
	return resolve_projectile(plane, point, [], 0.0, true)


## taskblock-22 Pass H2: "the shot's ray originates and immediately hits
## the cover if the muzzle is below the cover's height." Tests the
## shooter's own real (H1: shouldered) muzzle height straight down the
## plane's own centerline (lateral=0 — the muzzle sits ON the ray's own
## line of travel) against this SAME already-built plane, rather than
## constructing a second, independently-anchored one the way
## `resolve_ray` does for the reticle/overwatch path. `shooter_parts`
## excludes the shooter's own body — same convention
## `DamageResolver.resolve_shot`'s own first `_find_next` call already
## uses to keep a shooter's own arm/leg from self-intercepting a
## collinear shot. Returns null if nothing at that height blocks the
## centerline at all — the caller decides whether what comes back is
## actually cover worth treating as an obstruction (e.g.
## `not (region.body is Unit)`), same as `resolve_projectile` itself
## doesn't know what a "unit" or "cover" is either.
static func self_obstruction(
	plane: Array[Region], muzzle_height: float, shooter_parts: Array[Part]
) -> Region:
	return resolve_projectile(plane, Vector2(0.0, muzzle_height), shooter_parts, 0.0, true)


## docs/09 taskblock06 Pass A / taskblock07 Pass A2: the ray-cast
## hit-resolution entry point, from `muzzle` — the shooter's own real
## muzzle position, an ordinary 3D world point, not a synthetic one built
## by the caller — along `dir`, against everything in `world`.
##
## taskblock-23 Pass C: `dir` may now travel with a real vertical
## component — the old `dir.y ~= 0` guard (docs/02's pre-multi-level "shots
## travel horizontally") is gone.
##
## taskblock-36 Pass C: `build` now does its own height reconciliation
## (`_shear`, above) — this function passes its REAL `muzzle`/`dir_n`
## through (no longer flattening them to `y == 0.0` first, Pass A's own
## temporary posture) and reads back a plane where every region's own
## `rect.position.y` is already height RELATIVE TO THIS RAY'S OWN PATH at
## that region's own depth. `0.0` is exactly "on the ray," at any depth —
## no separate `muzzle.y + vertical_slope * depth` reconstruction here
## anymore; `build` and `resolve_ray` now share one geometry instead of
## merely agreeing on its answer. A perfectly level `dir` (every real
## production caller today — `AimPlaneGeometry.ray_from_muzzle` expresses
## vertical aim by repositioning the muzzle's own height, deliberately
## keeping `dir.y == 0.0`, docs on that function) makes the shear exactly
## `0.0` throughout, reducing this to the exact old formula.
## taskblock-24 Pass C: `exclude_parts` skips those parts entirely — the
## same exclusion `resolve_projectile` itself already accepts, needed
## here for the same reason `AttackAction.apply()` excludes the shooter's
## own body from its own shot plane lookup: the ray's own origin sits
## AT/NEAR the caster's own position (near-zero depth), so a caster with
## a real, volumed torso would otherwise hit ITSELF first, every time,
## before ever reaching a real target downrange. Found live: `Overwatch.
## _torso_visible` called this with no exclusion at all — every overwatch
## fixture in this codebase's own test suite worked around it by building
## an overwatcher with NO torso volume, masking a real production bug
## that made overwatch structurally unable to trigger for any unit with
## an ordinary body.
static func resolve_ray(
	muzzle: Vector3, dir: Vector3, world: CombatState, exclude_parts: Array[Part] = []
) -> HitResult:
	var dir_n: Vector3 = dir.normalized()
	var flat_dir := Vector2(dir_n.x, dir_n.z)
	if flat_dir.is_zero_approx():
		# taskblock-36 Pass C: still an honest bail, not something this
		# pass's own reconciliation resolves — the plane's own lateral/
		# depth basis is built from the ray's GROUND-projected heading
		# (docs/02's plane, not a full pinhole camera), and a dead-vertical
		# ray has no ground heading to build one from at all. Picking an
		# arbitrary basis would silently rotate the dartboard's own
		# scatter axes shot to shot — an honest null beats that. A real
		# `PhysicsServer.intersect_ray` remains the documented swap-in for
		# exactly this case, never this plane's own math.
		return null
	var flat_origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
	var origin := Vector3(flat_origin.x, muzzle.y, flat_origin.y)
	# taskblock-37 Pass A: the one caller that opts INTO the shear — see
	# `build`'s own doc comment. `resolve_ray` queries at `Vector2.ZERO`
	# below precisely because it wants "relative to the ray," not an
	# absolute point read back out.
	var plane: Array[Region] = build(origin, dir_n, world, true)
	var region: Region = null
	for candidate: Region in plane:
		if candidate.depth < 0.0:
			continue
		if exclude_parts.has(candidate.part):
			continue
		if candidate.rect.has_point(Vector2.ZERO):
			region = candidate
			break
	if region == null:
		return null
	var t: float = region.depth / flat_dir.length()
	var hit_point: Vector3 = muzzle + dir_n * t
	return HitResult.new(
		region.part, hit_point, region.surface_normal, t, region.body, region.socket
	)


## Every unit with at least one Region in `plane`, nearest-first by its
## closest region's depth (docs/08): a UI must be able to show stats for a
## partially obscured target deeper in the plane, not only the one
## resolve_projectile would actually hit at a given point.
static func units_along(plane: Array[Region], state: CombatState) -> Array[Unit]:
	var best_depth: Dictionary = {}  # Unit -> float
	for unit: Unit in state.units:
		var unit_parts: Array[Part] = unit.shell.all_parts()
		for region: Region in plane:
			if unit_parts.has(region.part):
				if not best_depth.has(unit) or region.depth < best_depth[unit]:
					best_depth[unit] = region.depth

	var units: Array[Unit] = []
	for unit: Variant in best_depth.keys():
		units.append(unit)
	units.sort_custom(func(a: Unit, b: Unit) -> bool: return best_depth[a] < best_depth[b])
	return units


## The frontmost region belonging to `target`'s rect center — a point, never
## a chosen body part (docs/02: the dartboard picks a point, not a part).
## Shared by AttackAction's default aim point and the aim UI's reticle
## default (docs/10 Phase 12.3): both must agree on "center mass," never
## compute it twice.
static func center_of(plane: Array[Region], target: Unit) -> Vector2:
	var target_parts: Array[Part] = target.shell.all_parts()
	var best: Region = null
	for region: Region in plane:
		if not target_parts.has(region.part):
			continue
		if best == null or region.depth < best.depth:
			best = region
	if best == null:
		return Vector2(target.cell.x, target.cell.y)
	return best.rect.get_center()


## tb32 Pass C: the `center_of` counterpart for a non-unit target (wall/
## cover/downed object/field item, `PartPicker`'s new HitKind.PART) —
## matched by `region.body` rather than a Unit's `shell.all_parts()`:
## `ShotPlane.build` above tags every region in one blocker/field-item's
## own assembly with the SAME root-Part identity (`region.body = part`),
## so this finds the frontmost region belonging to that whole object the
## same way `center_of` finds the frontmost region belonging to a whole
## unit's body.
static func center_of_part(plane: Array[Region], part: Part, fallback_cell: Vector2i) -> Vector2:
	var best: Region = null
	for region: Region in plane:
		if region.body != part:
			continue
		if best == null or region.depth < best.depth:
			best = region
	if best == null:
		return Vector2(fallback_cell.x, fallback_cell.y)
	return best.rect.get_center()


## taskblock-37 Pass A: `center_of`'s own companion — the frontmost
## region's real DEPTH, not just its rect center. `DamageResolver._find_
## next` reconstructs a candidate's real height as `point.y + vertical_
## slope * (candidate.depth - point_depth)`: for a genuinely tilted first
## hop, the dartboard's own aim point sits at the TARGET's own depth, not
## the origin's, so testing OTHER candidates (in front of or behind the
## target) needs to adjust relative to THAT depth, not depth zero. `0.0`
## (no matching region) is exactly a ricochet's own convention too — a
## ricochet's continuation plane is always fresh-built from the deflection
## point itself, genuinely AT depth zero, so this reduces to the exact old
## formula for every ricochet hop and every caller that never computes a
## real point_depth at all.
static func depth_of(plane: Array[Region], target: Unit) -> float:
	var target_parts: Array[Part] = target.shell.all_parts()
	var best: Region = null
	for region: Region in plane:
		if not target_parts.has(region.part):
			continue
		if best == null or region.depth < best.depth:
			best = region
	return 0.0 if best == null else best.depth


## `center_of_part`'s own depth companion — see `depth_of`'s own doc
## comment for why this exists at all.
static func depth_of_part(plane: Array[Region], part: Part) -> float:
	var best: Region = null
	for region: Region in plane:
		if region.body != part:
			continue
		if best == null or region.depth < best.depth:
			best = region
	return 0.0 if best == null else best.depth


static func _offset(cell: Vector2i, origin: Vector2, dir: Vector2, perp: Vector2) -> Vector2:
	var world := Vector2(cell.x, cell.y) - origin
	return Vector2(world.dot(perp), world.dot(dir))


static func _place(region: Region, offset: Vector2) -> void:
	region.rect.position.x += offset.x
	region.depth += offset.y


## taskblock-36 Pass C: called after `_place` (so `region.depth` is already
## the real ground distance from `origin`) — subtracts the ray's own real
## world height AT that depth (`origin_height + vertical_slope * depth`)
## from the region's rect, converting its `rect.position.y` from absolute
## world height into height relative to the ray's own straight path. `0.0`
## is exactly `0.0` for a flat caller (`origin_height` and `vertical_slope`
## both `0.0`), so this is a no-op for every existing level caller.
static func _shear(region: Region, origin_height: float, vertical_slope: float) -> void:
	region.rect.position.y -= origin_height + vertical_slope * region.depth
