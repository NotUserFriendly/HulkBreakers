class_name ShotPlane
extends RefCounted

## The line-of-fire projection (docs/02): every unit and every piece of
## destructible cover along one direction, flattened into a single
## depth-sorted Array[Region]. `resolve_projectile` is the entire
## hit-resolution system — it does not know about units, cover, or gaps,
## only rects.


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
			regions.append(region)

	for cell: Vector2i in state.grid.blockers:
		var part: Part = state.grid.blockers[cell]
		var offset := _offset(cell, origin, dir, perp)
		for region: Region in BodyProjector.project_part(part, dir):
			_place(region, offset)
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


## Every unit with at least one Region in `plane`, nearest-first by its
## closest region's depth (docs/08): a UI must be able to show stats for a
## partially obscured target deeper in the plane, not only the one
## resolve_projectile would actually hit at a given point.
static func units_along(plane: Array[Region], state: CombatState) -> Array[Unit]:
	var best_depth: Dictionary = {}  # Unit -> float
	for unit: Unit in state.units:
		var unit_parts: Array[Part] = unit.frame.all_parts()
		for region: Region in plane:
			if unit_parts.has(region.part):
				if not best_depth.has(unit) or region.depth < best_depth[unit]:
					best_depth[unit] = region.depth

	var units: Array[Unit] = []
	for unit: Variant in best_depth.keys():
		units.append(unit)
	units.sort_custom(func(a: Unit, b: Unit) -> bool: return best_depth[a] < best_depth[b])
	return units


static func _offset(cell: Vector2i, origin: Vector2, dir: Vector2, perp: Vector2) -> Vector2:
	var world := Vector2(cell.x, cell.y) - origin
	return Vector2(world.dot(perp), world.dot(dir))


static func _place(region: Region, offset: Vector2) -> void:
	region.rect.position.x += offset.x
	region.depth += offset.y
