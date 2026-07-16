class_name BoardPicker
extends RefCounted

## Pure ground-plane math (docs/10): given a ray in world space, the grid
## cell it points at, or null if the ray never crosses the board's y == 0
## plane (looking above the horizon, or parallel to it). The Node supplies
## the ray — `Camera3D.project_ray_origin`/`project_ray_normal` need a live
## viewport to mean anything — everything after that is plain,
## headless-testable arithmetic, no SceneTree required.


static func cell_at_ray(from: Vector3, dir: Vector3) -> Variant:
	if is_zero_approx(dir.y):
		return null
	var t: float = -from.y / dir.y
	if t < 0.0:
		return null
	var world: Vector3 = from + dir * t
	return Vector2i(
		roundi(world.x / UnitGeometry.CELL_SIZE), roundi(world.z / UnitGeometry.CELL_SIZE)
	)
