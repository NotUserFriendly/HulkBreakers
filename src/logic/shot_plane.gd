class_name ShotPlane
extends RefCounted

## The line-of-fire projection (docs/02): every unit and every piece of
## destructible cover along one direction, flattened into a single
## depth-sorted Array[Region]. `resolve_ray` (docs/09 taskblock06 Pass A) is
## the hit-resolution entry point now — a real ray in, a `HitResult` out.
## `resolve_projectile`, the old "does this rect contain the point" 2D
## lookup, hasn't moved; it's the math `resolve_ray` runs internally, and
## the aim-preview UI (AimController) still calls it directly since it
## already works in plane space. Both answer the exact same question the
## exact same way — that's the no-drift invariant (test coverage).


## Projects every living unit and every standing cover part in `state` into
## one plane, offset so each entity's local Regions land at its cell's true
## position relative to `origin`, and sorted nearest-shooter-first.
static func build(origin: Vector2, direction: Vector2, state: CombatState) -> Array[Region]:
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var regions: Array[Region] = []

	for unit: Unit in state.units:
		if not unit.alive:
			continue
		var offset := _offset(unit.cell, origin, dir, perp)
		for region: Region in BodyProjector.project(unit, dir):
			_place(region, offset)
			region.body = unit
			regions.append(region)

	for cell: Vector2i in state.grid.blockers:
		var part: Part = state.grid.blockers[cell]
		var offset := _offset(cell, origin, dir, perp)
		# docs/10 taskblock04 C2: a field object can be a whole part TREE (a
		# dropped assembly — plate, weapon and all), not just one box, so
		# every attached part has to project too, not only the root's own
		# volume.
		for region: Region in BodyProjector.project_assembly(part, dir):
			_place(region, offset)
			region.body = part
			regions.append(region)

	regions.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)
	return regions


## Walks a depth-sorted plane and returns the frontmost Region containing
## `point`, or null if the shot passes clean through every one of them.
static func resolve_projectile(plane: Array[Region], point: Vector2) -> Region:
	for region: Region in plane:
		if region.rect.has_point(point):
			return region
	return null


## docs/09 taskblock06 Pass A: the ray-cast hit-resolution entry point. A
## straight, level shot (`docs/02`/BodyProjector: "shots travel
## horizontally") from `origin` along `dir`, against everything in `world`.
##
## Built entirely on the existing plane math — `origin`'s own lateral and
## vertical offset from the ray's own line of travel is, by construction,
## zero, so the plane is anchored at `origin` itself and tested against
## `(0, origin.y)`. That's the whole seam: a caller that used to build a
## plane at the shooter's cell and hand `resolve_projectile` a
## center-plus-aim-offset point now instead hands `resolve_ray` a world
## point already carrying that offset (`AimPlaneGeometry.world_point`
## produces exactly this) — same math, same regions, same results, and
## later a `PhysicsServer.intersect_ray` swap-in changes this function's
## body and nothing that calls it.
static func resolve_ray(origin: Vector3, dir: Vector3, world: CombatState) -> HitResult:
	var flat_origin := Vector2(origin.x, origin.z) / UnitGeometry.CELL_SIZE
	var flat_dir: Vector2 = Vector2(dir.x, dir.z).normalized()
	if flat_dir.is_zero_approx():
		return null
	var plane: Array[Region] = build(flat_origin, flat_dir, world)
	var region: Region = resolve_projectile(plane, Vector2(0.0, origin.y))
	if region == null:
		return null
	var dir3d := Vector3(flat_dir.x, 0.0, flat_dir.y)
	var hit_point: Vector3 = origin + dir3d * region.depth
	return HitResult.new(region.part, hit_point, region.surface_normal, region.depth, region.body)


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


static func _offset(cell: Vector2i, origin: Vector2, dir: Vector2, perp: Vector2) -> Vector2:
	var world := Vector2(cell.x, cell.y) - origin
	return Vector2(world.dot(perp), world.dot(dir))


static func _place(region: Region, offset: Vector2) -> void:
	region.rect.position.x += offset.x
	region.depth += offset.y
