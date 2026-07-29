class_name TestExitCodeProbe
extends GutTest

## taskblock-48 Pass B: **a test that fails on demand, so the runner's exit code can be
## checked against a real failing run.**
##
## ## Why this file exists instead of a temporary one
##
## `test_run_suite.gd` and `test_suite_run.gd` both need a genuinely failing suite to
## prove that failure propagates. The obvious way is to write a throwaway test file,
## run it, and delete it — and that is what they did, until it broke the full gate for
## the supervisor with `Cannot open file 'test_temporary_deliberate_failure.gd'`.
##
## **The race is not fixable by tidier cleanup.** The subprocess runs
## `godot --import`, which writes a `.uid` beside the script on its own schedule. If
## that lands after the test has deleted the pair, the `.uid` is orphaned; the next
## run's import sees it, tries to open a `.gd` that no longer exists, and the whole
## gate dies. Nothing the deleting side does can win a race against a process it has
## already stopped waiting for.
##
## So the file is permanent and its *behaviour* is what varies. Nothing is created,
## nothing is deleted, and there is no `.uid` to orphan.
##
## **It is green in every ordinary run**, including the gate — which is the property
## that makes it safe to keep in the tree.

## Named here and referenced by the tests that use it, rather than duplicated as a
## literal — a magic string in two files is a magic string that eventually disagrees
## with itself, and the failure mode would be a test that quietly stops proving
## anything because it is setting a variable nobody reads.
##
## Set by the tests that need a failing run. Deliberately specific: a vague name like
## `FAIL` would eventually be set by something else and turn the suite red for a
## reason nobody could find.
const FORCE_FAILURE_ENV := "HULK_FORCE_TEST_FAILURE"


func test_the_probe_fails_only_when_it_is_asked_to() -> void:
	if OS.get_environment(FORCE_FAILURE_ENV) == "":
		assert_true(true, "no failure requested — this is the ordinary case")
		return
	assert_true(
		false,
		(
			(
				"deliberate failure, requested via %s — if you are seeing this outside "
				+ "test_run_suite.gd or test_suite_run.gd, that variable leaked"
			)
			% FORCE_FAILURE_ENV
		)
	)
