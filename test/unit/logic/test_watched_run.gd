extends GutTest

## taskblock-58 Pass C.2: the wall-clock budget the watched-vs-headless comparison raises so it
## cannot trip. Ten minutes — far past any turn, so reaching it is a real defect rather than a busy
## machine. `test_a_watched_seed_matches_what_the_headless_path_reported` has why.
const UNREACHABLE_BUDGET_MSEC := 1000 * 60 * 10

## taskblock-47 Pass D: the watched run's sequencing and its report.
##
## The pass's real acceptance is the last test in this file: **a watched seed produces
## the same outcome the headless path reported for it.** If those two disagree, one of
## them is lying and everything built on the sampler — the completion floor, the
## budget, `BR45.03`'s whole argument — is suspect.
##
## Everything above it is the sequencing, which is here rather than in the overlay
## because CC cannot see the screen and "the seeds played in the order given" has to
## be answerable without one.

const TURN_CAP := 40


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


# --- the seed list ----------------------------------------------------------------


## **Order is the caller's.** Someone asking for `[11, 3, 7]` usually has a reason,
## and silently sorting it would hide which bout they were watching.
func test_seeds_play_in_the_order_given() -> void:
	var run: WatchedRun = WatchedRun.of([11, 3, 7] as Array[int])

	var seen: Array[int] = []
	while not run.is_done():
		seen.append(run.current_seed())
		run.record(&"EXTRACTED", 5)

	assert_eq(seen, [11, 3, 7] as Array[int])


func test_parsing_a_seed_list_is_tolerant_of_spacing() -> void:
	assert_eq(WatchedRun.parse_seeds("3, 7,11 "), [3, 7, 11] as Array[int])
	assert_eq(WatchedRun.parse_seeds(""), [] as Array[int])


## **A typo produces a shorter list, never a run against seed 0.** Silently reading
## "seven" as 0 would play a real bout nobody asked for and report it under a seed
## that was never typed.
func test_a_nonsense_entry_is_dropped_rather_than_read_as_zero() -> void:
	assert_eq(WatchedRun.parse_seeds("3, seven, 11"), [3, 11] as Array[int])
	assert_false(WatchedRun.parse_seeds("seven").has(0))


# --- stop, skip, re-watch ----------------------------------------------------------


## **Stopping keeps what the run learned.** The 15-of-20 case is exactly one where the
## useful information arrives at seed 5, so a stop that cleared the table would throw
## away the reason for watching.
func test_stopping_mid_run_keeps_the_results_so_far() -> void:
	var run: WatchedRun = WatchedRun.of([1, 2, 3, 4, 5] as Array[int])
	run.record(&"TERMINATED", 100)
	run.record(&"TERMINATED", 100)

	run.stop()

	assert_true(run.is_done(), "the run is over")
	assert_eq(run.results.size(), 2, "and it still knows what it saw")
	assert_eq(run.current_seed(), -1, "with nothing left current")


## Killing a run leaves no state behind that a fresh run would inherit — asserted by
## building a second run and checking it starts clean, rather than by inspecting the
## first, because "leaves nothing behind" is a claim about the next run.
func test_killing_a_run_leaves_nothing_behind() -> void:
	var first: WatchedRun = WatchedRun.of([1, 2] as Array[int])
	first.record(&"EXTRACTED", 12)
	first.stop()

	var second: WatchedRun = WatchedRun.of([1, 2] as Array[int])

	assert_eq(second.results, {}, "a new run starts with no results")
	assert_eq(second.index, 0)
	assert_false(second.stopped)
	assert_eq(second.current_seed(), 1)


## A skipped seed is recorded as skipped, **not dropped** — a missing row reads as a
## seed that passed, which is the opposite of what happened.
func test_a_skipped_seed_is_recorded_rather_than_dropped() -> void:
	var run: WatchedRun = WatchedRun.of([4, 5] as Array[int])

	run.skip()

	assert_eq(run.results[4]["outcome"], WatchedRun.SKIPPED)
	assert_eq(run.current_seed(), 5, "and it moved on")


## Re-watching clears the row it is about to replace. Keeping it would leave the table
## reporting an outcome from a bout nobody is looking at any more.
func test_rewatching_clears_the_row_it_replaces() -> void:
	var run: WatchedRun = WatchedRun.of([8, 9] as Array[int])
	run.record(&"TERMINATED", 100)
	run.rewatch_previous()

	assert_eq(run.current_seed(), 8, "back on the seed in question")
	assert_false(run.results.has(8), "and its old outcome is gone")

	run.record(&"EXTRACTED", 30)
	assert_eq(run.results[8]["outcome"], &"EXTRACTED", "the re-watch is what stands")


func test_rewatching_before_the_first_seed_does_nothing() -> void:
	var run: WatchedRun = WatchedRun.of([1, 2] as Array[int])

	run.rewatch_previous()

	assert_eq(run.current_seed(), 1, "still on the first seed, no wrap-around")


# --- what it says on screen --------------------------------------------------------


## **Say what is being checked.** A pass/fail against an unexplained criterion is
## something to interpret rather than read, and `TERMINATED` in particular reads like
## a crash when it means the opposite of anything happening.
func test_the_criteria_explain_every_outcome_by_name() -> void:
	var lines: Array[String] = WatchedRun.describe_criteria(100, 0.35)
	var text: String = "\n".join(lines)

	gut.p(text)
	for outcome: String in ["EXTRACTED", "TERMINATED", "STRANDED"]:
		assert_true(text.contains(outcome), "%s is explained" % outcome)
	assert_true(text.contains("100"), "the turn cap is stated")
	assert_true(text.contains("35"), "and so is the floor")


## Pending seeds appear in the table, so the run's length is visible from the first
## frame rather than growing mysteriously as it goes.
func test_the_table_shows_seeds_that_have_not_played_yet() -> void:
	var run: WatchedRun = WatchedRun.of([1, 2, 3] as Array[int])
	run.record(&"EXTRACTED", 12)

	var lines: Array[String] = run.describe_table()

	gut.p("\n".join(lines))
	assert_eq(lines.size(), 5, "header, three seeds, summary")
	assert_true(lines[1].contains("EXTRACTED"), "the played seed shows its outcome")
	assert_true(lines[3].contains(String(WatchedRun.PENDING)), "the unplayed one shows pending")
	assert_true(lines[2].begins_with(">"), "and the current seed is marked")


# --- the pass's real acceptance -----------------------------------------------------


## **If watched and headless disagree about the same seed, one of them is lying.**
##
## They cannot disagree by construction — both build through
## `CompletionSampler.build_for_seed`, which is why that was split out — and this
## asserts the construction actually holds. The watched path additionally runs with a
## `PlanPacer`, since that is what a rendered bout does, so this also pins that
## suspending a plan does not change what the bout decides.
##
## ## taskblock-58 Pass C.2: the budget is raised so it cannot trip
##
## **The same treatment, and the same reason, as `test_ai_batch_yield`.** The headless half of this
## comparison is `BoutCorpus`'s record, which was played with no pacer at all; the watched half runs
## with one. So the equality was quietly carrying a second claim — that planning fits inside
## `PlanPacer`'s wall-clock deadline — and **this file went red under full-suite load while passing
## in isolation**, which is what a wall-clock variable looks like from the outside.
##
## `BR58.01` owns the defect: the budget being wall-clock **at all** means the same seed produces
## different bouts on different hardware, or on the same hardware under different load. Raising it
## here restores what the test was built to assert — that *suspending* a plan changes nothing. The
## companion assertion below checks the raise was genuinely enough rather than assuming headroom.
##
## One seed, deliberately: the property is either true or it is not, and checking it
## twenty times would put this file in the expensive tier for no extra confidence.
func test_a_watched_seed_matches_what_the_headless_path_reported() -> void:
	# taskblock-50 Pass B: **the headless half comes from the corpus.** This played the
	# seed twice — once headless, once watched — to compare them, and the headless run is
	# precisely what `BoutCorpus` already played and recorded for the whole suite. Taking
	# its record instead of re-deriving it halves the test, and the comparison is
	# unchanged: it is still one headless result against one watched one, on one seed.
	var recorded: Array[Dictionary] = await BoutCorpus.rows()
	assert_gt(recorded.size(), 0, "sanity: the corpus played something to compare against")
	var headless: Dictionary = recorded[0]
	var map_seed: int = int(headless["seed"])

	var built: Dictionary = CompletionSampler.build_for_seed(map_seed)
	assert_eq(built.get("error", ""), "", "sanity: the watched path builds the same bout")
	var runner := BoutRunner.new(built["state"], built["mission"], CompletionSampler.TURN_CAP)
	# What a rendered bout does: slice the planning so the window keeps breathing.
	runner.pacer = PlanPacer.new()
	runner.pacer.budget_msec = UNREACHABLE_BUDGET_MSEC
	await runner.run_to_completion()
	var mission: MissionState = built["mission"]

	gut.p(
		(
			"seed %d — headless %s in %d, watched %s in %d"
			% [
				map_seed,
				headless["outcome_name"],
				headless["turns"],
				Enums.MissionOutcome.keys()[mission.outcome],
				runner.turns_taken
			]
		)
	)
	assert_eq(
		Enums.MissionOutcome.keys()[mission.outcome],
		headless["outcome_name"],
		"a watched seed must end the way the headless run said it did"
	)
	assert_eq(runner.turns_taken, int(headless["turns"]), "and take the same number of turns")
	assert_false(
		(runner.pacer as PlanPacer).aborted,
		"the raised budget must genuinely not be reached, or this is measuring wall-clock again"
	)
