extends GutTest

## docs/04: one class serves both the base (persistent crew member) and the
## link (the physical vessel deployed in the field) — `base == null` means
## this instance IS a base.


func test_unlinked_matrix_defers_to_its_own_fields() -> void:
	var matrix := Matrix.new()
	matrix.level = 5
	matrix.perks = [&"steady_hands", &"quick_draw"]

	assert_almost_eq(matrix.effective_level(), 5.0, 0.0001)
	assert_eq(matrix.active_perks(), [&"steady_hands", &"quick_draw"])


func test_link_effective_level_is_base_level_times_tier_ratio() -> void:
	var base := Matrix.new()
	base.id = &"jerry"
	base.level = 10

	var link := Matrix.new()
	link.base = base
	link.tier_ratio = 0.5

	assert_almost_eq(link.effective_level(), 5.0, 0.0001)


func test_link_carries_the_players_chosen_subset_of_the_bases_perks() -> void:
	var base := Matrix.new()
	base.perks = [&"steady_hands", &"quick_draw", &"iron_will", &"overclock"]

	var link := Matrix.new()
	link.base = base
	link.perk_slots = 2
	link.chosen_perks = [&"overclock", &"iron_will"]  # the base's own top perks, player's pick

	assert_eq(link.active_perks(), [&"overclock", &"iron_will"])
	assert_true(link.active_perks().size() <= link.perk_slots)


func test_destroying_a_link_flags_link_killed_on_the_base_and_docks_one_perk() -> void:
	var base := Matrix.new()
	base.perks = [&"steady_hands", &"quick_draw"]
	var link := Matrix.new()
	link.base = base

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var docked: StringName = link.destroy(rng)

	assert_eq(base.recovery_state, Enums.RecoveryState.LINK_KILLED)
	assert_eq(base.perks.size(), 1)
	assert_true(docked == &"steady_hands" or docked == &"quick_draw")
	assert_false(base.perks.has(docked))


func test_destroying_a_link_with_no_perks_left_is_a_harmless_no_op() -> void:
	var base := Matrix.new()
	var link := Matrix.new()
	link.base = base
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	assert_eq(link.destroy(rng), &"")
	assert_eq(base.recovery_state, Enums.RecoveryState.LINK_KILLED)


func test_destroying_an_unlinked_matrix_is_a_no_op() -> void:
	var matrix := Matrix.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(matrix.destroy(rng), &"")
	assert_eq(matrix.recovery_state, Enums.RecoveryState.PILOTING)
