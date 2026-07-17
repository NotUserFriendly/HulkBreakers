extends GutTest

## docs/09 taskblock06 Pass A / taskblock07 Pass A2: resolve_ray(muzzle, dir,
## world) is a seam over the existing plane-build + rect-lookup math, not a
## new resolution mechanism — same boxes, same regions, same results, just
## anchored at the ray's own real origin and direction instead of a fixed
## "dead ahead from the shooter's cell" plane with the offset baked into the
## query point. These tests prove the no-drift invariant against THAT
## relationship: `resolve_ray(muzzle, dir, world)` always agrees with
## building a plane at muzzle's own flat (x,z) using `dir`'s own flattened
## direction, then resolving at `(0, muzzle.y)` — the exact math
## `resolve_ray` runs internally.


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


## The frontmost Region `resolve_ray(muzzle, dir, world)` is built to agree
## with — the exact internal math (flat origin/direction from `muzzle`/
## `dir`, queried at `(0, muzzle.y)`), computed independently here so the
## test can't just be checking the implementation against itself.
func _expected_region(muzzle: Vector3, dir: Vector3, world: CombatState) -> Region:
	var flat_origin := Vector2(muzzle.x, muzzle.z)
	var flat_dir: Vector2 = Vector2(dir.x, dir.z).normalized()
	var plane: Array[Region] = ShotPlane.build(flat_origin, flat_dir, world)
	return ShotPlane.resolve_projectile(plane, Vector2(0.0, muzzle.y))


func test_resolve_ray_matches_the_plane_it_builds_internally_for_a_corpus_of_cases() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	var far_unit := _standing_unit(&"far", 1.0, Vector2i(2, 6))
	state.add_unit(near_unit)
	state.add_unit(far_unit)

	var cases: Array[Vector3] = [
		Vector3(2.0, 0.5, 0.0),  # dead-on, from behind the near unit's own cell
		Vector3(2.8, 0.5, 0.0),  # laterally offset muzzle, still dead-ahead +Z
		Vector3(-1.0, 0.5, -3.0),  # off the axis entirely, angled toward the units
	]
	var dir := Vector3(0.0, 0.0, 1.0)
	for muzzle: Vector3 in cases:
		var expected: Region = _expected_region(muzzle, dir, state)
		var hit: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)
		if expected == null:
			assert_null(hit, "muzzle %s: nothing expected" % muzzle)
		else:
			assert_not_null(hit, "muzzle %s: expected %s" % [muzzle, expected.part.id])
			assert_eq(hit.part, expected.part)
			assert_eq(hit.body, expected.body)


func test_the_rays_hit_part_always_equals_the_frontmost_region_at_the_corresponding_point() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var crate := _part(&"crate", Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6)))
	grid.blockers[Vector2i(2, 2)] = crate

	var muzzle := Vector3(2.0, 0.5, 0.0)
	var dir := Vector3(0.0, 0.0, 1.0)
	var expected: Region = _expected_region(muzzle, dir, state)

	var hit: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)

	assert_not_null(hit)
	assert_eq(hit.part, expected.part)
	assert_eq(hit.normal, expected.surface_normal)
	assert_eq(hit.distance, expected.depth)


func test_resolve_ray_returns_null_when_nothing_is_hit() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)

	# Far off the unit's own lateral span (half_width 0.5 -> spans [-0.5, 0.5]).
	var muzzle := Vector3(7.0, 0.5, 0.0)
	var dir := Vector3(0.0, 0.0, 1.0)

	assert_null(ShotPlane.resolve_ray(muzzle, dir, state))


func test_resolve_ray_is_deterministic() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)

	var muzzle := Vector3(2.2, 0.5, 0.0)
	var dir := Vector3(0.0, 0.0, 1.0)

	var first: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)
	var second: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)

	assert_not_null(first)
	assert_eq(first.part, second.part)
	assert_eq(first.point, second.point)
	assert_eq(first.distance, second.distance)


## docs/02: the world hit point the ray reports must be a real point along
## muzzle + dir * distance — the seam must reconstruct a usable 3D position,
## not just an identity.
func test_resolve_ray_reports_a_hit_point_that_lies_on_the_ray() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var near_unit := _standing_unit(&"near", 0.5, Vector2i(2, 2))
	state.add_unit(near_unit)

	var muzzle := Vector3(2.2, 0.5, 0.0)
	var dir := Vector3(0.0, 0.0, 1.0)

	var hit: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)

	assert_not_null(hit)
	var expected_point: Vector3 = muzzle + dir * hit.distance
	assert_true(hit.point.is_equal_approx(expected_point))


## docs/09 taskblock07 Pass A3: "assert is_zero_approx(dir.y)... a silent
## drop is a trap." A non-horizontal dir must fail loudly, not silently
## flatten and carry on.
func test_a_non_zero_dir_y_fails_loudly() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)

	var hit: Variant = ShotPlane.resolve_ray(Vector3(2.0, 0.5, 0.0), Vector3(0.0, 0.5, 1.0), state)

	assert_null(hit)
	assert_push_error("dir.y")


func test_a_zero_horizontal_direction_returns_null_without_erroring() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)

	# dir.y == 0 (satisfies the precondition) but the whole vector is zero —
	# no horizontal direction to fire along at all.
	assert_null(ShotPlane.resolve_ray(Vector3(2.0, 0.5, 0.0), Vector3.ZERO, state))
