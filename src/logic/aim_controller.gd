class_name AimController
extends RefCounted

## docs/10 Phase 12.3, "the signature screen." Pure and testable — the whole
## dartboard UI reads from resolve()'s output and computes nothing itself
## (docs/08's three laws: no number is born in the view).
##
## The load-bearing rule: scrolling changes what you're READING, never what
## the reticle RESOLVES to. `reading` comes from `layers[layer_index]`;
## `resolves` is always `ShotPlane.resolve_projectile` against the whole
## plane, computed independently of `layer_index` entirely. That's what
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


## (plane, reticle, layer_index) -> {layers, reading, resolves, rings}.
## `layer_index` is clamped into range, never out of bounds and never
## negative — scrolling past either end just holds at the last real layer.
static func resolve(
	plane: Array[Region],
	reticle: Vector2,
	layer_index: int,
	weapon: Part,
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
		ShotPlane.resolve_projectile(plane, reticle),
		Dartboard.resolve_scatter(weapon, extra_sources)
	)
