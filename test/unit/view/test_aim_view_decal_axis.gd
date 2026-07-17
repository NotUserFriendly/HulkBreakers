extends GutTest

## docs/09 taskblock07 Pass D/TESTS: "the dot's decal axis equals the
## ray's direction" — Godot's Decal always projects along its own local
## -Y, so this proves AimView._decal_basis(dir) always yields a basis
## whose local -Y IS `dir`, for any direction, not just the axis-aligned
## cases that happen to look right by coincidence (the same discipline
## taskblock07 Pass B1's own mirror bug was found by).


func test_the_decal_basis_projects_along_the_exact_direction_given() -> void:
	var directions: Array[Vector3] = [
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.6, 0.0, 0.8),
		Vector3(-0.3, 0.0, -0.95393920141694566).normalized(),
	]
	for dir: Vector3 in directions:
		var basis: Basis = AimView._decal_basis(dir)
		var projection_dir: Vector3 = -basis.y
		assert_true(
			projection_dir.is_equal_approx(dir),
			(
				"dir %s: decal must project along exactly this direction, got %s"
				% [dir, projection_dir]
			)
		)


## The literal taskblock wording: the decal's own axis must equal the same
## `dir` AimPlaneGeometry.ray_from_muzzle() (the bridge
## AimController._resolve_hit() itself uses for ShotPlane.resolve_ray)
## produces for a real, laterally-offset aim point — not just the
## dead-ahead shooter->target line.
func test_the_decal_axis_equals_ray_from_muzzles_own_direction_for_an_offset_reticle() -> void:
	var shooter_cell := Vector2i(1, 2)
	var target_cell := Vector2i(8, 6)
	var aim_point := Vector2(1.5, 0.3)  # laterally offset — not dead-ahead
	var muzzle := Vector3(1.2, 0.5, 2.1)

	var ray: Dictionary = AimPlaneGeometry.ray_from_muzzle(
		shooter_cell, target_cell, aim_point, muzzle
	)
	assert_false(ray.is_empty())
	var dir: Vector3 = ray["dir"]

	var basis: Basis = AimView._decal_basis(dir)
	var projection_dir: Vector3 = -basis.y

	assert_true(projection_dir.is_equal_approx(dir))
	# Sanity: an offset reticle really does deviate from dead-ahead — this
	# test would be vacuous otherwise.
	var dead_ahead: Vector2 = Vector2(target_cell - shooter_cell).normalized()
	assert_false(Vector2(dir.x, dir.z).is_equal_approx(dead_ahead))


func test_the_decal_basis_is_orthonormal() -> void:
	var dir := Vector3(0.6, 0.0, 0.8).normalized()
	var basis: Basis = AimView._decal_basis(dir)

	assert_almost_eq(basis.x.length(), 1.0, 0.0001)
	assert_almost_eq(basis.y.length(), 1.0, 0.0001)
	assert_almost_eq(basis.z.length(), 1.0, 0.0001)
	assert_almost_eq(basis.x.dot(basis.y), 0.0, 0.0001)
	assert_almost_eq(basis.y.dot(basis.z), 0.0, 0.0001)
	assert_almost_eq(basis.x.dot(basis.z), 0.0, 0.0001)
