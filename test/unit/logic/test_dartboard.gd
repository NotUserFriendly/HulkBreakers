extends GutTest

## docs/02: aiming picks a point, never a body part. Ring count is never
## assumed; weights govern which ring a projectile picks; scatter radii are
## resolved through StatResolver (docs/08) so a modifier like "Spin Up"
## shows up in provenance instead of a raw arithmetic tweak.


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func test_same_seed_produces_identical_impact_points() -> void:
	var scatter: Array[Ring] = [Ring.new(0.2, 1.0), Ring.new(1.0, 3.0)]
	var a: Array[Vector2] = Dartboard.sample(Vector2(5, 5), scatter, _rng(42), 50)
	var b: Array[Vector2] = Dartboard.sample(Vector2(5, 5), scatter, _rng(42), 50)
	assert_eq(a, b)


func test_works_with_one_two_three_or_five_rings() -> void:
	for ring_count: int in [1, 2, 3, 5]:
		var scatter: Array[Ring] = []
		for i in range(ring_count):
			scatter.append(Ring.new(float(i + 1), 1.0))
		var outer_radius: float = scatter[ring_count - 1].radius

		var points: Array[Vector2] = Dartboard.sample(Vector2.ZERO, scatter, _rng(1), 100)
		assert_eq(points.size(), 100, "ring count %d: must sample the requested count" % ring_count)
		for point: Vector2 in points:
			assert_true(
				point.length() <= outer_radius + 0.0001,
				"ring count %d: every sample must land within the outermost ring" % ring_count
			)


func test_ring_weights_hold_over_many_samples() -> void:
	# Ring 0 gets 1 part in 4 of the weight, ring 1 the other 3 — a
	# projectile's ring choice is a weight draw, independent of ring area.
	var scatter: Array[Ring] = [Ring.new(0.2, 1.0), Ring.new(1.0, 3.0)]
	var rng := _rng(7)
	const SAMPLES := 4000
	var inner_hits := 0
	for point: Vector2 in Dartboard.sample(Vector2.ZERO, scatter, rng, SAMPLES):
		if point.length() <= scatter[0].radius + 0.0001:
			inner_hits += 1
	var fraction: float = float(inner_hits) / SAMPLES
	assert_almost_eq(fraction, 0.25, 0.03)


func _weapon(id: StringName, scatter: Array[Ring]) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.scatter = scatter
	return weapon


func test_tight_inner_ring_sniper_hits_a_small_region_a_chaingun_cannot() -> void:
	var sniper := _weapon(&"sniper", [Ring.new(0.05, 9.0), Ring.new(1.0, 1.0)])
	var chaingun := _weapon(&"chaingun", [Ring.new(2.0, 1.0)])
	var eyehole := Rect2(-0.1, -0.1, 0.2, 0.2)
	const SAMPLES := 500

	var sniper_hits := 0
	for point: Vector2 in Dartboard.sample(Vector2.ZERO, sniper.scatter, _rng(3), SAMPLES):
		if eyehole.has_point(point):
			sniper_hits += 1

	var chaingun_hits := 0
	for point: Vector2 in Dartboard.sample(Vector2.ZERO, chaingun.scatter, _rng(3), SAMPLES):
		if eyehole.has_point(point):
			chaingun_hits += 1

	assert_true(
		float(sniper_hits) / SAMPLES > 0.5, "the sniper should land in the eyehole most of the time"
	)
	assert_true(
		float(chaingun_hits) / SAMPLES < 0.05,
		"the chaingun's huge radii should almost never land in the eyehole"
	)
	assert_true(sniper_hits > chaingun_hits)


func test_spin_up_shrinks_a_ring_through_the_resolver_and_names_itself_in_sources() -> void:
	var weapon := _weapon(&"chaingun", [Ring.new(1.0, 1.0)])
	var spin_up := ModSource.new("Spin Up", Enums.ModSourceKind.STANCE, Enums.ModOp.MULTIPLY, 0.5)

	var context := ResolverContext.new()
	context.base = weapon.scatter[0].radius
	context.parts = [weapon]
	context.extra_sources = [spin_up]
	var resolved: StatValue = StatResolver.resolve(&"scatter_radius_0", context)

	assert_eq(resolved.current, 0.5)
	assert_eq(resolved.sources.size(), 1)
	assert_eq(resolved.sources[0].source_name, "Spin Up")

	var resolved_scatter: Array[Ring] = Dartboard.resolve_scatter(weapon, [spin_up])
	assert_eq(resolved_scatter[0].radius, 0.5)
