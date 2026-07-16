class_name AimPlaneGeometry
extends RefCounted

## docs/10 taskblock03 F2 / runNotes.md: the dartboard's own plane in world
## space — a vertical plane through the target's cell, normal to the
## shooter->target line, spanned by that line's horizontal perpendicular
## (aim_point.x) and world-up (aim_point.y). Shared by AimView (aim_point ->
## world_point, for drawing the rings) and TacticsController (a camera ray
## -> aim_point, for "the reticle follows the cursor exactly" — runNotes.md:
## "Dartboard isn't following the cursor exactly instead being offset") so
## both sides of that round-trip agree on exactly the same plane.

const CELL_SIZE := UnitGeometry.CELL_SIZE


## The horizontal axis aim_point.x moves along — perpendicular to the
## shooter->target line, in the ground plane.
static func perp_axis(shooter_cell: Vector2i, target_cell: Vector2i) -> Vector2:
	var direction: Vector2 = Vector2(target_cell - shooter_cell).normalized()
	return Vector2(-direction.y, direction.x)


static func target_origin(target_cell: Vector2i) -> Vector3:
	return Vector3(target_cell.x, 0.0, target_cell.y) * CELL_SIZE


## aim_point (shot-plane 2D: x lateral, y vertical) -> its world position,
## nudged off the target's cell along perp_axis/world-up.
static func world_point(
	shooter_cell: Vector2i, target_cell: Vector2i, aim_point: Vector2
) -> Vector3:
	var perp: Vector2 = perp_axis(shooter_cell, target_cell)
	return (
		target_origin(target_cell)
		+ Vector3(perp.x, 0.0, perp.y) * aim_point.x
		+ Vector3(0.0, aim_point.y, 0.0)
	)


## The inverse: where a camera ray crosses that same plane, as an aim_point
## — or null if the ray runs parallel to it (no intersection) or the plane
## sits behind the ray's origin. `perp_axis`/world-up form an orthonormal
## basis for the plane, so the inverse is a straight dot-product projection
## once the 3D hit point is known — no matrix solve needed.
static func aim_point_from_ray(
	shooter_cell: Vector2i, target_cell: Vector2i, ray_origin: Vector3, ray_dir: Vector3
) -> Variant:
	var perp: Vector2 = perp_axis(shooter_cell, target_cell)
	var normal := Vector3(perp.y, 0.0, -perp.x)  # perp rotated -90 deg: shooter->target direction
	var denom: float = ray_dir.dot(normal)
	if absf(denom) < 0.0001:
		return null
	var origin: Vector3 = target_origin(target_cell)
	var t: float = (origin - ray_origin).dot(normal) / denom
	if t < 0.0:
		return null
	var hit: Vector3 = ray_origin + ray_dir * t
	var relative: Vector3 = hit - origin
	return Vector2(relative.x * perp.x + relative.z * perp.y, relative.y)
