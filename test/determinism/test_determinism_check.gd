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
		return (
			a.width == b.width
			and a.height == b.height
			and a.terrain == b.terrain
			and a.opacity == b.opacity
			and a.cover_value == b.cover_value
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
