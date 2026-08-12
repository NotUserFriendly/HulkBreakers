extends GutTest

## taskblock-48 Pass A: **the runner, and the three rungs on top of it.**
##
## ## The one that matters
##
## `test_the_runner_fails_the_process_when_a_test_fails`. Before this block there were
## two entry points into one suite — `gut_cmdln.gd`, which passed `-gexit`, and
## `tools/run_suite.gd`, which collected work counts and then called `quit(0)`
## unconditionally after writing its JSON. **Only one of them failed the build.**
##
## A runner that reports counts beautifully and exits 0 on a red suite is worse than
## no runner at all, so this is asserted against a real failing test in a real
## subprocess rather than by reading the source. It is the slowest test in this file
## and the only one worth its cost.
##
## ## Why these shell out
##
## The rungs are shell behaviour — argument resolution, which steps get skipped, the
## exit code — and none of it exists inside the engine. Asserting it any other way
## would be asserting a second implementation of the same logic, which is the trap
## `docs/00` names for view maths and which applies just as well here.


## Runs `./run_tests.sh` with `args` and returns `{"code": int, "out": String}`.
func _run(args: Array[String]) -> Dictionary:
	var output: Array = []
	var code: int = SuiteProcess.execute("./run_tests.sh", args, output, true)
	return {"code": code, "out": "\n".join(output)}


# --- the exit code -----------------------------------------------------------------


## **The pass's real acceptance.** A deliberately failing test, run through the real
## script, must fail the process.
##
## Uses `test_exit_code_probe.gd`, a permanent file that fails only when asked. The
## first version wrote a throwaway test and deleted it, which broke the full gate for
## the supervisor: the subprocess's import step writes a `.uid` on its own schedule,
## so deleting the pair can orphan it, and the next run dies trying to open a script
## that is not there. See that file's header — the race cannot be cleaned up around.
func test_the_runner_fails_the_process_when_a_test_fails() -> void:
	var probe: String = TestExitCodeProbe.FORCE_FAILURE_ENV
	var restore: String = OS.get_environment(probe)
	# Restored rather than cleared: `OS.set_environment` is process-wide, and clearing
	# it to "" once switched the fast gate off for every file GUT had not yet reached
	# (taskblock-47 Pass C).
	OS.set_environment(probe, "1")

	var result: Dictionary = _run(["test_exit_code_probe.gd"] as Array[String])

	OS.set_environment(probe, restore)

	gut.p(String(result["out"]).substr(maxi(0, String(result["out"]).length() - 300)))
	assert_eq(int(result["code"]), 1, "a failing test must fail the process")
	assert_true(String(result["out"]).contains("1 failure(s)"), "and the count says so")


## The other direction on the same probe: with nothing asking it to fail, the identical
## invocation passes. Without this, a runner that always returned 1 would look correct.
##
## **The variable is cleared for the child, not assumed absent.** `OS.execute` hands
## the child this process's environment, so running the whole gate under
## `HB_FORCE_TEST_FAILURE=1` — which is exactly what the panel's toggle does — made
## this test's subprocess inherit it and fail. A test that only passes when nobody is
## exercising the feature it belongs to is not a test.
func test_the_same_probe_passes_when_nothing_asks_it_to_fail() -> void:
	var probe: String = TestExitCodeProbe.FORCE_FAILURE_ENV
	var restore: String = OS.get_environment(probe)
	OS.set_environment(probe, "")

	var result: Dictionary = _run(["test_exit_code_probe.gd"] as Array[String])

	OS.set_environment(probe, restore)
	assert_eq(int(result["code"]), 0, "the probe is green unless asked otherwise")
	assert_true(String(result["out"]).contains("0 failure(s)"))


## **Five facts about one invocation, and one subprocess to establish them.**
##
## Each of these used to spawn its own run of `./run_tests.sh test_grid.gd` — five
## processes, each paying the ~3.7 s floor, to assert five things about a run that is
## identical every time. **Here the subprocess IS the fixture cost**, exactly as the
## bout was in taskblock-47 Pass E2, and the same merge applies.
##
## The assertion messages stay distinct so a failure still names which fact broke.
func test_a_passing_targeted_run_exits_zero_reports_its_cost_and_writes_nothing() -> void:
	var profile_before: String = FileAccess.get_file_as_string("res://test/suite_profile.json")
	assert_ne(profile_before, "", "sanity: the profile is committed and readable")

	var result: Dictionary = _run(["test_grid.gd"] as Array[String])
	var text: String = result["out"]

	# --- it passes, and says so ---
	assert_eq(int(result["code"]), 0, "a passing run exits zero")
	assert_true(text.contains("0 failure(s)"), "and reports no failures")

	# --- a bare filename resolved by search ---
	assert_true(
		text.contains("test/unit/logic/test_grid.gd"), "the run names the path it resolved to"
	)

	# --- every run reports what it cost ---
	assert_true(text.contains("--- suite cost ---"), "the cost block is printed")
	for counter: String in ["bouts", "turns", "floods"]:
		assert_true(text.contains(counter), "%s is reported" % counter)

	# --- a targeted run states its delta against the committed profile ---
	assert_true(text.contains("delta:"), "a targeted run states its delta")
	var profile: Variant = JSON.parse_string(profile_before)
	var recorded: Dictionary = {}
	for row: Dictionary in (profile as Dictionary).get("files", []):
		if String(row.get("path", "")) == "res://test/unit/logic/test_grid.gd":
			recorded = row
			break
	assert_false(recorded.is_empty(), "sanity: the profile has a row for this file")
	if int(recorded.get("turns", 0)) == 0 and int(recorded.get("bouts", 0)) == 0:
		assert_true(text.contains("no change"), "unchanged cost reports as no change")

	# --- and it left the committed artifacts alone ---
	assert_eq(
		FileAccess.get_file_as_string("res://test/suite_profile.json"),
		profile_before,
		"the profile was rewritten by a run that was not asked to write it"
	)


# --- resolving the target ------------------------------------------------------------


## **Two files sharing a name is a repo mistake to fix, not a case to disambiguate
## cleverly.** It prints both and stops, so the fix is obvious and nobody ends up
## running the wrong one because a resolver picked a winner.
##
## Exercised against a throwaway directory via `HB_TEST_ROOT` rather than by writing
## a duplicate into `test/`. Same reason as the probe above: a `.gd` written and
## deleted inside the project races Godot's importer, and the orphaned `.uid` breaks
## the next run rather than this one.
func test_an_ambiguous_name_fails_and_prints_every_match() -> void:
	var root: String = OS.get_environment("TMPDIR")
	if root == "":
		root = "/tmp"
	root += "/hulk_ambiguity_check"
	var output: Array = []
	SuiteProcess.execute(
		"bash",
		(
			[
				"-c",
				(
					"rm -rf %s && mkdir -p %s/a %s/b && touch %s/a/test_grid.gd %s/b/test_grid.gd"
					% [root, root, root, root, root]
				)
			]
			as Array[String]
		),
		output,
		true
	)

	var restore: String = OS.get_environment("HB_TEST_ROOT")
	OS.set_environment("HB_TEST_ROOT", root)
	var result: Dictionary = _run(["test_grid.gd"] as Array[String])
	OS.set_environment("HB_TEST_ROOT", restore)
	SuiteProcess.execute("bash", ["-c", "rm -rf %s" % root] as Array[String], [], true)

	gut.p(result["out"])
	assert_eq(int(result["code"]), 2, "ambiguity is a usage error, not a test failure")
	assert_true(String(result["out"]).contains("ambiguous"), "and it says so")
	assert_true(String(result["out"]).contains("/a/"), "naming every match, not just one")
	assert_true(String(result["out"]).contains("/b/"), "including the second")


func test_an_unknown_target_is_a_usage_error() -> void:
	var result: Dictionary = _run(["test_definitely_not_a_real_file.gd"] as Array[String])

	assert_eq(int(result["code"]), 2, "not 1 — this is not a test failure")
	assert_true(String(result["out"]).contains("usage:"), "and it says how to call it")
	# tb67 Pass C: the usage line has to name the rung that exists, or the only place a
	# newcomer is told about `profile` is a doc they are not reading at the moment they need it.
	assert_true(String(result["out"]).contains("profile"), "and names the bookkeeping rung")


# --- tb67 Pass C: the four rungs ----------------------------------------------------


## **`shard` is refused by name, not by the filename resolver.**
##
## It named the sharded full gate while that was an opt-in fourth rung; the bare gate is that now,
## so the word became a synonym for the default and was retired. Left to fall through, it would
## have produced *"no test file or directory named 'shard'"* — true, useless, and exactly how a
## stale instruction survives: the taskblock-66 census found eight claims in this repo's own docs
## that were wrong for a median of fourteen blocks, and every one of them read plausibly.
##
## **Really invoked rather than read**, because the cost is one immediate exit and because what is
## being asserted is that the script refuses it, not that a string appears somewhere in the file.
func test_the_retired_shard_rung_says_it_is_retired_and_what_replaced_it() -> void:
	var result: Dictionary = _run(["shard"] as Array[String])

	assert_eq(int(result["code"]), 2, "a retired rung is a usage error")
	var out: String = String(result["out"])
	assert_true(out.contains("retired"), "and it says so in that word")
	assert_true(out.contains("./run_tests.sh "), "and points at what to run instead")
	assert_true(out.contains("profile"), "including the rung that took over the profiling job")


## **Which map each sharded rung reads, and which rung may write the artifacts.**
##
## Read from the shell rather than run, and the limit of that is worth stating: this asserts the
## script's *intent*, not its behaviour. Running the two sharded rungs for real costs 113 s and
## 200 s+ and spawns sixteen engines between them, which is not a unit test — the real proof that
## both work is the gate this file is running inside. The same instrument is already used on this
## same file by `test_hulk_prefix_guard.gd`.
##
## What it genuinely catches is the two maps being swapped or one rung quietly losing its map,
## which is a plausible edit and would otherwise show up as a fast gate that plays every bout.
func test_each_sharded_rung_reads_its_own_map_and_only_profile_writes() -> void:
	var shell: String = FileAccess.get_file_as_string("res://run_tests.sh")
	assert_gt(shell.length(), 0, "the script is readable, or this proves nothing")

	assert_true(
		shell.contains('run_sharded "test/shard_map_fast.json" "fast"'),
		"the fast rung reads the fast map",
	)
	assert_true(
		shell.contains('run_sharded "test/shard_map.json" ""'),
		"and the bare gate reads the full map",
	)
	assert_true(
		shell.contains('"$GATE" == "profile"'),
		"only the profile rung reaches the --write flag",
	)
	# The maps it names have to exist, or the rung fails at the point of use rather than here.
	assert_true(FileAccess.file_exists(ShardMap.MAP_PATH), "the full map is committed")
	assert_true(FileAccess.file_exists(ShardMap.FAST_MAP_PATH), "and so is the fast one")


## **A partial run must never write a whole-suite artifact**, whatever the environment
## says.
##
## `SUITE-PROFILE.md` and `suite_profile.json` describe the entire suite, so a run that
## saw one file cannot honestly produce them. Found the hard way: `WRITE_PROFILE=1` is
## an exported variable, so it leaked into the subprocess this very file spawns, and a
## targeted run overwrote the committed profile with a single file's data **while
## `test_suite_budget.gd` and `test_suite_tier.gd` were still reading it.** The outer
## run rewrote it correctly at the end, so the tree looked fine afterwards and the only
## symptom was two unrelated tests failing.
func test_a_targeted_run_refuses_to_write_the_profile_even_when_asked() -> void:
	var before: String = FileAccess.get_file_as_string("res://test/suite_profile.json")
	var output: Array = []
	# `OS.execute` inherits this process's environment, which is exactly how the
	# original leak happened — so setting it here reproduces the real conditions.
	OS.set_environment("WRITE_PROFILE", "1")

	var code: int = SuiteProcess.execute(
		"./run_tests.sh", ["test_grid.gd"] as Array[String], output, true
	)

	OS.set_environment("WRITE_PROFILE", "")
	var text: String = "\n".join(output)
	gut.p(text.substr(maxi(0, text.length() - 250)))
	assert_eq(code, 0, "the run itself still passes")
	assert_true(text.contains("WRITE_PROFILE ignored"), "and says why it did not write")
	assert_eq(
		FileAccess.get_file_as_string("res://test/suite_profile.json"),
		before,
		"a one-file run must not overwrite the whole-suite profile"
	)
