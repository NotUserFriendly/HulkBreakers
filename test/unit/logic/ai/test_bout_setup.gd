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


## taskblock-28 Pass B: "a bout of kitted units starts fully armed at turn
## 1" — `kitted_chaingun`'s own GRIP_R starts deliberately bare (its
## loadout); only `KitEquipper`, run by `BoutSetup._spawn_squad` itself
## (never a separate, hand-called step this test has to trigger), fills
## it — proving the real bout-setup path self-arms, not just the
## mechanism in isolation.
func test_a_kitted_preset_spawns_armed_through_the_real_bout_setup_path() -> void:
	var kitted: BotPreset = DataLibrary.get_preset(&"kitted_chaingun")
	assert_not_null(kitted, "sanity: the shipped kitted preset must load")
	var unarmed_reference: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")

	var result: Dictionary = BoutSetup.build_bout(
		_roster(kitted, &"AGGRESSIVE", 1), _roster(unarmed_reference, &"COVER_SEEKER", 1), 42
	)

	assert_eq(result.error, "")
	var state: CombatState = result.state
	var kitted_unit: Unit = state.units[0]
	var weapon: Part = DeepStrike.find_operable_weapon(kitted_unit)
	assert_not_null(weapon, "the kitted unit must already be armed before turn 1")
	assert_eq(weapon.id, &"chaingun")
	assert_eq(weapon.ammo_id, &"556x45_fmj", "ready ammo — chambered, not just carried")

	var socket: Socket = PartGraph.find_socket(kitted_unit.shell.root, &"BACK")
	assert_eq(
		socket.occupant.contents.size(),
		0,
		"the weapon must have left the kit's own container once equipped"
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


## taskblock-21 Pass D2 / taskblock-23 Pass E1: "team-coded extraction
## tiles, placed at bout setup" — both squads get their OWN entry (now
## the OPPOSING squad's own spawn, tb23 E1 — see the dedicated test
## below for that specific placement), never a shared zone, and never
## left unpopulated the way a plain single-player mission's
## `team_extraction_cells` stays.
func test_build_bout_populates_team_extraction_cells_for_both_squads() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		_roster(profiles[0], &"AGGRESSIVE", 1), _roster(profiles[1], &"AGGRESSIVE", 1), 555
	)

	var mission: MissionState = result.mission
	assert_true(mission.team_extraction_cells.has(0))
	assert_true(mission.team_extraction_cells.has(1))
	assert_false(
		(mission.team_extraction_cells[0] as Array).is_empty(), "squad 0 must get at least one tile"
	)
	assert_false(
		(mission.team_extraction_cells[1] as Array).is_empty(), "squad 1 must get at least one tile"
	)
	assert_ne(
		mission.team_extraction_cells[0],
		mission.team_extraction_cells[1],
		"each squad gets its own zone, not a shared one"
	)


## taskblock-23 Pass E1: "place each team's extraction near the OPPOSING
## team's spawn — this pulls the teams through each other and forces
## engagement." Squad 0 (spawns at SPAWN_A) extracts at SPAWN_B and vice
## versa — the exact opposite of tb21 D2's own original "each squad's
## own spawn doubles as its own extraction" placement, which let both
## teams sit still on their own side with no reason to cross at all.
func test_build_bout_places_each_squads_extraction_on_the_opposing_side() -> void:
	var profiles: Array = _reference_profiles()

	var result: Dictionary = BoutSetup.build_bout(
		_roster(profiles[0], &"AGGRESSIVE", 1), _roster(profiles[1], &"AGGRESSIVE", 1), 555
	)

	var mission: MissionState = result.mission
	var state: CombatState = result.state
	var spawn_a: Array[Vector2i] = BoutSetup._cells_of_terrain(
		state.grid, Enums.TerrainType.SPAWN_A
	)
	var spawn_b: Array[Vector2i] = BoutSetup._cells_of_terrain(
		state.grid, Enums.TerrainType.SPAWN_B
	)

	assert_eq(
		mission.team_extraction_cells[0], spawn_b, "squad 0 (spawns at SPAWN_A) extracts at SPAWN_B"
	)
	assert_eq(
		mission.team_extraction_cells[1], spawn_a, "squad 1 (spawns at SPAWN_B) extracts at SPAWN_A"
	)


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
