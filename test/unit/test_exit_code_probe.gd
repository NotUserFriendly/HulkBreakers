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

## The seed the forced failure replays. Any real bout would do; this one is fixed so
## the demonstration is the same every time.
const DEMO_SEED := 7


## **This probe has a visual form on purpose.**
##
## It is the one test that fails on demand, so it is the one that demonstrates the
## whole path — run, fail, offer, replay, play. Without a handle the "force a failure"
## toggle produced a failure with nothing to show, which proved the failure half and
## left the replay half exactly as unverifiable as before.
##
## A seed bout rather than a bare map: two units that move and shoot answers "is
## anything happening" in a way a static board cannot. The map-generation handles are
## unit-less by nature — the map *is* what failed there — so they render a board that
## correctly does not move.
static func replay_handle_for(test_name: String) -> ReplayHandle:
	if test_name != "test_the_probe_fails_only_when_it_is_asked_to":
		return null
	return ReplayHandle.from_seed(DEMO_SEED)


func test_the_probe_fails_only_when_it_is_asked_to() -> void:
	if OS.get_environment(FORCE_FAILURE_ENV) == "":
		assert_true(true, "no failure requested — this is the ordinary case")
		return
	assert_true(
		false,
		(
			(
				"deliberate failure, requested via %s. This is what the run panel's"
				+ " 'force a failure' toggle does; unset it for an ordinary run"
			)
			% FORCE_FAILURE_ENV
		)
	)
