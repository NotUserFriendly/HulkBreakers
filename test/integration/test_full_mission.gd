extends GutTest

## taskblock-39 Pass A: replaces the pinned-seed "does THIS scripted mission
## reach extraction" harness (docs/SUPERSEDED.md — six re-picks, every one a
## legitimate mechanics change absorbed as noise instead of a signal) with
## the question this file actually asks: can a mission be completed AT ALL?
## That's an EXISTENCE question, answered honestly by a completion RATE over
## many seeds, never a single frozen one — a pinning test fixes its inputs
## to catch a behaviour change; a sampling test asks a statistical question
## and should report a rate. Built on the same `BoutSetup`/`DeepStrike`/
## `BoutRunner` path a real "Simulate Bout" menu uses — never a hand-rolled
## turn loop (the old harness called `CombatState.resolve_turn` directly,
## silently skipping `BoutRunner.step()`'s own `Overwatch.check_trigger`
## wiring the whole time).
##
## Measured baseline (this pass, two independent samples, 1-vs-1 AGGRESSIVE
## a_brand_laborer/a_brand_laborer_battery_mods bouts, `TURN_CAP` below):
## 10 seeds at a 150-turn cap and 15 seeds at a 100-turn cap each landed
## ~80% EXTRACTED, the rest split between TERMINATED (turn cap) and
## STRANDED (the tracked squad wiped). `MIN_COMPLETION_RATE` is set well
## below that observed rate — enough margin for everyday seed-to-seed
## variance, still low enough to catch a real collapse (this is what would
## have gone red the instant the AI line-of-fire bug landed, instead of
## being absorbed across five silent re-picks). **Flagged as a tunable, not
## a design number** — re-measure and move it if the real rate drifts.
##
## Per-bout wall time varies far more than turn count does (a 21-turn bout
## and a 26-turn bout differed 13x in wall time in the same sample) — some
## seeds hit a genuinely expensive AI decision path, not just "more turns."
## Not this pass's job to fix; `SEED_COUNT`/`TURN_CAP` are kept modest
## specifically because of it.
const SEED_COUNT := 12
const TURN_CAP := 100
const MIN_COMPLETION_RATE := 0.5


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _roster(profile: BotPreset, playstyle: StringName, count: int) -> Array[BoutRosterEntry]:
	var roster: Array[BoutRosterEntry] = []
	for i in range(count):
		roster.append(BoutRosterEntry.new(profile, playstyle))
	return roster


## Every seed's own outcome and turn count, printed once at the end — the
## per-seed numbers are the actual useful artifact here (docs/taskblock39's
## own instruction), not just the pass/fail the assertion below reduces
## them to.
func test_bout_completion_rate_meets_the_measured_floor() -> void:
	var profile_a: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var profile_b: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	assert_not_null(profile_a, "sanity: a_brand_laborer must load")
	assert_not_null(profile_b, "sanity: a_brand_laborer_battery_mods must load")

	var completed := 0
	var summary_lines: Array[String] = []
	for map_seed in range(SEED_COUNT):
		var result: Dictionary = BoutSetup.build_bout(
			_roster(profile_a, &"AGGRESSIVE", 1), _roster(profile_b, &"AGGRESSIVE", 1), map_seed
		)
		assert_eq(result.error, "", "seed %d: bout must build" % map_seed)

		var runner := BoutRunner.new(result.state, result.mission, TURN_CAP)
		runner.run_to_completion()

		var outcome: int = result.mission.outcome
		assert_ne(
			outcome,
			Enums.MissionOutcome.UNDECIDED,
			"seed %d: BoutRunner guarantees a terminal outcome" % map_seed
		)
		if outcome == Enums.MissionOutcome.EXTRACTED:
			completed += 1
		summary_lines.append(
			(
				"seed %d: %s in %d turns"
				% [map_seed, Enums.MissionOutcome.keys()[outcome], runner.turns_taken]
			)
		)

	var rate: float = float(completed) / SEED_COUNT
	print("\nbout completion rate: %d/%d (%.1f%%)" % [completed, SEED_COUNT, rate * 100.0])
	for line: String in summary_lines:
		print("  " + line)

	assert_true(
		rate >= MIN_COMPLETION_RATE,
		(
			"completion rate %.1f%% fell below the measured floor %.1f%%"
			% [rate * 100.0, MIN_COMPLETION_RATE * 100.0]
		)
	)
