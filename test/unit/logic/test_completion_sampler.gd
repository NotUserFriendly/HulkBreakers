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


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- what the sample draws ---------------------------------------------------


## **The seed list is the artifact.** A sample that cannot say which maps it asked
## about reports a number nobody can reproduce — BR45.03's whole lesson was that
## the aggregate hid which seeds mattered.
## taskblock-48 Pass C2: **canned records, no bouts at all.**
##
## "Every reported row names a seed that was drawn" is a property of the *report*, and a
## report does not care whether the missions behind it were real. taskblock-47 Pass E1
## already cut this from a full 8-bout sample to two; this cuts it to none.
##
## How many seeds a real sample draws is `draw_seeds`, asserted below without playing
## anything. That `sample` really is `run_seeds(draw_seeds(rng))` is asserted by the one
## end-to-end test at the bottom of this file.
func test_a_sample_reports_every_seed_it_drew() -> void:
	var report: Dictionary = BoutCorpus.canned_sample(3, 2)

	var seeds: Array = report["seeds"]
	assert_eq(seeds.size(), 5, "one entry per bout in the report")
	assert_eq(int(report["counted"]), seeds.size(), "and every one of them is counted")
	for row: Dictionary in report["rows"] as Array[Dictionary]:
		assert_has(seeds, row["seed"], "every reported row names a seed that was drawn")
	assert_eq(
		CompletionSampler.draw_seeds(_rng(12345)).size(),
		CompletionSampler.SAMPLE_SEEDS,
		"and a real sample draws one seed per bout it intends to run — without playing any"
	)


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
	# taskblock-47 Pass E1 cut this from three seeds to two; taskblock-48 Pass C2 cuts
	# it to one. **This is the file's only remaining pair of real runs**, and it has to
	# stay real: "the same seed list produces the same result twice" is a claim about
	# playing bouts, and canned records cannot make it. One seed is as good a witness
	# as fifty for a determinism property.
	var seeds: Array[int] = [0]

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

	# **At 0.56, the rate re-measured after taskblock-46's search-memory fix** — the
	# 0.54 this used to quote predates that change and is no longer what the planner
	# does.
	var measured: float = CompletionSampler.escalation_probability(0.56, 0.35)
	gut.p(
		(
			"escalation probability at the measured 0.56 with n=%d: %.3f (~1 run in %d)"
			% [CompletionSampler.SAMPLE_SEEDS, measured, int(round(1.0 / maxf(0.0001, measured)))]
		)
	)
	assert_gt(measured, 0.0, "a marginal planner must still escalate sometimes")
	# **This was 0.06 and the bar moved because what it costs moved, not because it
	# flapped.** Under taskblock-46 the escalation ran inside `run_tests.sh`, so an
	# escalation silently added ~330 s to a gate someone was waiting on and rarity was
	# worth paying for. taskblock-47 Pass C took it out of every gate: escalating now
	# costs a person deciding to run `tools/probe_seeds.gd`, so a sample that dips is
	# information rather than a tax, and the gate gets to be cheap instead.
	#
	# Recorded here rather than quietly edited because this project's documented habit
	# is raising a threshold when it goes red — the difference is that the *premise*
	# changed, and if it had not, the right move would have been a bigger `n`.
	assert_lt(measured, 0.15, "but rarely enough that a dip still means something")


## **A bigger sample must escalate LESS at the same true rate** — that is the whole
## reason for choosing one. Asserted as the relationship rather than as a pinned
## number, so re-sizing `SAMPLE_SEEDS` does not require editing an expectation.
func test_a_larger_sample_is_steadier_than_a_smaller_one() -> void:
	var ten: float = CompletionSampler.escalation_probability_for(10, 0.54, 0.35)
	var twenty: float = CompletionSampler.escalation_probability_for(20, 0.54, 0.35)

	assert_lt(twenty, ten, "twenty draws vary less than ten at the same true rate")
	assert_almost_eq(ten, 0.114, 0.005, "the figure taskblock-46 sized against")


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
##
## taskblock-48 Pass C2: fed canned records. The shape of a report — a header, one line
## per bout, a summary last — is a pure function of the records, and playing two real
## missions to check where a newline goes was cost with nothing behind it.
func test_describe_carries_the_seed_list_and_one_line_per_bout() -> void:
	var report: Dictionary = BoutCorpus.canned_sample(1, 1)

	var lines: Array[String] = CompletionSampler.describe(report)

	assert_true(lines[0].begins_with("seeds drawn:"), "the draw is stated first")
	assert_true(lines[0].contains("0") and lines[0].contains("1"))
	assert_eq(lines.size(), 4, "header, one line per seed, then the summary")
	assert_true(lines[lines.size() - 1].contains("completion"), "and a summary last")


# --- the in-window path reports the same numbers as the headless one ---------


## taskblock-46 Pass B's own acceptance, **merged with the non-mutation check at
## taskblock-47 Pass E2.**
##
## They invoked the verb separately and each paid for a full sample — 16 bouts and 8
## bouts, 295 s between them, to make two assertions about **one** invocation. For a
## bout test the fixture *is* the cost, so merging the pair is close to halving it.
##
## The assertion messages stay distinct so a failure still names which fact broke: a
## merged test that reports "something in here is wrong" has traded time for
## diagnosis, which is a worse deal than the time was worth.
func test_the_in_window_verb_reports_the_same_sample_and_changes_nothing() -> void:
	var grid: Grid = GridFixture.flat(8, 8)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(1, 1), 0)
	var state := CombatState.new(grid, [unit])
	var injector := BoutInjector.new(state)
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var cell_before: Vector2i = unit.cell
	var round_before: int = state.round_number

	await DebugVerbs._apply_sample_completion(injector, {}, {"rng_seed": 4242})
	state.combat_log.remove_sink(sink)

	# --- it reports in exactly the shape `describe` produces ---
	#
	# taskblock-48 Pass C2: **the second sample is gone.** This used to re-run the same
	# draw headlessly and compare the two renderings line for line, which doubled the
	# only expensive test left in the file — 16 bouts to establish that one formatter is
	# used by both callers.
	#
	# The guarantee is structural: `_apply_sample_completion` has no formatting of its
	# own, it emits `CompletionSampler.describe(result)` verbatim. So the check is that
	# the log carries `describe`'s shape over the verb's OWN sample — header naming the
	# seeds, one line per bout, a summary last — which holds if and only if the verb
	# went through that function. Re-playing eight missions to compare strings proved
	# the same thing at twice the price.
	var logged: Array[String] = []
	for event: LogEvent in sink.events_of_kind(&"completion_sample"):
		logged.append(event.text)
	assert_gt(logged.size(), 0, "the verb wrote its report into the combat log")
	assert_eq(
		logged.size(),
		CompletionSampler.SAMPLE_SEEDS + 2,
		"header, one line per bout it played, and a summary — describe's own shape"
	)
	assert_true(logged[0].begins_with("seeds drawn:"), "the draw is stated first")
	assert_true(logged[logged.size() - 1].contains("completion"), "and the summary is last")
	for i in range(1, logged.size() - 1):
		assert_true(logged[i].strip_edges().begins_with("seed "), "row %d names its seed" % i)
	# The rate in the summary must be arithmetic over the rows above it, which is the
	# part a formatter could get wrong without changing any line count.
	var completed := 0
	for i in range(1, logged.size() - 1):
		if logged[i].contains("EXTRACTED"):
			completed += 1
	assert_true(
		logged[logged.size() - 1].contains("%d/%d" % [completed, CompletionSampler.SAMPLE_SEEDS]),
		"the summary counts the rows it printed: %s" % logged[logged.size() - 1]
	)

	# --- and it is the one row in that table which mutates nothing ---
	assert_eq(unit.cell, cell_before, "the verb moved nothing")
	assert_eq(state.round_number, round_before, "and advanced nothing")
	assert_false(state.was_injected, "reporting is not an injection")
