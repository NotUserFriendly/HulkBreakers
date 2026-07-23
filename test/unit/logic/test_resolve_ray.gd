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
	var plane: Array[Region] = ShotPlane.build(
		Vector3(flat_origin.x, 0.0, flat_origin.y), Vector3(flat_dir.x, 0.0, flat_dir.y), world
	)
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


## taskblock-23 Pass C: "resolve_ray accepts vertical shots" — the old
## docs/09 taskblock07 Pass A3 `dir.y ~= 0` guard (docs/02's pre-multi-
## level "shots travel horizontally") is gone. A non-horizontal `dir` must
## resolve like any other ray, never push_error, even one that lands on
## nothing.
func test_a_non_zero_dir_y_no_longer_errors() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)

	var hit: Variant = ShotPlane.resolve_ray(Vector3(2.0, 0.5, 0.0), Vector3(0.0, 0.5, 1.0), state)

	assert_null(hit, "nothing stands in this empty grid's path")
	assert_push_error_count(0, "a real vertical dir must never push_error anymore")


## "a shot passes over a part shorter than the muzzle line and hits a
## taller one behind it" — an ordinary LEVEL ray (Pass A/B already gave
## every region its own real vertical extent; this proves resolve_ray
## actually honors it end to end, not just the plane-build primitives it
## wraps).
func test_a_level_shot_passes_over_a_short_part_and_hits_a_taller_one_behind_it() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var short_crate := _part(&"short", Box.new(Vector3(0.0, 0.25, 0.0), Vector3(2.0, 0.5, 0.6)))
	var tall_wall := _part(&"tall", Box.new(Vector3(0.0, 1.5, 0.0), Vector3(2.0, 2.0, 0.6)))
	grid.blockers[Vector2i(2, 2)] = short_crate
	grid.blockers[Vector2i(2, 6)] = tall_wall

	# Above the short crate's own rect ([0.0, 0.5]) but within the tall
	# wall's ([0.5, 2.5]).
	var muzzle := Vector3(2.0, 1.5, 0.0)
	var dir := Vector3(0.0, 0.0, 1.0)

	var hit: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)

	assert_not_null(hit)
	assert_eq(
		hit.part,
		tall_wall,
		"the muzzle's real height clears the short crate and reaches the tall wall behind it"
	)


## A genuinely tilted ray must reach a region a level ray from the exact
## same muzzle cannot — proof the vertical component actually participates
## in region selection now, not just carried along unused.
func test_a_tilted_ray_hits_a_part_a_level_ray_from_the_same_muzzle_would_miss() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var torso := _part(&"torso", Box.new(Vector3(0.0, 1.5, 0.0), Vector3(0.6, 1.0, 0.6)))
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 5))
	state.add_unit(unit)

	var muzzle := Vector3(2.0, 0.5, 0.0)
	assert_null(
		ShotPlane.resolve_ray(muzzle, Vector3(0.0, 0.0, 1.0), state),
		"sanity: a level ray at this muzzle height misses the torso entirely"
	)

	var hit: HitResult = ShotPlane.resolve_ray(muzzle, Vector3(0.0, 0.25, 1.0), state)

	assert_not_null(hit, "climbing along a real vertical dir must reach what a level ray missed")
	assert_eq(hit.part, torso)


## The world hit point a tilted ray reports must still lie on the real 3D
## ray — the same property `test_resolve_ray_reports_a_hit_point_that_lies_
## on_the_ray` proves for a level one, now proven for a climbing one too.
func test_a_tilted_rays_hit_point_lies_on_the_real_3d_ray() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var torso := _part(&"torso", Box.new(Vector3(0.0, 1.5, 0.0), Vector3(0.6, 1.0, 0.6)))
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 5))
	state.add_unit(unit)

	var muzzle := Vector3(2.0, 0.5, 0.0)
	var dir := Vector3(0.0, 0.25, 1.0)

	var hit: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)

	assert_not_null(hit)
	var expected_point: Vector3 = muzzle + dir.normalized() * hit.distance
	assert_true(hit.point.is_equal_approx(expected_point))


## "Muzzle height is real... not a hardcoded constant" — two boxes on the
## SAME part at different real heights, same everything else: only the
## caller's own real muzzle height decides which one (if either) gets hit.
func test_muzzle_height_is_real_not_a_hardcoded_constant() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var stacked := Part.new()
	stacked.id = &"stacked"
	stacked.hp = 5
	stacked.max_hp = 5
	stacked.volume = [
		Box.new(Vector3(0.0, 0.25, 0.0), Vector3(0.6, 0.5, 0.6)),  # spans y [0.0, 0.5]
		Box.new(Vector3(0.0, 1.75, 0.0), Vector3(0.6, 0.5, 0.6)),  # spans y [1.5, 2.0]
	]
	var unit := Unit.new(Matrix.new(), Shell.new(stacked), Vector2i(2, 5))
	state.add_unit(unit)
	var dir := Vector3(0.0, 0.0, 1.0)

	var low_hit: HitResult = ShotPlane.resolve_ray(Vector3(2.0, 0.25, 0.0), dir, state)
	var high_hit: HitResult = ShotPlane.resolve_ray(Vector3(2.0, 1.75, 0.0), dir, state)
	var between_miss: Variant = ShotPlane.resolve_ray(Vector3(2.0, 1.0, 0.0), dir, state)

	assert_not_null(low_hit, "the muzzle's own real low height must land on the low box")
	assert_not_null(high_hit, "the muzzle's own real high height must land on the high box")
	assert_null(between_miss, "a real muzzle height between the two boxes must hit neither")
	assert_almost_eq(low_hit.point.y, 0.25, 0.01)
	assert_almost_eq(high_hit.point.y, 1.75, 0.01)


func test_a_zero_horizontal_direction_returns_null_without_erroring() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)

	# The whole vector is zero — no horizontal heading to build a plane
	# along at all, whatever dir.y is.
	assert_null(ShotPlane.resolve_ray(Vector3(2.0, 0.5, 0.0), Vector3.ZERO, state))
