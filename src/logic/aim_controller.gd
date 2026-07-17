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
static func resolve(
	plane: Array[Region],
	reticle: Vector2,
	layer_index: int,
	weapon: Part,
	shooter: Unit,
	target_cell: Vector2i,
	world: CombatState,
	extra_sources: Array[ModSource] = []
) -> AimResult:
	var layers: Array[AimLayer] = layers_for(plane)
	var reading: Variant = null
	if not layers.is_empty():
		var clamped: int = clampi(layer_index, 0, layers.size() - 1)
		reading = layers[clamped].body

	return AimResult.new(
		layers,
		reading,
		_resolve_hit(reticle, weapon, shooter, target_cell, world),
		Dartboard.resolve_scatter(weapon, extra_sources)
	)


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
