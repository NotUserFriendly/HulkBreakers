extends GutTest

## taskblock-48 Pass B2: replay handles, and which failures have a visual form.
##
## ## The one that matters
##
## `test_a_handle_rebuilds_the_fixture_its_test_built`. **A replay showing something
## other than what failed is worse than no replay** — it is a confident answer to the
## wrong question, and the person looking at it has no way to tell.
##
## The rest is the filter: a test with no handle is skipped rather than erroring,
## because "nothing to show" is the correct answer for most of the suite and treating
## it as a fault would bury the few that do have something.


## taskblock-48 Pass B2: this file declares a handle for its own sake — the mechanism
## should be exercised by something other than the two files that shipped with it.
static func replay_handle_for(test_name: String) -> ReplayHandle:
	if test_name != "test_a_handle_rebuilds_the_fixture_its_test_built":
		return null
	return ReplayHandle.from_seed(11)


## taskblock-47 Pass C: this file builds bouts, so the fast gate skips it. The list it
## is on is checked against the profile's own bout counter every run — see `SuiteTier`.
##
## **Untyped on purpose, against this project's static-typing rule.** GUT declares
## `func should_skip_script():` with no return type, and Godot treats an override that
## adds `-> Variant` as a signature mismatch.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


# --- the acceptance --------------------------------------------------------------


## **A handle must rebuild what its test built, not something like it.**
##
## Asserted by building the fixture the way the test does and the way the handle does,
## then comparing the boards cell for cell and unit for unit. Comparing a summary — a
## seed, a size — would pass for two different maps that happened to agree about the
## thing being compared.
func test_a_handle_rebuilds_the_fixture_its_test_built() -> void:
	var map_seed := 11
	var directly: Dictionary = CompletionSampler.build_for_seed(map_seed)
	assert_eq(directly.get("error", ""), "", "sanity: the fixture builds")

	var handle: ReplayHandle = ReplayHandle.from_seed(map_seed)
	var replayed: Dictionary = handle.build()

	assert_false(replayed.is_empty(), "the handle rebuilt something")
	var a: CombatState = directly["state"]
	var b: CombatState = replayed["state"]
	assert_eq(b.grid.width, a.grid.width, "same board width")
	assert_eq(b.grid.rows, a.grid.rows, "same board height")
	assert_eq(b.units.size(), a.units.size(), "same number of units")
	var mismatched := 0
	for y in range(a.grid.rows):
		for x in range(a.grid.width):
			var cell := Vector2i(x, y)
			if a.grid.blockers.has(cell) != b.grid.blockers.has(cell):
				mismatched += 1
			elif not is_equal_approx(
				UnitGeometry.true_height_for_cell(cell, a.grid),
				UnitGeometry.true_height_for_cell(cell, b.grid)
			):
				mismatched += 1
	gut.p("%d of %d cells differ" % [mismatched, a.grid.width * a.grid.rows])
	assert_eq(mismatched, 0, "the replayed board is the board the test had")
	for i in range(a.units.size()):
		assert_eq(b.units[i].cell, a.units[i].cell, "unit %d starts where it started" % i)


## A different seed must produce a different board, or the comparison above would pass
## for any two maps and prove nothing.
func test_a_different_seed_rebuilds_a_different_fixture() -> void:
	var first: CombatState = ReplayHandle.from_seed(11).build()["state"]
	var second: CombatState = ReplayHandle.from_seed(12).build()["state"]

	var differences := 0
	for y in range(first.grid.rows):
		for x in range(first.grid.width):
			if first.grid.blockers.has(Vector2i(x, y)) != second.grid.blockers.has(Vector2i(x, y)):
				differences += 1
	assert_gt(differences, 0, "two seeds must not build the same map")


# --- the filter -------------------------------------------------------------------


## **A test with no handle is skipped, not an error.** Most of the suite has nothing
## spatial to show, and reporting that as a fault would bury the few that do.
func test_a_test_without_a_handle_is_skipped_rather_than_erroring() -> void:
	var handle: ReplayHandle = ReplayCatalog.handle_for(
		"res://test/unit/logic/test_grid.gd", "test_anything"
	)

	assert_null(handle, "a script with no replay_handle_for simply has no visual form")


## A script that declares handles for some tests and not others must answer for each
## one separately — the filter is per test, not per file.
func test_a_declared_script_still_answers_null_for_its_unhandled_tests() -> void:
	var covered: ReplayHandle = ReplayCatalog.handle_for(
		"res://test/unit/logic/test_replay_handle.gd",
		"test_a_handle_rebuilds_the_fixture_its_test_built"
	)
	var uncovered: ReplayHandle = ReplayCatalog.handle_for(
		"res://test/unit/logic/test_replay_handle.gd",
		"test_a_different_seed_rebuilds_a_different_fixture"
	)

	assert_not_null(covered, "the declared test has a handle")
	assert_null(uncovered, "and its neighbour does not")


func test_a_missing_script_is_skipped_rather_than_erroring() -> void:
	assert_null(ReplayCatalog.handle_for("res://test/unit/nope.gd", "test_x"))


## **The offer is bounded, and "show all" is a deliberate second choice.** The first
## few failures are where the pattern is; sitting through eleven is not the default.
func test_the_offer_is_capped_and_show_all_is_opt_in() -> void:
	var failures: Array = []
	for i in range(8):
		(
			failures
			. append(
				{
					"script": "res://test/unit/logic/test_replay_handle.gd",
					"test": "test_a_handle_rebuilds_the_fixture_its_test_built",
				}
			)
		)

	assert_eq(ReplayCatalog.handles_for(failures).size(), ReplayCatalog.DEFAULT_LIMIT, "capped")
	assert_lt(ReplayCatalog.DEFAULT_LIMIT, failures.size(), "sanity: the cap is doing something")
	assert_eq(ReplayCatalog.handles_for(failures, 0).size(), 8, "show-all takes an explicit 0")
	assert_eq(ReplayCatalog.replayable_count(failures), 8, "and the true count is reportable")


## Failures with nothing to show do not consume the cap — otherwise three dictionary
## assertions at the top of the list would hide every replayable failure behind them.
func test_unreplayable_failures_do_not_consume_the_cap() -> void:
	var failures: Array = [
		{"script": "res://test/unit/logic/test_grid.gd", "test": "test_a"},
		{"script": "res://test/unit/logic/test_grid.gd", "test": "test_b"},
		{
			"script": "res://test/unit/logic/test_replay_handle.gd",
			"test": "test_a_handle_rebuilds_the_fixture_its_test_built",
		},
	]

	assert_eq(ReplayCatalog.handles_for(failures, 1).size(), 1, "the replayable one is found")


## A handle whose builder fails reports nothing rather than a half-built board.
## "Cannot rebuild this" has to be distinguishable from "here it is".
func test_a_handle_that_cannot_build_returns_nothing() -> void:
	var broken: ReplayHandle = ReplayHandle.of(
		"broken", "broken", func() -> Dictionary: return {"error": "no"}
	)

	assert_true(broken.build().is_empty())
	assert_true(ReplayHandle.new().build().is_empty(), "and so does one with no builder")


# --- the fold ----------------------------------------------------------------------


## Seeds and non-seed handles queue in the same run with the same controls — B2's
## "one replayer, not two". A map handle has no seed, and saying so honestly is what
## keeps `current_seed()` meaningful for the ones that do.
func test_seed_and_non_seed_handles_share_one_run() -> void:
	var mixed: Array[ReplayHandle] = [
		ReplayHandle.from_seed(4),
		ReplayHandle.of("map:x", "map seed 0", func() -> Dictionary: return {}),
	]
	var run: WatchedRun = WatchedRun.of_handles(mixed)

	assert_eq(run.current_seed(), 4, "a seed handle reports its seed")
	run.record(&"EXTRACTED", 12)
	assert_eq(run.current_seed(), -1, "a map handle honestly has none")
	assert_eq(run.current().label, "map seed 0", "but still has a label for the table")
	run.skip()
	assert_true(run.is_done())
	assert_eq(run.results[4]["outcome"], &"EXTRACTED", "results key on the handle's key")
	assert_eq(run.results["map:x"]["outcome"], WatchedRun.SKIPPED)
