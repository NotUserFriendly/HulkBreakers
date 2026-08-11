extends GutTest

## tb65 Pass F — **the subprocess counter, and the guard that stops it being bypassed.**
##
## Deliberately its own file rather than a section of `test_work_counters.gd`: that file builds
## bouts and the fast gate skips it, and a guard that only the full gate runs is one that tells
## you about a bypass twenty minutes later. Nothing here builds a bout, so it runs on every rung.

## The one legitimate direct caller — this sweep has to be allowed to name the thing it bans.
const SELF_PATH := "res://test/unit/test_suite_process.gd"
const WRAPPER_PATH := "res://test/support/suite_process.gd"


## **A counter something can bypass reads low and looks green**, which is the failure mode the
## whole budget file is written against. `OS.execute` and `OS.create_process` are the engine's,
## so there is no way to instrument them — the only thing keeping `SuiteRun.processes_spawned`
## honest is that every test goes through the wrapper.
##
## Bans the two engine calls by name, in code rather than in comments, the same shape
## `test_step_height.gd`'s retired-identifier sweep uses. `src/logic/suite_run.gd` is not swept
## because it increments the counter itself at its own spawn site.
func test_no_test_spawns_a_process_behind_the_counter() -> void:
	var offenders: Array[String] = VocabularySweep.scan(
		[".gd"],
		SELF_PATH,
		func(path: String, line_number: int, line: String) -> String:
			if not path.begins_with("res://test/") or path == WRAPPER_PATH:
				return ""
			var code: String = line.split("#")[0]
			for banned: String in ["OS.execute(", "OS.create_process("]:
				if banned in code:
					return "%s:%d  %s" % [path, line_number, line.strip_edges()]
			return ""
	)

	assert_eq(
		offenders,
		[] as Array[String],
		(
			"a test spawning a process directly is invisible to SuiteRun.processes_spawned — "
			+ "use SuiteProcess.execute/create_process:\n%s" % "\n".join(offenders)
		)
	)


## **The wrapper counts, and it does not change what it wraps.** A wrapper that also altered
## behaviour would give a caller a reason to go around it, which is how the guard above becomes
## a formality.
func test_the_wrapper_counts_a_spawn_and_returns_what_os_execute_returns() -> void:
	SuiteRun.reset_diagnostics()
	var output: Array = []

	var code: int = SuiteProcess.execute(
		"bash", ["-c", "echo hulkbreakers; exit 3"] as Array[String], output, true
	)

	gut.p("exit %d, output %s, spawns %d" % [code, output, SuiteRun.processes_spawned])
	assert_eq(SuiteRun.processes_spawned, 1, "the spawn was counted")
	assert_eq(code, 3, "and the real exit code came back unchanged")
	assert_true(
		"hulkbreakers" in "\n".join(PackedStringArray(output)), "along with the real output"
	)


func test_resetting_clears_the_spawn_counter() -> void:
	SuiteProcess.execute("bash", ["-c", "true"] as Array[String], [], false)
	assert_gt(SuiteRun.processes_spawned, 0, "sanity: something was counted to clear")

	SuiteRun.reset_diagnostics()

	assert_eq(SuiteRun.processes_spawned, 0, "reset_diagnostics clears it")
