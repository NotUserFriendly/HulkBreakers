extends GutTest

## taskblock-64 Pass E — **a bout can be won by fighting.**
##
## Every AI measurement before this ran in a mode where *leaving* wins: a squad that never fires
## can still complete a mission, which is why `BR63.04`'s 31 turns of silence read as a slow bout
## rather than a broken one. **The win condition is itself the instrument** — under `contest`,
## that bout ends immediately as a loss instead of running to the turn cap.
##
## **Not "deathmatch".** The name overstates it: this is *a team that can no longer contest has
## lost*, which is narrower and more useful. Three terminating conditions, and they collapse to
## one predicate because `extract_unit` already sets `alive = false`:
##
## - no living units;
## - no units on the board — the whole team fled or extracted;
## - **no unit with a usable weapon**, which is the diagnostic one.
##
## The modes must not leak into each other, so every claim here is made twice: once under
## `contest` and once under `extraction`, which must still behave exactly as it did.

const CONTEST := MissionState.VICTORY_CONTEST
const EXTRACTION := MissionState.VICTORY_EXTRACTION


## This file builds bouts, so the fast gate skips it — the same reason `test_utility_planner.gd`
## and `test_bout_runner.gd` do. Untyped return on purpose: GUT declares it that way and an added
## `-> Variant` reads as a signature mismatch.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## An armed unit, built on `test_bout_runner.gd`'s own known-good shape — a hand carrying the
## `TRIGGER` capability the weapon `requires`, a docked matrix, real scatter rings.
##
## **Copied deliberately rather than trimmed.** The first version of this fixture had a weapon
## socketed straight onto the torso with no manipulator and no matrix, and a bout built on it
## **hung** rather than failing: nine minutes elapsed against one second of CPU. A fixture that
## is merely *nearly* a unit is not a cheaper fixture.
func _armed(id: StringName, cell: Vector2i, squad_id: int, tier: StringName) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 6.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 15.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket, Socket.new(&"MATRIX")]

	var link := Matrix.new()
	link.id = StringName("%s_link" % id)
	torso.hosted_matrix = link

	var unit := Unit.new(link, Shell.new(torso), cell, squad_id)
	unit.intelligence_tier = tier
	return unit


func _mission(units: Array[Unit], mode: StringName) -> MissionState:
	var state := CombatState.new(GridFixture.flat(12, 5), units, 11)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	mission.victory_mode = mode
	mission.player_squad_id = 0
	return mission


# --- the predicate itself ----------------------------------------------------


func test_a_team_with_a_usable_weapon_can_contest() -> void:
	var mission: MissionState = _mission(
		[_armed(&"a", Vector2i(2, 2), 0, &"TRAINED")] as Array[Unit], CONTEST
	)
	gut.p("  armed TRAINED unit -> %s" % mission.team_can_contest(0))
	assert_true(mission.team_can_contest(0), "an armed unit whose tier can shoot is in the fight")


## **The diagnostic condition**, and the one a "has a functional weapon" test would miss. The
## weapon is undamaged and fully operable; the unit simply has no action that can fire it.
func test_a_team_whose_weapon_its_tier_cannot_fire_cannot_contest() -> void:
	var unit: Unit = _armed(&"a", Vector2i(2, 2), 0, &"MINDLESS")
	var mission: MissionState = _mission([unit] as Array[Unit], CONTEST)
	var weapon: Part = unit.shell.find_part(&"a_gun")

	gut.p("  weapon hp %d, operable %s" % [weapon.hp, weapon.hp > 0])
	gut.p(
		(
			"  MINDLESS reachable actions: %s"
			% UtilityContext.reachable_firing_actions(weapon, &"MINDLESS").size()
		)
	)
	gut.p("  team_can_contest -> %s" % mission.team_can_contest(0))

	assert_gt(weapon.hp, 0, "the weapon is not broken — that is the whole point of this case")
	assert_false(
		mission.team_can_contest(0),
		"a unit that can be offered no shot is not contesting, whatever is bolted to its arm"
	)


func test_a_team_with_a_destroyed_weapon_cannot_contest() -> void:
	var unit: Unit = _armed(&"a", Vector2i(2, 2), 0, &"TRAINED")
	var mission: MissionState = _mission([unit] as Array[Unit], CONTEST)
	assert_true(mission.team_can_contest(0), "armed to begin with")

	unit.shell.find_part(&"a_gun").hp = 0

	assert_false(mission.team_can_contest(0), "and not once the gun is shot off")


func test_a_team_that_is_dead_or_gone_cannot_contest() -> void:
	var dead: Unit = _armed(&"a", Vector2i(2, 2), 0, &"TRAINED")
	var mission: MissionState = _mission([dead] as Array[Unit], CONTEST)
	dead.alive = false
	assert_false(mission.team_can_contest(0), "no living unit is no contest")

	var gone: Unit = _armed(&"b", Vector2i(3, 2), 0, &"TRAINED")
	var second: MissionState = _mission([gone] as Array[Unit], CONTEST)
	second.extract_unit(gone)
	assert_true(gone.extracted, "the fixture actually extracted it")
	assert_false(second.team_can_contest(0), "a team that has left the board is not contesting")


# --- the bout actually ending ------------------------------------------------


## `BR63.04`'s bout, in miniature: one team armed, one team holding weapons it cannot fire.
## **Ends immediately rather than at the turn cap.**
func test_a_team_reduced_to_no_usable_weapon_loses_immediately() -> void:
	var mine: Unit = _armed(&"a", Vector2i(2, 2), 0, &"TRAINED")
	var theirs: Unit = _armed(&"b", Vector2i(8, 2), 1, &"MINDLESS")
	var mission: MissionState = _mission([mine, theirs] as Array[Unit], CONTEST)
	var runner := BoutRunner.new(mission.combat_state, mission, 400)

	var finished: bool = await runner.step()

	gut.p(
		(
			"  outcome %d after %d turns, winner squad %d"
			% [mission.outcome, runner.turns_taken, mission.debug_winner_squad_id]
		)
	)
	assert_true(finished, "the bout is over on the first step")
	assert_eq(mission.outcome, Enums.MissionOutcome.DEBUG_ENDED, "and says why")
	assert_eq(mission.debug_winner_squad_id, 0, "squad 0 is the only team that can still contest")
	assert_eq(runner.turns_taken, 0, "no turn was spent — this is the point of the mode")


## **The modes must not leak into each other.** The identical board under `extraction` must not
## end, because nothing about a campaign mission changes.
func test_the_same_board_does_not_end_under_extraction_mode() -> void:
	var mine: Unit = _armed(&"a", Vector2i(2, 2), 0, &"TRAINED")
	var theirs: Unit = _armed(&"b", Vector2i(8, 2), 1, &"MINDLESS")
	var mission: MissionState = _mission([mine, theirs] as Array[Unit], EXTRACTION)
	var runner := BoutRunner.new(mission.combat_state, mission, 400)

	await runner.step()

	gut.p("  extraction mode outcome after one step: %d" % mission.outcome)
	assert_ne(
		mission.outcome,
		Enums.MissionOutcome.DEBUG_ENDED,
		"DEBUG_ENDED must be unreachable outside the mode that asks for it"
	)


## A team that extracts entirely loses under `contest` — **and still wins under `extraction`**,
## which is the leak this pass has to rule out in both directions.
func test_a_team_that_extracts_entirely_loses_under_contest_but_extracts_under_extraction() -> void:
	var leaver: Unit = _armed(&"a", Vector2i(2, 2), 0, &"TRAINED")
	var stayer: Unit = _armed(&"b", Vector2i(8, 2), 1, &"TRAINED")
	var contest: MissionState = _mission([leaver, stayer] as Array[Unit], CONTEST)
	contest.extract_unit(leaver)
	var runner := BoutRunner.new(contest.combat_state, contest, 400)

	assert_true(await runner.step(), "the bout ends once one team has left")
	assert_eq(contest.outcome, Enums.MissionOutcome.DEBUG_ENDED, "under contest, leaving is losing")
	assert_eq(contest.debug_winner_squad_id, 1, "the team still on the board is the one contesting")

	var second_leaver: Unit = _armed(&"a", Vector2i(2, 2), 0, &"TRAINED")
	var second_stayer: Unit = _armed(&"b", Vector2i(8, 2), 1, &"TRAINED")
	var extraction: MissionState = _mission(
		[second_leaver, second_stayer] as Array[Unit], EXTRACTION
	)
	extraction.extract_unit(second_leaver)

	gut.p("  extraction-mode outcome after the same move: %d" % extraction.outcome)
	assert_eq(
		extraction.outcome,
		Enums.MissionOutcome.EXTRACTED,
		"and under extraction the identical move is a clean win — the modes must not leak"
	)


## Both teams out at once is a real tie, not an error state.
func test_no_team_able_to_contest_ends_with_no_winner() -> void:
	var mine: Unit = _armed(&"a", Vector2i(2, 2), 0, &"MINDLESS")
	var theirs: Unit = _armed(&"b", Vector2i(8, 2), 1, &"MINDLESS")
	var mission: MissionState = _mission([mine, theirs] as Array[Unit], CONTEST)
	var runner := BoutRunner.new(mission.combat_state, mission, 400)

	assert_true(await runner.step(), "nobody can fight, so there is nothing to run")
	assert_eq(mission.outcome, Enums.MissionOutcome.DEBUG_ENDED)
	assert_eq(mission.debug_winner_squad_id, -1, "a tie reports -1 rather than picking a side")


# --- the bout builder --------------------------------------------------------


## **A mode the supervisor cannot select is a mode that cannot be tested.** Round-trips the
## dropdown through the real module, not through a re-derivation of its list.
func test_the_mode_round_trips_through_the_bout_builder() -> void:
	var module := BoutSetupModule.new()
	autofree(module)
	assert_eq(
		module.selected_victory_mode(),
		EXTRACTION,
		"an unmounted module answers the default rather than failing"
	)

	assert_eq(
		BoutSetupModule.VICTORY_MODES.size(),
		BoutSetupModule.VICTORY_LABELS.size(),
		"every mode the dropdown offers has a label, and vice versa"
	)
	assert_eq(
		BoutSetupModule.VICTORY_MODES[0],
		EXTRACTION,
		"index 0 is the default, so an untouched menu builds the bout it always built"
	)
	assert_true(
		BoutSetupModule.VICTORY_MODES.has(CONTEST), "and contest is reachable from the menu at all"
	)


## The mode survives `BoutSetup.build_bout` onto the mission the bout actually runs.
func test_build_bout_carries_the_mode_onto_the_mission() -> void:
	var roster: Array[BoutRosterEntry] = []
	var entry := BoutRosterEntry.new()
	entry.profile = DataLibrary.get_preset(&"combat_tester_pump_shotgun")
	entry.ai_profile = &"aggressive"
	roster.append(entry)
	var other: Array[BoutRosterEntry] = []
	var entry_b := BoutRosterEntry.new()
	entry_b.profile = DataLibrary.get_preset(&"combat_tester_sniper_rifle")
	entry_b.ai_profile = &"aggressive"
	other.append(entry_b)

	var default_bout: Dictionary = BoutSetup.build_bout(roster, other, 4242)
	assert_eq(default_bout.get("error", ""), "", "the fixture roster builds")
	assert_eq(
		(default_bout["mission"] as MissionState).victory_mode,
		EXTRACTION,
		"an unspecified mode is the default, so every existing caller is unchanged"
	)

	var contest_bout: Dictionary = BoutSetup.build_bout(roster, other, 4242, CONTEST)
	assert_eq(
		(contest_bout["mission"] as MissionState).victory_mode,
		CONTEST,
		"and the chosen mode reaches the mission the runner reads"
	)
