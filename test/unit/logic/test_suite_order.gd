extends GutTest

## taskblock-50 Pass E1: failure-first ordering.
##
## The ordering itself is a pure function over a script list and a history, which is why
## it lives in `SuiteOrder` rather than inside the runner — the runner's own behaviour is
## awkward to test, and this is the part with the rules in it.
##
## **The load-bearing property is that it is a permutation.** The pass forbids skipping
## outright: an indicator that passes while the thing it indicates is broken makes the
## suite greener than the code, and this project has hit that four blocks running. So
## "nothing is dropped" is asserted directly rather than left to follow from the
## implementation.

const SCRIPTS: Array[String] = [
	"res://test/a.gd",
	"res://test/b.gd",
	"res://test/c.gd",
	"res://test/d.gd",
]


func test_a_frequently_failing_script_goes_first() -> void:
	var history := {
		"res://test/c.gd": {"fails": 5, "runs": 10, "last_failed_run": 9},
		"res://test/a.gd": {"fails": 1, "runs": 10, "last_failed_run": 3},
	}

	var ordered: Array[String] = SuiteOrder.rank(SCRIPTS, history)

	assert_eq(ordered[0], "res://test/c.gd", "the worst offender runs first")
	assert_eq(ordered[1], "res://test/a.gd", "then the next")


## **Nothing is skipped, ever.** The set that goes in is the set that comes out.
func test_ordering_is_a_permutation_and_never_drops_a_script() -> void:
	var history := {"res://test/d.gd": {"fails": 3, "runs": 3, "last_failed_run": 3}}

	var ordered: Array[String] = SuiteOrder.rank(SCRIPTS, history)

	assert_eq(ordered.size(), SCRIPTS.size(), "same count out as in")
	for path: String in SCRIPTS:
		assert_has(ordered, path, "%s survived the ordering" % path)


## An empty history must reproduce the incoming order exactly — a fresh clone has to run
## the same suite in the same sequence as before this existed.
func test_an_empty_history_changes_nothing() -> void:
	assert_eq(SuiteOrder.rank(SCRIPTS, {}), SCRIPTS, "no history, no reordering")


## Among equals the incoming order survives, so an unchanged history means an unchanged
## run and a diff of two run logs shows only what the history really moved.
func test_ties_keep_the_incoming_order() -> void:
	var history := {
		"res://test/b.gd": {"fails": 2, "runs": 5, "last_failed_run": 4},
		"res://test/d.gd": {"fails": 2, "runs": 5, "last_failed_run": 4},
	}

	var ordered: Array[String] = SuiteOrder.rank(SCRIPTS, history)

	assert_eq(ordered[0], "res://test/b.gd", "equal records keep discovery order")
	assert_eq(ordered[1], "res://test/d.gd")


## More recent beats older when the counts match — a file that failed last run is the
## better bet than one that failed five runs ago.
func test_a_more_recent_failure_outranks_an_older_one_at_the_same_count() -> void:
	var history := {
		"res://test/b.gd": {"fails": 2, "runs": 5, "last_failed_run": 2},
		"res://test/d.gd": {"fails": 2, "runs": 5, "last_failed_run": 8},
	}

	assert_eq(SuiteOrder.rank(SCRIPTS, history)[0], "res://test/d.gd")


func test_folding_a_run_records_failures_and_passes_alike() -> void:
	var folded: Dictionary = SuiteOrder.fold({}, {"res://test/a.gd": 0, "res://test/b.gd": 2}, 7)

	assert_eq(int(folded["res://test/b.gd"]["fails"]), 1, "a failing script is counted")
	assert_eq(int(folded["res://test/b.gd"]["last_failed_run"]), 7, "and stamped with the run")
	assert_eq(int(folded["res://test/a.gd"]["fails"]), 0, "a passing one is not")
	assert_eq(int(folded["res://test/a.gd"]["runs"]), 1, "but its run still counts")
	assert_eq(int(folded["__run"]), 7)


## **A fixed file has to sink again.** `runs` climbing while `fails` holds is what lets a
## once-flaky file fall back down the order instead of sitting at the top forever, so the
## history has to keep counting runs for scripts that pass.
func test_a_script_that_stops_failing_stops_being_promoted() -> void:
	var history: Dictionary = SuiteOrder.fold({}, {"res://test/a.gd": 1}, 1)
	for run in range(2, 6):
		history = SuiteOrder.fold(history, {"res://test/a.gd": 0}, run)

	var record: Dictionary = history["res://test/a.gd"]
	assert_eq(int(record["fails"]), 1, "the single failure is remembered")
	assert_eq(int(record["runs"]), 5, "against five runs, which is what makes it stale")
	assert_eq(int(record["last_failed_run"]), 1, "and it has not failed since")


func test_the_run_number_advances_from_the_history() -> void:
	assert_eq(SuiteOrder.next_run_number({}), 1, "a missing history starts at one")
	assert_eq(SuiteOrder.next_run_number({"__run": 12}), 13)


## The bookkeeping key must not be mistaken for a script path — it would be ranked and
## then handed to GUT as a test to run.
func test_the_run_counter_is_not_reported_as_a_tracked_path() -> void:
	var history: Dictionary = SuiteOrder.fold({}, {"res://test/a.gd": 1}, 3)

	var tracked: Array[String] = SuiteOrder.tracked_paths(history)

	assert_eq(tracked, ["res://test/a.gd"] as Array[String])
	assert_false(tracked.has("__run"), "the counter is not a script")
