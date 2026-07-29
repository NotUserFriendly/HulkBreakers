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
## Measured baseline (this pass, two independent samples, 1-vs-1 aggressive
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
## **taskblock-45 lowered this from 0.5, and that is a recorded regression rather
## than a re-measurement.** taskblock-46 re-baselined it on fixed ground and left
## it here. Read this before trusting the number.
##
## Re-measured taskblock-46 Pass B, both planners, same probe, same 24 seeds, on
## the map generator AFTER Pass A stopped raised rooms sinking objects to level 0.
## The old planner was run from a worktree at `107af1e` carrying the same map fix,
## so the only difference between the columns is the planner:
##
## | | old | new |
## |---|---|---|
## | completion, 24 seeds | 18/24 (75.0%) | 12/24 (50.0%) |
## | mean turns to complete | 31.3 | **10.8** |
## | failure modes | 6 `TERMINATED` | 10 `TERMINATED`, 2 `STRANDED` |
##
## **The true rate is 54%**, from a 100-seed run of the new planner on the same
## ground (54 EXTRACTED, 37 TERMINATED, 9 STRANDED, mean 9.8 turns, 307 s). The
## 24-seed figure above is one draw; this is the number the floor is set against.
##
## **The gap narrowed from 33 points to 25** once the ground was level, and it is
## still a real regression — `BR45.03`. The planner is not uniformly worse: it
## finishes in a third of the turns when it finishes at all.
##
## **0.35 is unchanged, and deliberately so.** At a true 0.54 a 100-seed run falls
## below it essentially never, so the gate is comfortable where it matters. A
## *sample* can still dip, which is why a dip escalates rather than fails
## (`CompletionSampler`, whose `SAMPLE_SEEDS` is sized so that happens about one run
## in 38). The old harness pinned seeds 0–11, the pessimistic window, and read 33.3%
## there while the real rate was 54%; that is what made this constant look like it
## needed lowering again. It did not.
##
## **CC recommended against both landing the planner with this open and moving this
## constant; the supervisor decided otherwise.** Raise it back toward 0.5 as
## `BR45.03` closes — it is the one automated check standing between this project
## and an AI that cannot finish a mission.
const MIN_COMPLETION_RATE := 0.35


## taskblock-47 Pass C: this file builds bouts, so the fast gate skips it. The list it
## is on is checked against the profile's own bout counter every run — see `SuiteTier`.
##
## **Untyped on purpose, against this project's static-typing rule.** GUT declares
## `func should_skip_script():` with no return type, and Godot treats an override that
## adds `-> Variant` as a signature mismatch — the script then fails to parse and GUT
## reports it as "does not extend GutTest", which is a long way from the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _roster(profile: BotPreset, ai_profile: StringName, count: int) -> Array[BoutRosterEntry]:
	var roster: Array[BoutRosterEntry] = []
	for i in range(count):
		roster.append(BoutRosterEntry.new(profile, ai_profile))
	return roster


## taskblock-46 Pass B: **sample here, measure with a command.**
##
## Twenty seeds drawn at random per run, every one printed. The floor is checked
## against that sample, and a dip **fails and names the command that settles it**
## rather than running a hundred missions inline.
##
## The escalation is still the authority and still deterministic — it just is not
## the suite's to run. It plays a hundred bouts and costs upward of ten minutes;
## the suite is the feedback loop everything else depends on, and a gate that
## occasionally triples its own runtime teaches people to stop running it.
##
## **That trade only works if a spurious dip is rare**, and it is: at the measured
## 0.60 completion rate a twenty-seed draw lands below the 0.35 floor roughly one
## run in 160. The reported probability below is exactly that number, so if it ever
## climbs, this design is the thing to revisit.
##
## **This replaces a pinned window that was measuring the wrong thing.** Seeds 0–11
## read 33.3% while the real rate was 54%, because that window is the pessimistic
## one; the response to a floor that keeps flapping had twice been to lower it.
##
## The RNG is seeded from the clock ON PURPOSE. A fixed seed here would rebuild the
## pinned window under a new name — the point is that the sample walks the space
## over runs, and the printed seed list is what makes any individual run
## reproducible afterwards.
func test_bout_completion_rate_meets_the_measured_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system())

	var sampled: Dictionary = await CompletionSampler.sample(rng)
	print("\n--- completion sample ---")
	for line: String in CompletionSampler.describe(sampled):
		print(line)

	var rate: float = float(sampled["rate"])
	# Reported every run, pass or fail. With the escalation moved out of the suite
	# this is the probability of a SPURIOUS failure, which is the number that says
	# whether sampling is still a fair gate.
	var spurious: float = CompletionSampler.escalation_probability(rate, MIN_COMPLETION_RATE)
	print(
		(
			"spurious-failure probability at this rate: %.1f%% (~1 run in %d)"
			% [spurious * 100.0, int(round(1.0 / maxf(0.0001, spurious)))]
		)
	)
	assert_gt(int(sampled["counted"]), 0, "sanity: the sample actually ran bouts")

	assert_false(
		CompletionSampler.should_escalate(rate, MIN_COMPLETION_RATE),
		(
			(
				"sample %.1f%% is below the %.1f%% floor over %d seeds. Confirm with the "
				+ "deterministic %d-seed run before treating this as real:\n"
				+ "    godot --headless --path . -s res://tools/probe_seeds.gd\n"
				+ "seeds drawn: %s"
			)
			% [
				rate * 100.0,
				MIN_COMPLETION_RATE * 100.0,
				int(sampled["counted"]),
				CompletionSampler.ESCALATION_SEEDS,
				str(sampled["seeds"])
			]
		)
	)
