extends GutTest

## Proves DeterminismCheck itself works, and exercises it against a real
## generator (MapGen) as the template every later generator (dartboard,
## ricochet, deep-strike assembly...) should follow.


func test_check_passes_for_a_naturally_deterministic_generator() -> void:
	var generator := func(seed: int) -> int:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		return rng.randi_range(0, 1000000)

	var result: Dictionary = DeterminismCheck.check(generator, [1, 2, 3, 42])
	assert_true(result.ok)
	assert_eq(result.failed_seeds, [] as Array[int])


func test_check_fails_when_generator_is_not_actually_seeded() -> void:
	var call_count := {"n": 0}
	var generator := func(_seed: int) -> int:
		call_count.n += 1
		return call_count.n  # ignores the seed entirely -> never matches itself

	var result: Dictionary = DeterminismCheck.check(generator, [1])
	assert_false(result.ok)
	assert_eq(result.failed_seeds, [1])


func test_check_supports_a_custom_compare_fn_for_reference_types() -> void:
	var generator := func(seed: int) -> Grid: return MapGen.generate(seed, 12, 10)
	var compare := func(a: Grid, b: Grid) -> bool:
		# taskblock-16 Pass B2: `blockers` holds real Part objects now (never
		# a plain `cover_value` scalar) — Dictionary `==` on Object values is
		# reference equality, always false between two independently
		# generated grids, so this compares each cell's own blocker id
		# instead (a Dictionary of value types, which DOES compare by
		# content).
		var a_blocker_ids: Dictionary = {}
		for cell: Vector2i in a.blockers:
			a_blocker_ids[cell] = (a.blockers[cell] as Part).id
		var b_blocker_ids: Dictionary = {}
		for cell: Vector2i in b.blockers:
			b_blocker_ids[cell] = (b.blockers[cell] as Part).id
		return (
			a.width == b.width
			and a.height == b.height
			and a.terrain == b.terrain
			and a.opacity == b.opacity
			and a_blocker_ids == b_blocker_ids
			and a.occupant_id == b.occupant_id
		)

	var result: Dictionary = DeterminismCheck.check(generator, [1, 2, 3], compare)
	assert_true(result.ok, "MapGen must be byte-identical across two calls with the same seed")


func test_check_reports_which_seeds_failed() -> void:
	var call_count := {"n": 0}
	var generator := func(seed: int) -> int:
		# Deliberately breaks determinism only for seed 2 (an incrementing
		# counter, guaranteed to differ between the two calls DeterminismCheck
		# makes), to prove failures are attributed to the right seed rather
		# than an all-or-nothing result.
		if seed == 2:
			call_count.n += 1
			return call_count.n
		return seed * 7

	var result: Dictionary = DeterminismCheck.check(generator, [1, 2, 3])
	assert_false(result.ok)
	assert_eq(result.failed_seeds, [2])
