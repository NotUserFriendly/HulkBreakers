class_name BodyProjector
extends RefCounted

## Body-space projection (docs/02). No facings, no snap: a part's local Box
## volumes are rotated by the continuous angle between the unit's orientation
## and the line of fire, then flattened onto the view plane. `view_dir` is
## always "direction of travel" — the same direction a shot moving from the
## shooter into the world would take — so depth increases the farther a
## point sits from the shooter, and per-unit Regions compose directly with
## ShotPlane's inter-unit depth offsets by simple addition.

## World-space ground direction a unit with orientation == 0.0 faces.
const WORLD_FORWARD := Vector2(0.0, 1.0)


## Projects every living part of `unit`'s frame into view-plane Regions.
static func project(unit: Unit, view_dir: Vector2) -> Array[Region]:
	var regions: Array[Region] = []
	for part: Part in unit.frame.living_parts():
		regions.append_array(project_part(part, view_dir, unit.orientation))
	return regions


## Projects a single part's own boxes, rotated by `orientation` (a unit's
## facing, or 0.0 for a static, world-aligned cover/obstacle part) relative
## to `view_dir`. Shared by `project()` and ShotPlane's cover placement so
## both go through identical math.
static func project_part(part: Part, view_dir: Vector2, orientation: float = 0.0) -> Array[Region]:
	if part.hp <= 0:
		return []
	var dir: Vector2 = view_dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var regions: Array[Region] = []
	for box: Box in part.volume:
		regions.append(_project_box(box, dir, perp, orientation, part))
	return regions


static func _project_box(
	box: Box, dir: Vector2, perp: Vector2, orientation: float, part: Part
) -> Region:
	var half := box.size * 0.5
	var xs: Array[float] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var local := Vector2(box.center.x + sx * half.x, box.center.z + sz * half.z)
			var world: Vector2 = local.rotated(orientation)
			xs.append(world.dot(perp))
	var center_world: Vector2 = Vector2(box.center.x, box.center.z).rotated(orientation)
	var depth: float = center_world.dot(dir)
	var min_x: float = xs.min()
	var max_x: float = xs.max()
	var rect := Rect2(min_x, box.center.y - half.y, max_x - min_x, box.size.y)
	var normal := Vector3(-dir.x, 0.0, -dir.y)
	return Region.new(rect, depth, part, normal)
