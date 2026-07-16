class_name BoardPicker
extends RefCounted

## Pure ground-plane math (docs/10): given a ray in world space, the grid
## cell it points at, or null if the ray never crosses the board's y == 0
## plane (looking above the horizon, or parallel to it). The Node supplies
## the ray — `Camera3D.project_ray_origin`/`project_ray_normal` need a live
## viewport to mean anything — everything after that is plain,
## headless-testable arithmetic, no SceneTree required.


static func cell_at_ray(from: Vector3, dir: Vector3) -> Variant:
	var t: Variant = plane_hit_t(from, dir)
	if t == null:
		return null
	var world: Vector3 = from + dir * (t as float)
	return Vector2i(
		roundi(world.x / UnitGeometry.CELL_SIZE), roundi(world.z / UnitGeometry.CELL_SIZE)
	)


## docs/10 taskblock03 D1: the ray parameter `t` where a ray crosses the
## board's y == 0 plane, or null if it never does — split out from
## cell_at_ray so a caller (TacticsController) can compare this distance
## against UnitPicker's own hit distance to decide "nearest hit wins"
## between clicking a tile and clicking a unit's body.
static func plane_hit_t(from: Vector3, dir: Vector3) -> Variant:
	if is_zero_approx(dir.y):
		return null
	var t: float = -from.y / dir.y
	if t < 0.0:
		return null
	return t
