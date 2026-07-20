extends GutTest

## taskblock-28 Pass A: seeded variant generation — `VariantGenerator`
## mutates a copy of a base `BotPreset`'s own `Loadout` according to a
## `VariantFamily`'s open data, never a hardcoded per-family branch. Most
## of these tests build their own minimal template/family fixtures
## (CLAUDE.md: "if a test needs a concrete list, the test authors it as a
## fixture") rather than depending on JunkBot's real shipped content,
## except where JunkBot itself is what's under test.


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func test_zero_variation_amount_always_returns_the_base_loadout_unchanged() -> void:
	var base := BotPreset.new(
		"combat_tester",
		&"reference_humanoid",
		Loadout.new({&"GRIP_L": &"pistol"}),
		&"IDLE",
		&"combat_tester"
	)
	var family_def := VariantFamily.new(&"combat_tester", 0.0, [&"GRIP_L"], {})

	for seed_value in range(20):
		var variant: BotPreset = VariantGenerator.generate(base, family_def, _rng(seed_value))
		assert_eq(
			variant.loadout.entries, {&"GRIP_L": &"pistol"}, "seed %d must be uniform" % seed_value
		)


func test_no_authored_family_falls_back_to_uniform_generation() -> void:
	var base := BotPreset.new(
		"nameless",
		&"reference_humanoid",
		Loadout.new({&"GRIP_L": &"pistol"}),
		&"IDLE",
		&"nameless_family"
	)
	var variant: BotPreset = VariantGenerator.generate_for_family(base, _rng(1))
	assert_eq(variant.loadout.entries, {&"GRIP_L": &"pistol"})


func test_an_omittable_socket_is_sometimes_bare_and_sometimes_not_across_seeds() -> void:
	var base := BotPreset.new(
		"junk",
		&"reference_humanoid",
		Loadout.new({&"ARMOR_FRONT": &"plate_small_steel"}),
		&"IDLE",
		&"junk"
	)
	var family_def := VariantFamily.new(&"junk", 0.5, [&"ARMOR_FRONT"], {})

	var saw_bare := false
	var saw_present := false
	for seed_value in range(40):
		var variant: BotPreset = VariantGenerator.generate(base, family_def, _rng(seed_value))
		if variant.loadout.entries.get(&"ARMOR_FRONT") == &"":
			saw_bare = true
		else:
			saw_present = true
	assert_true(saw_bare, "at least one of 40 seeds must omit the socket")
	assert_true(saw_present, "at least one of 40 seeds must keep the socket")


func test_a_swap_pool_socket_sometimes_picks_an_alternate() -> void:
	var base := BotPreset.new("junk", &"reference_humanoid", Loadout.new({}), &"IDLE", &"junk")
	var family_def := VariantFamily.new(
		&"junk", 1.0, [], {&"ARMOR_FRONT": [&"plate_large_steel", &"plate_large_sheet_steel"]}
	)

	var seen_ids: Array[StringName] = []
	for seed_value in range(20):
		var variant: BotPreset = VariantGenerator.generate(base, family_def, _rng(seed_value))
		var chosen: StringName = variant.loadout.entries.get(&"ARMOR_FRONT")
		assert_true(
			chosen in [&"plate_large_steel", &"plate_large_sheet_steel"],
			"must pick from the authored swap pool, got %s" % chosen
		)
		if not chosen in seen_ids:
			seen_ids.append(chosen)
	assert_eq(seen_ids.size(), 2, "20 seeds at variation_amount 1.0 must exercise both options")


## docs/00 determinism: "same seed = same battle, always."
func test_the_same_seed_reproduces_the_same_variant_exactly() -> void:
	var base := BotPreset.new(
		"junk",
		&"reference_humanoid",
		Loadout.new({&"ARMOR_FRONT": &"plate_small_steel"}),
		&"IDLE",
		&"junk"
	)
	var family_def := VariantFamily.new(
		&"junk", 0.6, [&"ARMOR_FRONT"], {&"ARMOR_FRONT": [&"plate_large_steel"]}
	)

	var a: BotPreset = VariantGenerator.generate(base, family_def, _rng(99))
	var b: BotPreset = VariantGenerator.generate(base, family_def, _rng(99))
	assert_eq(a.loadout.entries, b.loadout.entries)


## "A designer adds a new variant family without code" — the generator
## must handle a family it has never seen before, built at runtime here,
## purely from data it declares.
func test_a_brand_new_family_needs_no_generator_code_change() -> void:
	var base := BotPreset.new(
		"widget",
		&"reference_humanoid",
		Loadout.new({&"WIDGET_SLOT": &"widget_a"}),
		&"IDLE",
		&"widgets"
	)
	var family_def := VariantFamily.new(&"widgets", 1.0, [&"WIDGET_SLOT"], {})

	var variant: BotPreset = VariantGenerator.generate(base, family_def, _rng(5))
	assert_eq(variant.loadout.entries.get(&"WIDGET_SLOT"), &"", "must omit — the only draw at 1.0")


func test_editing_the_base_after_generating_never_touches_the_variant() -> void:
	var base := BotPreset.new(
		"junk",
		&"reference_humanoid",
		Loadout.new({&"ARMOR_FRONT": &"plate_small_steel"}),
		&"IDLE",
		&"junk"
	)
	var family_def := VariantFamily.new(&"junk", 0.0, [], {})
	var variant: BotPreset = VariantGenerator.generate(base, family_def, _rng(1))

	base.loadout.entries[&"ARMOR_FRONT"] = &"plate_large_steel"
	assert_eq(variant.loadout.entries[&"ARMOR_FRONT"], &"plate_small_steel")


## JunkBot's own real content: a distinct base template with independently
## addressable per-limb ARMOR/CLADDING sockets, purpose-built to prove the
## mechanism against a real, DataLibrary-loadable family.
func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func test_junk_bot_family_generates_structurally_different_bots_across_seeds() -> void:
	var base: BotPreset = JunkBot.base_preset()
	var structures: Array[Array] = []
	for seed_value in range(30):
		var variant: BotPreset = VariantGenerator.generate_for_family(base, _rng(seed_value))
		var unit: Unit = JunkBot.assemble_from_preset(variant, Matrix.new(), Vector2i(0, 0))
		assert_not_null(unit, "seed %d must still assemble" % seed_value)
		var ids: Array = PartGraph.walk(unit.shell.root).map(
			func(p: Part) -> StringName: return p.id
		)
		ids.sort()
		if not ids in structures:
			structures.append(ids)
	assert_gt(
		structures.size(), 1, "at least two of 30 seeds must produce a structurally different bot"
	)


func test_junk_bot_family_is_deterministic_from_the_same_seed() -> void:
	var base: BotPreset = JunkBot.base_preset()
	var a: BotPreset = VariantGenerator.generate_for_family(base, _rng(17))
	var b: BotPreset = VariantGenerator.generate_for_family(base, _rng(17))
	assert_eq(a.loadout.entries, b.loadout.entries)


func test_combat_tester_family_produces_uniform_bots() -> void:
	var base := BotPreset.new(
		"combat_tester_chaingun",
		&"reference_humanoid",
		Loadout.new({&"ARMOR_FRONT": &"wedge_plate_torso", &"GRIP_R": &"chaingun"}),
		&"IDLE",
		&"combat_tester"
	)
	var first: BotPreset = VariantGenerator.generate_for_family(base, _rng(1))
	for seed_value in range(2, 20):
		var variant: BotPreset = VariantGenerator.generate_for_family(base, _rng(seed_value))
		assert_eq(
			variant.loadout.entries, first.loadout.entries, "seed %d must be uniform" % seed_value
		)
	assert_eq(first.loadout.entries, base.loadout.entries, "zero variation changes nothing at all")


func test_every_generated_junk_bot_variant_passes_assembly_validation() -> void:
	var base: BotPreset = JunkBot.base_preset()
	for seed_value in range(30):
		var variant: BotPreset = VariantGenerator.generate_for_family(base, _rng(seed_value))
		var unit: Unit = JunkBot.assemble_from_preset(variant, Matrix.new(), Vector2i(0, 0))
		assert_not_null(unit, "seed %d must assemble" % seed_value)
		var violations: Array[String] = DeepStrike.validate_assembly(unit)
		assert_eq(violations, [] as Array[String], "seed %d: %s" % [seed_value, violations])


func test_the_junk_bot_variant_family_is_loaded_from_real_data() -> void:
	var family_def: VariantFamily = DataLibrary.get_variant_family(&"junk_bot")
	assert_not_null(family_def)
	assert_gt(family_def.variation_amount, 0.0)
	assert_gt(family_def.omittable_sockets.size(), 0)
