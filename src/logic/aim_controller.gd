class_name AimController
extends RefCounted

## docs/10 Phase 12.3, "the signature screen." Pure and testable — the whole
## dartboard UI reads from resolve()'s output and computes nothing itself
## (docs/08's three laws: no number is born in the view).
##
## The load-bearing rule: scrolling changes what you're READING, never what
## the reticle RESOLVES to. `reading` comes from `layers[layer_index]`;
## `resolves` is always a real ray cast (docs/09 taskblock06 Pass A,
## taskblock07 Pass A: `ShotPlane.resolve_ray`, not a plane-space lookup
## anymore), computed independently of `layer_index` entirely. That's what
## makes the sniper thread honest — the UI shows you a gap exists, it
## doesn't grant you the target through it.


## Groups `plane` into one AimLayer per distinct body (`Region.body`),
## nearest-first by that body's own nearest region. A `null` body (a Region
## built without going through ShotPlane.build — direct BodyProjector calls
## in older fixtures) groups into its own layer same as any other identity;
## real usage always goes through ShotPlane.build, which tags every region.
static func layers_for(plane: Array[Region]) -> Array[AimLayer]:
	var regions_by_body: Dictionary = {}
	var best_depth: Dictionary = {}
	var body_order: Array = []
	for region: Region in plane:
		var body: Variant = region.body
		if not regions_by_body.has(body):
			regions_by_body[body] = [] as Array[Region]
			body_order.append(body)
		(regions_by_body[body] as Array[Region]).append(region)
		if not best_depth.has(body) or region.depth < best_depth[body]:
			best_depth[body] = region.depth

	body_order.sort_custom(
		func(a: Variant, b: Variant) -> bool: return best_depth[a] < best_depth[b]
	)

	var layers: Array[AimLayer] = []
	for body: Variant in body_order:
		layers.append(AimLayer.new(body, regions_by_body[body]))
	return layers


## (plane, reticle, layer_index, weapon, shooter, target_cell, world) ->
## {layers, reading, resolves, rings}. `layer_index` is clamped into range,
## never out of bounds and never negative — scrolling past either end just
## holds at the last real layer. `target_cell` (not a whole target Unit) is
## the ONLY thing about the target `_resolve_hit` needs — it just names the
## shooter->target dead-ahead axis `reticle`'s own lateral/vertical
## coordinates are expressed against (`AimPlaneGeometry`'s own convention).
##
## docs/09 taskblock07 Pass A: `reading` (the READING side) still groups
## the CALLER's own `plane` — a preview clone TacticsController.aim_state()
## already built, and the only source `layers_for` needs. `resolves` (the
## RESOLVES side) goes through `ShotPlane.resolve_ray` now instead of a
## direct `resolve_projectile` lookup against that same `plane` — a real
## ray, cast from `shooter`'s own weapon muzzle, against `world` (the same
## preview state `plane` was built from). READING and RESOLVES staying two
## genuinely separate code paths (one groups a plane, one casts a ray) is
## the whole point (docs/09 taskblock06's own load-bearing rule, still
## true): scrolling can only ever change which layer `reading` names, never
## what `resolves` hits.
## tb34 Pass B: `action_id` — the armed action (`&"shoot"`/`&"burst"`/...)
## `resolve()` is drawing for, so `recoil_bound_radius` knows whether the
## shot about to be queued genuinely bursts (never inferred from the
## weapon alone: a weapon that CAN burst but is currently armed to single-
## shoot draws no bound). Defaults to `&""` (never burst) so every
## existing call site keeps behaving exactly as before this pass.
static func resolve(
	plane: Array[Region],
	reticle: Vector2,
	layer_index: int,
	weapon: Part,
	shooter: Unit,
	target_cell: Vector2i,
	world: CombatState,
	extra_sources: Array[ModSource] = [],
	action_id: StringName = &""
) -> AimResult:
	var layers: Array[AimLayer] = layers_for(plane)
	var reading: Variant = null
	if not layers.is_empty():
		var clamped: int = clampi(layer_index, 0, layers.size() - 1)
		reading = layers[clamped].body

	var rings: Array[Ring] = ShotScatter.for_shot(
		shooter, weapon, target_cell, world, extra_sources
	)
	return AimResult.new(
		layers,
		reading,
		_resolve_hit(reticle, weapon, shooter, target_cell, world),
		rings,
		recoil_bound_radius(rings, weapon, action_id == &"burst", extra_sources),
		pellet_circle_radius(weapon)
	)


## tb34 Pass B: the widest pull's own outer-ring radius
## (`RecoilResolver.widen` at `burst_size - 1`, the same formula
## `BurstAction` itself resolves through pull by pull) — 0.0 ("nothing to
## draw") when the armed action isn't really a burst, the weapon can't
## burst at all, or recoil is negligible enough that the widened ring
## coincides with the plain outer one (a doubled edge is worse than no
## bound at all).
static func recoil_bound_radius(
	rings: Array[Ring], weapon: Part, is_burst: bool, extra_sources: Array[ModSource] = []
) -> float:
	if not is_burst or rings.is_empty() or weapon == null or weapon.weapon_def == null:
		return 0.0
	var burst_size: int = weapon.weapon_def.burst_size
	if burst_size <= 1:
		return 0.0
	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var resolved_step: float = (
		WeaponResolver.resolve_recoil_step(weapon, damage, extra_sources).current
	)
	var widened: Array[Ring] = RecoilResolver.widen(rings, resolved_step, burst_size - 1)
	var outer: float = rings[rings.size() - 1].radius
	var widest: float = widened[widened.size() - 1].radius
	if is_equal_approx(widest, outer):
		return 0.0
	return widest


## tb34 Pass B: the mechanical pellet pattern's own resolved size
## (`SpreadPattern.pattern_radius`, the exact radius `BurstAction` itself
## scatters pellets within) — 0.0 ("draw the plain dot, not a circle")
## for any weapon that doesn't actually fire more than one projectile per
## pull. Never baked into the ring texture (see `DartboardTexture.build`'s
## own doc comment for why) — the caller draws this as its own overlay.
static func pellet_circle_radius(weapon: Part) -> float:
	if weapon == null or weapon.ammo_id == &"":
		return 0.0
	var ammo: AmmoDef = DataLibrary.get_ammo(weapon.ammo_id)
	if ammo == null or ammo.projectile_num <= 1:
		return 0.0
	return SpreadPattern.pattern_radius(weapon)


## taskblock-08 B2: the aim window's own depth (docs/09 taskblock06 Pass
## H) — "as close to the aimed-at model as possible without touching it,"
## just in front of the TARGET's own nearest (lowest-depth) region, never
## behind the shooter. Reverses taskblock-07 B2's own fix, which anchored
## to the currently-READ layer instead: scrolling to inspect a body behind
## the target used to drag the physical window back through the scene with
## it, when the shadow (aim_view.gd's own _decal) already stayed pinned at
## the target throughout — two different anchors for what's meant to read
## as one "painted on the target" surface. `target_body` identifies which
## of `layers` IS the target (`Region.body` identity, same as AimLayer's
## own grouping) — independent of `layer_index`/READING entirely now, the
## same "scrolling changes what you read, never what you're shooting at"
## rule this file's own header already applies to `resolves`.
## Pure math (headless-testable); the view only draws whatever this says.
## A body positioned "behind" the shooter along the fire line still gets a
## Region in the plane (ShotPlane.build projects every unit, not just ones
## in front), so its own frontmost depth can be small or even negative —
## `epsilon` alone can't guard against that (subtracting a small amount
## from an already-small-or-negative depth only makes it worse), so the
## result is always clamped to at least `min_depth`. `target_depth` is the
## fallback when the target has no region of its own in `layers` at all
## (an empty plane, or a degenerate target with no volume).
static func window_depth(
	layers: Array[AimLayer],
	target_body: Variant,
	target_depth: float,
	epsilon: float,
	min_depth: float
) -> float:
	var depth: float = target_depth
	for layer: AimLayer in layers:
		if layer.body == target_body:
			depth = layer.frontmost_depth() - epsilon
			break
	return maxf(depth, min_depth)


## docs/09 taskblock07 Pass A: a real ray cast from `weapon`'s own muzzle on
## `shooter`, through the world point `reticle` (plane-space: x lateral, y
## vertical) names — `AimPlaneGeometry.ray_from_muzzle` is the bridge
## `resolve_ray`'s own docstring calls for. `null` if the muzzle sits
## exactly on the shooter->target line already (no horizontal direction to
## fire along — the degenerate "shooting yourself" case).
static func _resolve_hit(
	reticle: Vector2, weapon: Part, shooter: Unit, target_cell: Vector2i, world: CombatState
) -> HitResult:
	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
	var ray: Dictionary = AimPlaneGeometry.ray_from_muzzle(
		shooter.cell, target_cell, reticle, muzzle
	)
	if ray.is_empty():
		return null
	return ShotPlane.resolve_ray(ray["origin"], ray["dir"], world)
