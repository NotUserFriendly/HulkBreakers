extends GutTest

## taskblock-47 Pass A: **the deterministic work counters the suite profile and Pass
## B's budgets are both built on.**
##
## Wall-clock is machine-dependent and this project has a documented habit of raising
## a constant when a threshold flaps — the completion floor went 0.5 to 0.25 to 0.35
## that way. So the budgets gate on counts instead, and counts are only worth gating
## on if two runs of the same work produce the same number. **If that is not true,
## everything downstream of it is decoration.**
##
## ## The second assertion is the one that would actually catch something
##
## A counter wired to nothing is perfectly deterministic: it reports zero, every
## time, forever. A budget built on it never fails and nobody finds out until the
## suite has doubled again. So every counter is also asserted to *move* for a
## workload that should move it — `docs/11`'s "a restriction that does nothing passes
## every test asserting what it should do", applied to instrumentation.

## Kept to two short bouts. This file measures the measuring apparatus; it has no
## business being expensive itself, and a determinism property is exactly as true of
## one seed as of fifty.
const SEED := 4242
const TURN_CAP := 6

## Every counter the profiler snapshots. Authored here as a fixture rather than
## imported from the tool, so adding a counter to the profiler without teaching it to
## anyone shows up as a failure here rather than as a silently unmeasured field.
const COUNTERS: Array[String] = ["bouts", "turns", "plans", "candidates", "shot_planes", "floods"]


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()
	_reset_all()


func after_each() -> void:
	DataLibrary.reset()


func _reset_all() -> void:
	CombatState.reset_diagnostics()
	Pathfinder.reset_diagnostics()
	AiPlanner.reset_diagnostics()
	UtilityPlanner.candidates_scored = 0
	UtilityPlanner.empty_decisions = 0
	ShotPlane.builds = 0


func _snapshot() -> Dictionary:
	return {
		"bouts": CombatState.bouts_built,
		"turns": CombatState.turns_resolved,
		"plans": AiPlanner.plans,
		"candidates": UtilityPlanner.candidates_scored,
		"shot_planes": ShotPlane.builds,
		"floods": Pathfinder.floods,
	}


## One short bout, played from a fixed seed through the same path the game uses.
func _play() -> Dictionary:
	_reset_all()
	var profile_a: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var profile_b: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	var built: Dictionary = BoutSetup.build_bout(
		[BoutRosterEntry.new(profile_a, &"aggressive")] as Array[BoutRosterEntry],
		[BoutRosterEntry.new(profile_b, &"aggressive")] as Array[BoutRosterEntry],
		SEED
	)
	assert_eq(built.get("error", ""), "", "sanity: the bout builds")
	var runner := BoutRunner.new(built["state"], built["mission"], TURN_CAP)
	await runner.run_to_completion()
	return _snapshot()


# --- determinism ---------------------------------------------------------------


## **The foundation.** Same seed, same work — down to the integer, for every counter.
## A count that drifts between runs cannot be budgeted against, and a budget that
## flakes gets raised rather than investigated.
func test_the_same_bout_does_identical_work_twice() -> void:
	var first: Dictionary = await _play()
	var second: Dictionary = await _play()

	gut.p("counts: %s" % [first])
	for key: String in COUNTERS:
		assert_eq(int(second[key]), int(first[key]), "%s drifted between two identical runs" % key)


# --- the counters are wired to something ---------------------------------------


## **A counter wired to nothing is perfectly deterministic and completely useless.**
## Every field the profiler reads has to move for work that should move it, or Pass
## B's budget for it can never fail.
func test_every_counter_actually_counts() -> void:
	var counts: Dictionary = await _play()

	for key: String in COUNTERS:
		assert_gt(int(counts[key]), 0, "%s stayed at zero — it is not wired to anything" % key)


## Resetting has to actually clear, or a profile reports the previous file's work
## against this one and every attribution in it is wrong.
func test_resetting_clears_every_counter() -> void:
	await _play()
	for key: String in COUNTERS:
		assert_gt(int(_snapshot()[key]), 0, "sanity: %s is non-zero before the reset" % key)

	_reset_all()

	for key: String in COUNTERS:
		assert_eq(int(_snapshot()[key]), 0, "%s survived the reset" % key)


# --- what the counters mean -----------------------------------------------------


## Turns are counted at `CombatState.advance_turn`, **not** in `BoutRunner`, so a
## test that drives the board by hand is measured like any other. That distinction is
## the whole point of the counter for taskblock-47 Pass E: retargeting a test from a
## planner-driven bout to a scripted queue must show up as bouts falling while turns
## stay honest, and a runner-side counter would report the scripted version as free.
func test_a_scripted_turn_counts_without_any_bout_being_built() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var other: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(5, 5), 1)
	var state := CombatState.new(grid, [unit, other])
	_reset_all()

	state.advance_turn()

	assert_eq(CombatState.turns_resolved, 1, "a hand-driven turn is still a turn")
	assert_eq(CombatState.bouts_built, 0, "and it built no bout")


## A rejected roster is not a bout that was played. Counted after the validation
## gates for that reason — otherwise every test that checks an error path inflates
## the bout budget.
func test_a_rejected_roster_does_not_count_as_a_bout() -> void:
	_reset_all()

	var built: Dictionary = BoutSetup.build_bout(
		[] as Array[BoutRosterEntry], [] as Array[BoutRosterEntry], SEED
	)

	assert_ne(built.get("error", ""), "", "sanity: this roster is rejected")
	assert_eq(CombatState.bouts_built, 0)
