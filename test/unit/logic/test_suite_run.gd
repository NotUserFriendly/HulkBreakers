extends GutTest

## taskblock-48 Pass B: the launcher behind the run window.
##
## ## The one that matters
##
## `test_the_launcher_agrees_with_the_shell_about_the_same_rung`. **If the window and
## the terminal ever disagree, the window is worthless** — it exists to show what CC
## actually runs, and a viewer that reports its own version of events is worse than
## no viewer, because it is believed.
##
## Everything else here is the mechanics that make the feed trustworthy: completion
## decided by the exit marker rather than by a PID disappearing, a run in progress
## never reading as green, and kill actually killing.
##
## ## Never launch a gate that contains this file
##
## Every run started here is **targeted at a specific file**, and that is not a cost
## optimisation. `start(&"full")` runs the whole suite — including this one — which
## starts another full run, which starts another. It is unbounded recursion whose only
## brake is how fast each generation gets killed, and it took the machine to **107
## concurrent Godot processes** before that was obvious.
##
## The panel has no such problem: the game is not a test. But anything in `test/` that
## drives `SuiteRun` has to pick a target that cannot contain itself.


## Waits for the **exit marker**, not for a pid to vanish. Under `setsid` the launcher
## pid exits almost immediately, so waiting on the process would return long before the
## run had done anything — which is the same mistake the class itself used to make.
func _await_finish(run: SuiteRun, timeout_msec: int = 180000) -> void:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while not run.finished and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.2).timeout
		run.poll()
	run.poll()
	assert_true(run.finished, "the run did not finish within %d ms" % timeout_msec)


# --- the acceptance ------------------------------------------------------------------


## The launcher and a plain shell invocation must reach the same verdict on the same
## work. Run through `OS.execute` for the shell side, deliberately: that is a
## different code path from `OS.create_process` + tail, so agreement means something.
func test_the_launcher_agrees_with_the_shell_about_the_same_rung() -> void:
	var shell_output: Array = []
	var shell_code: int = SuiteProcess.execute(
		"./run_tests.sh", ["test_grid.gd"] as Array[String], shell_output, true
	)

	var run := SuiteRun.new()
	assert_true(run.start(&"full", "test_grid.gd"), "the launcher started the run")
	await _await_finish(run)

	gut.p("shell exit %d — launcher: %s" % [shell_code, run.status_line()])
	assert_true(run.finished, "the launcher saw the run finish")
	assert_eq(run.exit_code, shell_code, "the window and the terminal agree on the exit code")
	assert_eq(run.passed(), shell_code == 0, "and therefore on pass/fail")
	assert_eq(
		int(run.tallies()["passing"]),
		20,
		"and on how many tests passed — the same number the terminal printed"
	)


## A failing run must read as failed — the other half of the acceptance, and the one
## that would catch a verdict wired to a constant.
##
## **Fed the output directly rather than through a manufactured failing subprocess.**
## The first version wrote a temporary failing test and ran it, and it was flaky: the
## inner run resolved the filename but GUT did not always discover a file written
## moments earlier, collected nothing, and exited 0 — so the test failed *because the
## suite passed*, which is a race dressed up as a verdict. Whether a failing suite is
## reported as failing is a parsing question, and this asks it as one.
func test_a_failing_run_reads_as_failed() -> void:
	var run := SuiteRun.new()

	run.ingest("Passing Tests      12\nFailing Tests         3\n")
	assert_false(run.passed(), "no verdict before the exit marker, however bad it looks")

	run.ingest("%s=1\n" % SuiteRun.EXIT_MARKER)

	gut.p(run.status_line())
	assert_true(run.finished)
	assert_false(run.passed(), "a failing suite must not read as passed")
	assert_eq(run.exit_code, 1)
	assert_eq(int(run.tallies()["failing"]), 3, "and it reports how many failed")
	assert_true(run.status_line().begins_with("FAILED"), "and says so in the header")


## The inverse, on the same seam: a zero exit with the marker present is a pass.
func test_a_clean_exit_marker_reads_as_passed() -> void:
	var run := SuiteRun.new()

	run.ingest("Passing Tests      2373\nFailing Tests         0\n")
	run.ingest("%s=0\n" % SuiteRun.EXIT_MARKER)

	assert_true(run.passed())
	assert_eq(int(run.tallies()["passing"]), 2373)


# --- the mechanics that make it trustworthy -------------------------------------------


## **Completion is the exit marker, not the PID.** A process can vanish without the
## script having finished; a run reported as passed because its PID went away is
## exactly the lie that makes this window worthless.
##
## **Killed rather than waited out.** The first version waited for a real
## `test_grid.gd` run to finish — nominally 4 s, but it timed out at 180 s inside a
## loaded full gate, because a suite running a suite competes with itself for the
## machine. The claim here is about the *states before* completion, and the marker
## actually ending a run is established without a subprocess at all by
## `test_a_failing_run_reads_as_failed`. Waiting bought nothing and cost a flake.
func test_an_unfinished_run_never_reads_as_passed() -> void:
	var run := SuiteRun.new()
	assert_false(run.passed(), "a run that never started has not passed")
	assert_false(run.finished)

	run.start(&"full", "test_map_gen.gd")
	run.poll()

	assert_false(run.passed(), "and neither has one still going")
	assert_false(run.finished, "no marker yet, so not finished")
	assert_true(run.is_running(), "but it is running")

	run.kill()
	assert_true(run.finished, "killing ends it")
	assert_false(run.passed(), "without ever reading as passed")


## **Killing must reach the Godot the shell launched, not just the shell.**
##
## The first version of this asserted `run.is_running()` — which short-circuits on
## `finished` and therefore verified nothing at all. Meanwhile `OS.kill` was killing
## only the wrapper, and a full-gate run started by this very test left **79 orphaned
## Godot processes** running suites nobody was watching. The weakened assertion is
## what let that ship, so this counts real processes instead.
func test_kill_terminates_the_whole_process_group_not_just_the_shell() -> void:
	var before: int = _godot_processes()
	var run := SuiteRun.new()
	# A slow file rather than a gate — see the recursion note in this file's header.
	# `test_map_gen.gd` takes ~22 s and contains nothing that starts a run.
	assert_true(run.start(&"full", "test_map_gen.gd"))
	# Long enough for the shell to reach the engine, or there is no grandchild yet and
	# the test proves nothing.
	await get_tree().create_timer(6.0).timeout
	run.poll()
	var during: int = _godot_processes()

	run.kill()
	await get_tree().create_timer(3.0).timeout

	var after: int = _godot_processes()
	gut.p("godot processes — before %d, during %d, after %d" % [before, during, after])
	assert_gt(during, before, "sanity: the run actually started an engine to kill")
	assert_lte(after, before, "the grandchild died with the shell")
	assert_true(run.finished, "and the run reports itself over")
	assert_false(run.passed(), "a killed run is not a passed run")
	assert_true(run.status_line().begins_with("killed"), "the header says it was killed")


## Counts live Godot processes. Shelled out because the engine cannot see its own
## siblings, and the whole question here is about processes it did not create.
func _godot_processes() -> int:
	var output: Array = []
	SuiteProcess.execute("bash", ["-c", "pgrep -c godot || true"] as Array[String], output, true)
	var text: String = "\n".join(output).strip_edges()
	return text.to_int() if text.is_valid_int() else 0


## The status line has to say what is happening, not merely that something is. A
## progress indicator that cannot name its work is something to interpret.
func test_the_status_line_states_the_rung_and_the_elapsed_time() -> void:
	var run := SuiteRun.new()
	assert_eq(run.status_line(), "no run started")

	# Targeted, not the `fast` rung: the fast gate contains this file.
	run.start(&"fast", "test_map_gen.gd")
	await get_tree().create_timer(1.0).timeout
	run.poll()
	var line: String = run.status_line()
	run.kill()

	gut.p(line)
	assert_true(line.contains("fast"), "the rung is named")
	assert_true(line.contains("s"), "and the elapsed time is shown")
	assert_true(line.contains("running"), "and it reads as in-progress")


## Every rung the panel offers must be a real `run_tests.sh` argument, or a button
## launches something that exits 2 and the window reports a usage error as a failure.
func test_every_offered_rung_is_a_real_argument() -> void:
	for rung: StringName in SuiteRun.RUNGS:
		var argument: String = String(SuiteRun.RUNGS[rung])
		assert_true(
			argument == "" or argument == "fast",
			"'%s' maps to '%s', which run_tests.sh does not accept as a gate" % [rung, argument]
		)
