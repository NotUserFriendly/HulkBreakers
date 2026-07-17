extends GutTest

## runNotes.md: "Dartboard isn't following the cursor exactly instead being
## offset" — world_point/aim_point_from_ray must be exact inverses of each
## other, or the reticle drawn from one and the cursor read from the other
## would visibly disagree.


func test_world_point_at_zero_offset_is_the_targets_own_cell() -> void:
	var point: Vector3 = AimPlaneGeometry.world_point(Vector2i(0, 0), Vector2i(5, 0), Vector2.ZERO)
	assert_almost_eq(point.x, 5.0, 0.0001)
	assert_almost_eq(point.y, 0.0, 0.0001)
	assert_almost_eq(point.z, 0.0, 0.0001)


func test_world_point_lateral_offset_follows_the_perpendicular_axis() -> void:
	# Shooter due south of the target (shooting +X): perp is +Z, so a
	# positive lateral aim_point.x must move the world point toward +Z.
	var point: Vector3 = AimPlaneGeometry.world_point(
		Vector2i(0, 0), Vector2i(5, 0), Vector2(2.0, 0.0)
	)
	assert_almost_eq(point.x, 5.0, 0.0001, "no lateral drift onto the shooter->target axis itself")
	assert_almost_eq(point.z, 2.0, 0.0001)


func test_world_point_vertical_offset_is_plain_world_up() -> void:
	var point: Vector3 = AimPlaneGeometry.world_point(
		Vector2i(0, 0), Vector2i(5, 0), Vector2(0.0, 1.5)
	)
	assert_almost_eq(point.y, 1.5, 0.0001)


## The actual contract: a ray aimed straight at a known world_point must
## recover the exact aim_point that produced it — this is what makes the
## reticle track the literal cursor position, not an accumulated delta.
func test_aim_point_from_ray_round_trips_through_world_point() -> void:
	var shooter := Vector2i(1, 4)
	var target := Vector2i(6, 9)  # diagonal, not sharing a row or column
	var aim_point := Vector2(0.35, 0.8)
	var world: Vector3 = AimPlaneGeometry.world_point(shooter, target, aim_point)

	# A ray from far off the plane, aimed exactly at `world` — stands in for
	# a camera ray a real cursor projection would produce.
	var ray_origin := world + Vector3(-3.0, 2.0, -4.0)
	var ray_dir: Vector3 = (world - ray_origin).normalized()

	var recovered: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter, target, ray_origin, ray_dir
	)

	assert_not_null(recovered)
	assert_almost_eq((recovered as Vector2).x, aim_point.x, 0.001)
	assert_almost_eq((recovered as Vector2).y, aim_point.y, 0.001)


func test_aim_point_from_ray_returns_null_when_parallel_to_the_plane() -> void:
	var shooter := Vector2i(0, 0)
	var target := Vector2i(5, 0)
	# The plane's normal is +X (shooter->target); a ray travelling along Z
	# never crosses it.
	var recovered: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter, target, Vector3(5.0, 1.0, -10.0), Vector3(0.0, 0.0, 1.0)
	)
	assert_null(recovered)


## docs/09 taskblock06 Pass H: world_point() must be exactly
## world_point_at_depth() at depth = the shooter-target distance — the
## no-drift invariant a scrolling window relies on.
func test_world_point_at_depth_matches_world_point_at_the_target_distance() -> void:
	var shooter := Vector2i(1, 4)
	var target := Vector2i(6, 9)
	var aim_point := Vector2(0.35, 0.8)
	var distance: float = Vector2(target - shooter).length()

	var at_depth: Vector3 = AimPlaneGeometry.world_point_at_depth(
		shooter, target, aim_point, distance
	)
	var at_target: Vector3 = AimPlaneGeometry.world_point(shooter, target, aim_point)

	assert_almost_eq(at_depth.x, at_target.x, 0.0001)
	assert_almost_eq(at_depth.y, at_target.y, 0.0001)
	assert_almost_eq(at_depth.z, at_target.z, 0.0001)


## docs/09 taskblock06 Pass H: "scrolling moves the window backward through
## the scene" — a shallower depth must sit closer to the shooter's own
## cell, not the target's.
func test_world_point_at_depth_zero_sits_at_the_shooters_own_cell() -> void:
	var point: Vector3 = AimPlaneGeometry.world_point_at_depth(
		Vector2i(2, 0), Vector2i(7, 0), Vector2.ZERO, 0.0
	)
	assert_almost_eq(point.x, 2.0, 0.0001)
	assert_almost_eq(point.z, 0.0, 0.0001)


func test_aim_point_from_ray_returns_null_when_the_plane_is_behind_the_ray() -> void:
	var shooter := Vector2i(0, 0)
	var target := Vector2i(5, 0)
	# Standing past the target, aimed further away from the shooter — the
	# plane at x=5 is behind this ray's own origin.
	var recovered: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter, target, Vector3(10.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0)
	)
	assert_null(recovered)
