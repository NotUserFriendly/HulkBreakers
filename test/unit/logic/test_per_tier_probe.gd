extends GutTest

## taskblock-59 Pass F — **the completion probe reports per tier, and the floor is not touched.**
##
## *"Every completion rate this project has recorded is an all-`TRAINED` rate. With a spread
## authored, take it again."* The measurement itself is a command (`tools/probe_tiers.gd`) because
## it plays dozens of bouts; what belongs in the suite is that the probe **has** the shape the pass
## asks for, and that nothing quietly adjusted the threshold to make the new number acceptable.

## Two tiers and one seed, at a horizon of a few turns. **The claim under test is the report's
## shape, not its numbers** — the rates come from the probe, which plays dozens of bouts and is
## deliberately not in the suite. A full-horizon run here would cost minutes to assert a dictionary
## has the right keys in it.
const PROBE_TIERS: Array[StringName] = [&"MINDLESS", &"ELITE"]
const PROBE_CAP := 4


## taskblock-47 Pass C: this file builds bouts, so the fast gate skips it.
##
## **Untyped on purpose, against this project's static-typing rule** — GUT declares
## `should_skip_script()` with no return type and Godot treats an added `-> Variant` as a
## signature mismatch, which reports as "does not extend GutTest" and hides the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## **The acceptance**: the probe reports per tier, and reports the mixed roster alongside.
func test_the_completion_probe_reports_per_tier_and_the_mixed_roster() -> void:
	var rows: Array[Dictionary] = await CompletionSampler.per_tier(
		PROBE_TIERS, [4242] as Array[int], PROBE_CAP
	)

	assert_eq(rows.size(), PROBE_TIERS.size() + 1, "one row per tier, plus the mixed roster")
	for i: int in range(PROBE_TIERS.size()):
		assert_eq(rows[i]["tier"], PROBE_TIERS[i], "row %d is not the tier it claims" % i)
	assert_eq(rows[rows.size() - 1]["tier"], &"", "the last row is the mixed roster")


## **Every row is the same seeds**, or the per-tier figures are comparing maps as much as
## intelligence.
func test_every_tier_is_measured_over_the_same_seeds() -> void:
	var seeds: Array[int] = [4242, 7] as Array[int]

	var rows: Array[Dictionary] = await CompletionSampler.per_tier(PROBE_TIERS, seeds, PROBE_CAP)

	for row: Dictionary in rows:
		assert_eq(row["seeds"], seeds, "a row was measured on a different window")


## The report names the mixed row rather than leaving it blank — a blank cell reads as a number
## nobody took.
func test_the_mixed_row_is_labelled() -> void:
	var lines: Array[String] = (
		CompletionSampler
		. describe_per_tier(
			(
				[
					{
						"tier": &"ELITE",
						"completed": 3,
						"counted": 4,
						"rate": 0.75,
						"mean_turns": 21.0
					},
					{"tier": &"", "completed": 1, "counted": 4, "rate": 0.25, "mean_turns": 33.0},
				]
				as Array[Dictionary]
			)
		)
	)

	for line: String in lines:
		gut.p(line)
	assert_true("\n".join(lines).contains("ELITE"))
	assert_true("\n".join(lines).contains("mixed"), "the mixed row has no label")


## **The floor is not adjusted in this block**, which is the pass's own instruction: *"if the mixed
## rate drops below the floor, that is a finding about the floor as much as about the AI."*
##
## Both thresholds are pinned by value. The recorded history here is why: `MIN_COMPLETION_RATE` was
## lowered twice in response to a flapping gate, and `FIRST_WIN_CAP` replaced it precisely so a
## threshold on a small integer count stopped being the thing that moved. **A pass that authored a
## harder bout and then relaxed the bar would be measuring nothing.**
func test_neither_completion_threshold_was_adjusted_in_this_block() -> void:
	assert_eq(CompletionSampler.FIRST_WIN_CAP, 9, "the first-win cap moved")
	assert_eq(CompletionSampler.TURN_CAP, 100, "the turn horizon moved")
	assert_eq(CompletionSampler.SAMPLE_SEEDS, 8, "the sample size moved")
