extends GutTest

## taskblock-14 Pass D: BoutSetup — the headless matchup-building logic
## behind the "Simulate Bout" menu.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _reference_profiles() -> Array:
	var base: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var variant: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	return [base, variant]


func test_a_valid_bout_builds_a_real_state_and_mission() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		profiles[0], 2, &"AGGRESSIVE", profiles[1], 2, &"COVER_SEEKER", 555
	)

	assert_eq(result.error, "")
	var state: CombatState = result.state
	var mission: MissionState = result.mission
	assert_not_null(state)
	assert_not_null(mission)
	assert_eq(state.units.size(), 4)
	assert_eq(state.controller_for(0), Enums.SquadController.AI)
	assert_eq(state.controller_for(1), Enums.SquadController.AI)


func test_squad_units_carry_their_own_assigned_playstyle() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		profiles[0], 2, &"AGGRESSIVE", profiles[1], 1, &"COVER_SEEKER", 9
	)

	var state: CombatState = result.state
	for unit: Unit in state.units:
		var expected: StringName = &"AGGRESSIVE" if unit.squad_id == 0 else &"COVER_SEEKER"
		assert_eq(unit.matrix.playstyle, expected, "unit %s carries the wrong playstyle" % unit.id)


## "An invalid setup (empty squad) is rejected, not crashed."
func test_a_zero_count_squad_is_rejected_not_crashed() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		profiles[0], 0, &"AGGRESSIVE", profiles[1], 2, &"AGGRESSIVE", 1
	)

	assert_ne(result.error, "")
	assert_false(result.has("state"))


func test_a_missing_profile_is_rejected_not_crashed() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		null, 2, &"AGGRESSIVE", profiles[1], 2, &"AGGRESSIVE", 1
	)

	assert_ne(result.error, "")
	assert_false(result.has("state"))


## "A bout built from the menu matches one built directly from the same
## profiles/counts/seed."
func test_the_same_profiles_counts_and_seed_produce_an_equivalent_bout() -> void:
	var profiles: Array = _reference_profiles()

	var first: Dictionary = BoutSetup.build_bout(
		profiles[0], 2, &"AGGRESSIVE", profiles[1], 2, &"AGGRESSIVE", 777
	)
	var second: Dictionary = BoutSetup.build_bout(
		profiles[0], 2, &"AGGRESSIVE", profiles[1], 2, &"AGGRESSIVE", 777
	)

	var first_state: CombatState = first.state
	var second_state: CombatState = second.state
	assert_eq(first_state.units.size(), second_state.units.size())
	for i in range(first_state.units.size()):
		assert_eq(first_state.units[i].cell, second_state.units[i].cell)
		assert_eq(first_state.units[i].squad_id, second_state.units[i].squad_id)


## "The menu lists loaded profiles" — grouped by family, base first.
func test_group_by_family_groups_the_base_and_its_variant_together() -> void:
	var profiles: Array[BotPreset] = []
	for p: BotPreset in _reference_profiles():
		profiles.append(p)

	var groups: Dictionary = BoutSetup.group_by_family(profiles)

	assert_true(groups.has(&"a_brand_laborer"))
	var members: Array[BotPreset] = groups[&"a_brand_laborer"]
	assert_eq(members.size(), 2)
	assert_eq(members[0].variant_label, "", "the base (empty variant_label) must sort first")
	assert_eq(members[1].variant_label, "Battery Mods")


## A preset with no profile_family authored groups under its own name —
## never dropped, never crashing the dropdown.
func test_group_by_family_falls_back_to_the_presets_own_name_when_ungrouped() -> void:
	var lone := BotPreset.new("lone_bot", ShellTemplates.DEFAULT_ID)

	var groups: Dictionary = BoutSetup.group_by_family([lone])

	assert_true(groups.has(&"lone_bot"))
	assert_eq((groups[&"lone_bot"] as Array[BotPreset]).size(), 1)
