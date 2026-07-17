extends GutTest

## docs/09 taskblock06 Pass A: resolve_ray is a seam over the existing
## rect-lookup math, not a new resolution mechanism — "same boxes, same
## regions, same results." These tests prove the no-drift invariant: a
## world ray's hit part always equals the frontmost region the equivalent
## plane-space point would resolve to.


func _part(id: StringName, box: Box) -> Part:
	var part := Part.new()
	part.id = id
	part.hp = 5
	part.max_hp = 5
	part.volume = [box]
	return part


func _standing_unit(id: StringName, half_width: float, cell: Vector2i) -> Unit:
	var body := _part(id, Box.new(Vector3(0.0, 0.5, 0.0), Vector3(half_width * 2.0, 1.0, 0.6)))
	return Unit.new(Matrix.new(), Shell.new(body), cell)


## Converts the same (origin: Vector2, direction: Vector2, point: Vector2)
## triple test_shot_plane.gd's fixtures already use into the equivalent 3D
## ray: a level shot whose ORIGIN already carries the lateral/vertical
## offset `point` used to encode as a separate argument.
func _ray_for(origin: Vector2, direction: Vector2, point: Vector2) -> Dictionary:
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var flat: Vector2 = origin + perp * point.x
	var ray_origin := Vector3(flat.x, point.y, flat.y) * UnitGeometry.CELL_SIZE
	var ray_dir := Vector3(dir.x, 0.0, dir.y)
	return {"origin": ray_origin, "dir": ray_dir}


func test_resolve_ray_matches_resolve_projectile_for_a_corpus_of_existing_cases() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)

	var cases: Array[Vector2] = [Vector2(0.8, 0.5), Vector2(0.2, 0.5), Vector2(5.0, 0.5)]
	for point: Vector2 in cases:
		var expected: Region = ShotPlane.resolve_projectile(plane, point)
		var ray: Dictionary = _ray_for(origin, direction, point)
		var hit: HitResult = ShotPlane.resolve_ray(ray.origin, ray.dir, state)
		if expected == null:
			assert_null(hit, "point %s: resolve_projectile found nothing" % point)
		else:
			assert_not_null(
				hit, "point %s: resolve_projectile found %s" % [point, expected.part.id]
			)
			assert_eq(hit.part, expected.part)
			assert_eq(hit.body, expected.body)


## The invariant itself, stated directly rather than via a shared fixture:
## for any ray, the part it hits is exactly the part the frontmost region
## containing the corresponding plane point would be.
func test_the_rays_hit_part_always_equals_the_frontmost_region_at_the_corresponding_point() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 2)] = crate

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var point := Vector2(0.0, 0.5)
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)
	var expected: Region = ShotPlane.resolve_projectile(plane, point)

	var ray: Dictionary = _ray_for(origin, direction, point)
	var hit: HitResult = ShotPlane.resolve_ray(ray.origin, ray.dir, state)

	assert_not_null(hit)
	assert_eq(hit.part, expected.part)
	assert_eq(hit.normal, expected.surface_normal)
	assert_eq(hit.distance, expected.depth)


func test_resolve_ray_returns_null_when_nothing_is_hit() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var ray: Dictionary = _ray_for(origin, direction, Vector2(5.0, 0.5))

	assert_null(ShotPlane.resolve_ray(ray.origin, ray.dir, state))


func test_resolve_ray_is_deterministic() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var ray: Dictionary = _ray_for(origin, direction, Vector2(0.2, 0.5))

	var first: HitResult = ShotPlane.resolve_ray(ray.origin, ray.dir, state)
	var second: HitResult = ShotPlane.resolve_ray(ray.origin, ray.dir, state)

	assert_eq(first.part, second.part)
	assert_eq(first.point, second.point)
	assert_eq(first.distance, second.distance)


## docs/02: the world hit point the ray reports must be a real point along
## origin + dir * distance — the seam must reconstruct a usable 3D position,
## not just an identity.
func test_resolve_ray_reports_a_hit_point_that_lies_on_the_ray() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)
	var ray: Dictionary = _ray_for(origin, direction, Vector2(0.2, 0.5))

	var hit: HitResult = ShotPlane.resolve_ray(ray.origin, ray.dir, state)

	assert_not_null(hit)
	var expected_point: Vector3 = (ray.origin as Vector3) + (ray.dir as Vector3) * hit.distance
	assert_true(hit.point.is_equal_approx(expected_point))
