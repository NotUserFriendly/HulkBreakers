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


## taskblock-17 Pass D: a squad is now a LIST of `BoutRosterEntry`
## (profile + that bot's own playstyle) — this helper stands in for "add
## the same profile/playstyle pair twice," the common case a list-of-2
## covers for tests that don't care about mixed rosters.
func _roster(profile: BotPreset, playstyle: StringName, count: int) -> Array[BoutRosterEntry]:
	var roster: Array[BoutRosterEntry] = []
	for i in range(count):
		roster.append(BoutRosterEntry.new(profile, playstyle))
	return roster


## taskblock-17 Pass A: same regression as `BattleScene`'s own default —
## `GRID_WIDTH`/`GRID_HEIGHT` used to be 20x14, under
## `MapGen.MIN_LEAF_SIZE * 2` (24) on both axes, so a bout's own map was
## also silently one room forever. Pinned directly against the constant
## so a future `MIN_ROOM_SIZE` raise can't regress this again unnoticed.
func test_grid_size_clears_the_map_gen_split_threshold() -> void:
	assert_true(
		BoutSetup.GRID_WIDTH >= MapGen.MIN_LEAF_SIZE * 2,
		"GRID_WIDTH must clear MapGen.MIN_LEAF_SIZE * 2 or a bout's own map never splits"
	)
	assert_true(
		BoutSetup.GRID_HEIGHT >= MapGen.MIN_LEAF_SIZE * 2,
		"GRID_HEIGHT must clear MapGen.MIN_LEAF_SIZE * 2 or a bout's own map never splits"
	)


func test_a_valid_bout_builds_a_real_state_and_mission() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		_roster(profiles[0], &"AGGRESSIVE", 2), _roster(profiles[1], &"COVER_SEEKER", 2), 555
	)

	assert_eq(result.error, "")
	var state: CombatState = result.state
	var mission: MissionState = result.mission
	assert_not_null(state)
	assert_not_null(mission)
	assert_eq(state.units.size(), 4)
	assert_eq(state.controller_for(0), Enums.SquadController.AI)
	assert_eq(state.controller_for(1), Enums.SquadController.AI)


## taskblock-16 Pass E: "the built bout's roster equals the list" — a
## squad built from a MIXED roster (two distinct profiles at two
## distinct index positions, not one profile repeated) must thread each
## index's own profile through to that index's own unit, not silently
## reuse `profiles[0]` for the whole squad.
func test_the_built_roster_equals_a_mixed_list_of_distinct_profiles() -> void:
	var profiles: Array = _reference_profiles()
	var mixed: Array[BoutRosterEntry] = [
		BoutRosterEntry.new(profiles[0], &"AGGRESSIVE"),
		BoutRosterEntry.new(profiles[1], &"AGGRESSIVE")
	]

	var result: Dictionary = BoutSetup.build_bout(
		mixed, _roster(profiles[0], &"AGGRESSIVE", 1), 321
	)

	assert_eq(result.error, "")
	var squad_a: Array[Unit] = result.state.units.filter(
		func(u: Unit) -> bool: return u.squad_id == 0
	)
	assert_eq(squad_a.size(), 2)
	for i in range(squad_a.size()):
		assert_true(
			String(squad_a[i].matrix.id).begins_with(String(mixed[i].profile.preset_name)),
			(
				"unit %d must be assembled from its own list index's profile (%s), not always index 0"
				% [i, mixed[i].profile.preset_name]
			)
		)


## taskblock-17 Pass D: "playstyle moves from per-team to per-bot" — two
## entries in the SAME squad, each carrying its own distinct playstyle,
## must both survive into the assembled units, not collapse to one
## shared value per team.
func test_squad_units_carry_their_own_per_bot_playstyle() -> void:
	var profiles: Array = _reference_profiles()
	var mixed_squad: Array[BoutRosterEntry] = [
		BoutRosterEntry.new(profiles[0], &"AGGRESSIVE"),
		BoutRosterEntry.new(profiles[0], &"MARKSMAN")
	]

	var result: Dictionary = BoutSetup.build_bout(
		mixed_squad, _roster(profiles[1], &"COVER_SEEKER", 1), 9
	)

	var squad_a: Array[Unit] = result.state.units.filter(
		func(u: Unit) -> bool: return u.squad_id == 0
	)
	assert_eq(squad_a.size(), 2)
	assert_eq(squad_a[0].matrix.playstyle, &"AGGRESSIVE")
	assert_eq(squad_a[1].matrix.playstyle, &"MARKSMAN")

	var squad_b: Array[Unit] = result.state.units.filter(
		func(u: Unit) -> bool: return u.squad_id == 1
	)
	assert_eq(squad_b[0].matrix.playstyle, &"COVER_SEEKER")


## "An invalid setup (empty team) is rejected, not crashed" — no count
## field left to be zero; the roster list itself is just empty.
func test_an_empty_roster_is_rejected_not_crashed() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		[] as Array[BoutRosterEntry], _roster(profiles[1], &"AGGRESSIVE", 2), 1
	)

	assert_ne(result.error, "")
	assert_false(result.has("state"))


func test_a_missing_profile_is_rejected_not_crashed() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		[BoutRosterEntry.new(null, &"AGGRESSIVE")] as Array[BoutRosterEntry],
		_roster(profiles[1], &"AGGRESSIVE", 2),
		1
	)

	assert_ne(result.error, "")
	assert_false(result.has("state"))


## "A bout built from the menu matches one built directly from the same
## profiles/counts/seed."
func test_the_same_profiles_counts_and_seed_produce_an_equivalent_bout() -> void:
	var profiles: Array = _reference_profiles()

	var first: Dictionary = BoutSetup.build_bout(
		_roster(profiles[0], &"AGGRESSIVE", 2), _roster(profiles[1], &"AGGRESSIVE", 2), 777
	)
	var second: Dictionary = BoutSetup.build_bout(
		_roster(profiles[0], &"AGGRESSIVE", 2), _roster(profiles[1], &"AGGRESSIVE", 2), 777
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
