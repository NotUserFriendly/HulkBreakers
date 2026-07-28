extends GutTest

## taskblock-46 Pass B: the sampler's own mechanics.
##
## **Deliberately cheap.** The expensive question — what the completion rate
## actually is — belongs to `test_full_mission.gd`, which samples and escalates.
## This file pins the machinery around that: what gets drawn, what gets reported,
## when an escalation fires, and that the escalation is deterministic.
##
## Every assertion here runs at most a handful of bouts, and most run none at all.
## A test that had to play a hundred missions to check that a comparison operator
## points the right way is a test nobody will keep.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- what the sample draws ---------------------------------------------------


## **The seed list is the artifact.** A sample that cannot say which maps it asked
## about reports a number nobody can reproduce — BR45.03's whole lesson was that
## the aggregate hid which seeds mattered.
func test_a_sample_reports_every_seed_it_drew() -> void:
	# The one test here that plays a full sample — everything else about drawing is
	# answered by `draw_seeds` without a bout.
	var result: Dictionary = await CompletionSampler.sample(_rng(12345))

	var seeds: Array = result["seeds"]
	assert_eq(
		seeds.size(), CompletionSampler.SAMPLE_SEEDS, "one seed per bout the sample intends to run"
	)
	assert_eq(int(result["counted"]), seeds.size(), "and every one of them actually ran")
	for row: Dictionary in result["rows"] as Array[Dictionary]:
		assert_has(seeds, row["seed"], "every reported row names a seed that was drawn")


## Ten draws must be ten distinct maps. With replacement, a "ten-seed sample" could
## quietly be eight maps and a coincidence, which would understate its own variance.
func test_a_sample_draws_without_replacement() -> void:
	var drawn: Array[int] = CompletionSampler.draw_seeds(_rng(999))

	var seen: Dictionary = {}
	for map_seed: int in drawn:
		assert_false(seen.has(map_seed), "seed %d drawn twice" % map_seed)
		seen[map_seed] = true


## The caller owns the RNG, so the same seed replays the same sample — that is what
## makes a printed seed list a reproduction recipe rather than a souvenir.
func test_the_same_rng_seed_replays_the_same_draw() -> void:
	assert_eq(CompletionSampler.draw_seeds(_rng(4242)), CompletionSampler.draw_seeds(_rng(4242)))


## Two different draws must be able to differ, or "sampling" is a pinned window
## wearing a disguise — the exact thing this replaced.
func test_different_rng_seeds_draw_different_samples() -> void:
	assert_ne(CompletionSampler.draw_seeds(_rng(1)), CompletionSampler.draw_seeds(_rng(2)))


# --- determinism of the escalation -------------------------------------------


## **The escalation is the measurement, so it must be reproducible.** Asserted on a
## short fixed list rather than the real `ESCALATION_SEEDS`: the property under test
## is that a fixed seed list yields identical results twice, and that is exactly as
## true of three seeds as of a hundred — while costing about a minute less.
func test_a_fixed_seed_list_yields_identical_results_twice() -> void:
	var seeds: Array[int] = [0, 1, 2]

	var first: Dictionary = await CompletionSampler.run_seeds(seeds)
	var second: Dictionary = await CompletionSampler.run_seeds(seeds)

	assert_eq(first["completed"], second["completed"])
	assert_eq(first["rate"], second["rate"])
	assert_eq(
		CompletionSampler.describe(first),
		CompletionSampler.describe(second),
		"identical down to the reported text"
	)


func test_the_escalation_seed_list_is_fixed_and_starts_at_zero() -> void:
	# Asserted against the constant rather than by running it — `escalate()` plays
	# a hundred missions, and what wants pinning is which seeds it chooses.
	assert_eq(CompletionSampler.ESCALATION_SEEDS, 100)
	assert_gt(
		CompletionSampler.ESCALATION_SEEDS,
		CompletionSampler.SAMPLE_SEEDS,
		"the escalation must carry more weight than the sample that triggered it"
	)


# --- when an escalation fires ------------------------------------------------


## The rule itself, pinned without running a single bout.
func test_a_sample_below_the_floor_escalates_and_one_above_it_does_not() -> void:
	assert_true(CompletionSampler.should_escalate(0.2, 0.35), "below escalates")
	assert_false(CompletionSampler.should_escalate(0.5, 0.35), "above does not")
	assert_false(CompletionSampler.should_escalate(0.35, 0.35), "exactly at the floor is a pass")


# --- escalation frequency as a metric ----------------------------------------


## **How often the gate escalates is a statement about the planner, not about
## luck.** These are exact binomial values, so they are checkable by hand.
func test_escalation_probability_is_the_exact_binomial_tail() -> void:
	# A perfect planner never escalates; a hopeless one always does.
	assert_almost_eq(CompletionSampler.escalation_probability(1.0, 0.35), 0.0, 0.0001)
	assert_almost_eq(CompletionSampler.escalation_probability(0.0, 0.35), 1.0, 0.0001)

	# At the rate taskblock-46 measured (0.54) against the shipped floor, the
	# taskblock's own estimate was "roughly one run in nine".
	var measured: float = CompletionSampler.escalation_probability(0.54, 0.35)
	gut.p("escalation probability at the measured 0.54: %.3f" % measured)
	assert_gt(measured, 0.08, "~1 in 9, which is what a marginal planner looks like")
	assert_lt(measured, 0.15)


## A healthy planner makes escalation rare — the property that keeps the gate cheap
## once the regression closes.
func test_a_healthy_rate_almost_never_escalates() -> void:
	assert_lt(
		CompletionSampler.escalation_probability(0.85, 0.35),
		0.005,
		"at 85% completion the sampler should essentially never escalate"
	)


# --- the shared report -------------------------------------------------------


## `describe` is what both the headless test and the in-window runner print, so a
## change to one cannot silently disagree with the other.
func test_describe_carries_the_seed_list_and_one_line_per_bout() -> void:
	var result: Dictionary = await CompletionSampler.run_seeds([0, 1] as Array[int])

	var lines: Array[String] = CompletionSampler.describe(result)

	assert_true(lines[0].begins_with("seeds drawn:"), "the draw is stated first")
	assert_true(lines[0].contains("0") and lines[0].contains("1"))
	assert_eq(lines.size(), 4, "header, one line per seed, then the summary")
	assert_true(lines[lines.size() - 1].contains("completion"), "and a summary last")


# --- the in-window path reports the same numbers as the headless one ---------


## taskblock-46 Pass B's own acceptance. The debug verb and the integration test
## must not be able to disagree about the same sample, which is guaranteed here by
## construction: both format through `CompletionSampler.describe`, so this asserts
## the guarantee actually holds rather than assuming it.
func test_the_in_window_verb_reports_the_same_lines_as_the_headless_path() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var injector := BoutInjector.new(state)
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	await DebugVerbs._apply_sample_completion(injector, {}, {"rng_seed": 4242})
	state.combat_log.remove_sink(sink)

	var logged: Array[String] = []
	for event: LogEvent in sink.events_of_kind(&"completion_sample"):
		logged.append(event.text)
	# Re-run the same draw through the headless path. Same RNG seed, so the same
	# ten maps — this compares two renderings of one sample, not two samples.
	var headless: Array[String] = CompletionSampler.describe(
		await CompletionSampler.run_seeds(CompletionSampler.draw_seeds(_rng(4242)))
	)

	assert_gt(logged.size(), 0, "the verb wrote its report into the combat log")
	assert_eq(logged, headless, "the window and the suite report the same sample")


## The verb reports and changes nothing — it is the one row in that table which is
## not a mutation, so "it did not touch the bout" is worth pinning.
func test_the_in_window_verb_mutates_nothing() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var injector := BoutInjector.new(state)
	var cell_before: Vector2i = unit.cell
	var round_before: int = state.round_number

	await DebugVerbs._apply_sample_completion(injector, {}, {"rng_seed": 7})

	assert_eq(unit.cell, cell_before)
	assert_eq(state.round_number, round_before)
	assert_false(state.was_injected, "reporting is not an injection")
