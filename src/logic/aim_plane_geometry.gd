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
## nudged off the target's cell along perp_axis/world-up. Exactly
## world_point_at_depth() at depth = the shooter-target distance (proven by
## test — the two must never drift apart).
static func world_point(
	shooter_cell: Vector2i, target_cell: Vector2i, aim_point: Vector2
) -> Vector3:
	return world_point_at_depth(
		shooter_cell, target_cell, aim_point, Vector2(target_cell - shooter_cell).length()
	)


## docs/09 taskblock06 Pass H: "scrolling the READ layer moves the window
## backward through the scene" — the aim window's own depth has to be able
## to float to wherever the currently-read layer's frontmost surface sits,
## not just sit fixed at the target's own cell. Same plane, same aim_point
## axes, but anchored `depth` cells along the shooter->target line from the
## SHOOTER's own cell (ShotPlane's own depth convention: distance along the
## fire direction from the ray's origin) rather than fixed at the target's.
static func world_point_at_depth(
	shooter_cell: Vector2i, target_cell: Vector2i, aim_point: Vector2, depth: float
) -> Vector3:
	var direction: Vector2 = Vector2(target_cell - shooter_cell).normalized()
	var perp: Vector2 = perp_axis(shooter_cell, target_cell)
	var shooter_origin := Vector3(shooter_cell.x, 0.0, shooter_cell.y) * CELL_SIZE
	return (
		shooter_origin
		+ Vector3(direction.x, 0.0, direction.y) * depth
		+ Vector3(perp.x, 0.0, perp.y) * aim_point.x
		+ Vector3(0.0, aim_point.y, 0.0)
	)


## docs/09 taskblock07 Pass A: builds a `ShotPlane.resolve_ray`-ready
## `{origin, dir}` pair from a real weapon muzzle and a plane-space aim
## point. "Shots travel horizontally" (docs/02) means a level ray can only
## ever hit points at its OWN height — so vertical aim (aim_point.y) is
## expressed by which height the ray travels AT (the returned origin is
## `muzzle` raised/lowered to the aim point's own height), never by tilting
## `dir` (`dir.y` is 0 by construction, satisfying `resolve_ray`'s own
## precondition, not by discarding anything). Lateral aim (aim_point.x)
## lives entirely in `dir`'s own horizontal direction, exactly the taskblock
## text: "the aim offset lives entirely in dir." Returns `{}` if `muzzle`
## sits exactly above/below the aim world point (no horizontal direction to
## fire along).
static func ray_from_muzzle(
	shooter_cell: Vector2i, target_cell: Vector2i, aim_point: Vector2, muzzle: Vector3
) -> Dictionary:
	var aim_world: Vector3 = world_point(shooter_cell, target_cell, aim_point)
	var flat := Vector2(aim_world.x - muzzle.x, aim_world.z - muzzle.z)
	if flat.is_zero_approx():
		return {}
	var flat_dir: Vector2 = flat.normalized()
	return {
		"origin": Vector3(muzzle.x, aim_world.y, muzzle.z),
		"dir": Vector3(flat_dir.x, 0.0, flat_dir.y),
	}


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
