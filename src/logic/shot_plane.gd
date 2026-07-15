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


static func _offset(cell: Vector2i, origin: Vector2, dir: Vector2, perp: Vector2) -> Vector2:
	var world := Vector2(cell.x, cell.y) - origin
	return Vector2(world.dot(perp), world.dot(dir))


static func _place(region: Region, offset: Vector2) -> void:
	region.rect.position.x += offset.x
	region.depth += offset.y
