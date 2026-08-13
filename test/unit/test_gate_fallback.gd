extends GutTest

## tb67 Pass D — **the fallback, and the one thing it must never do.**
##
## Sharding's risk is not that it breaks. It is that it **degrades quietly** and a future CC
## concludes twenty-two minutes is normal — the same shape as the profile going eight blocks stale,
## where every individual run looked fine.
##
## So there are two properties, and the second matters more than the first:
##
## 1. An infrastructure failure falls back, loudly, in the banner **and** the verdict line **and** a
##    durable record. CC reads the tail of a log and reports from it, so a banner alone is not loud.
## 2. **A failing test never falls back.** A red gate re-run single-process is a real crash
##    laundered into a slow green run, which is worse than the crash.
##
## ## Why these shell out, and what the seams are for
##
## The fallback is shell behaviour and none of it exists inside the engine, so asserting it any
## other way would be asserting a second implementation — the trap `docs/00` names for view maths.
##
## Three test-only seams make that affordable and safe:
## - `HB_SHARD_MAP` points the gate at a map that is not the committed one, so a corrupt or
##   deliberately-tiny map can be used without editing the repo's own artifacts.
## - `HB_REPACK_CMD` replaces the repack with a no-op. **Without it a test driving the stale-map
##   branch would repack the two committed maps as a side effect** — the gate editing the repo
##   because a test asked it a question.
## - `HB_DRY_RUN` stops at the decision and exits **3**, never 0, so it cannot be mistaken for a
##   pass. Needed because a real fallback runs the whole suite in one process: 1687 s per case.

const SCRIPT := "./run_tests.sh"

var _dir: String = ""
var _restore_failure: String = ""


func before_each() -> void:
	_dir = "%s/tb67_fallback_%d" % [OS.get_temp_dir(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_dir)
	_restore_failure = OS.get_environment(TestExitCodeProbe.FORCE_FAILURE_ENV)


func after_each() -> void:
	OS.set_environment(TestExitCodeProbe.FORCE_FAILURE_ENV, _restore_failure)
	OS.set_environment(TestExitCodeProbe.FORCE_DEATH_ENV, "")
	for key: String in ["HB_SHARD_MAP", "HB_REPACK_CMD", "HB_DRY_RUN", "HB_FALLBACK_LOG"]:
		OS.set_environment(key, "")
	if _dir != "":
		OS.move_to_trash(ProjectSettings.globalize_path(_dir))


func _write(name: String, text: String) -> String:
	var path: String = "%s/%s" % [_dir, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _run(args: Array[String]) -> Dictionary:
	var output: Array = []
	var code: int = SuiteProcess.execute(SCRIPT, args, output, true)
	return {"code": code, "out": "\n".join(output)}


func _record_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	return FileAccess.get_file_as_string(path).strip_edges().split("\n", false)


## **An unparseable map is infrastructure, so it falls back — and says so three times over.**
##
## The banner is where it happens, the verdict line is what gets quoted into a report, and the
## record is what turns *"this happened once"* into *"this has happened four times and nobody
## filed it."* Any one of the three alone is missable.
func test_a_corrupt_map_falls_back_loudly_and_is_recorded() -> void:
	var map: String = _write("broken.json", "this is not json")
	var log: String = "%s/fallbacks.log" % _dir
	OS.set_environment("HB_SHARD_MAP", map)
	OS.set_environment("HB_FALLBACK_LOG", log)
	OS.set_environment("HB_DRY_RUN", "1")

	var result: Dictionary = _run(["fast"] as Array[String])
	var out: String = String(result["out"])

	gut.p("exit %d" % result["code"])
	assert_eq(int(result["code"]), 3, "the dry-run seam exits 3, never 0 — see this file's header")
	assert_true(out.contains("SHARDED GATE UNAVAILABLE"), "1. a banner where it happens")
	assert_true(out.contains("not a parseable shard map"), "naming the condition")
	assert_true(out.contains("pack_shards.gd"), "and the fix")
	assert_true(out.contains("FELL BACK TO ONE PROCESS"), "2. and it reaches the verdict line")
	assert_true(
		out.contains("finding to report"), "which says what to do with it, not just that it is"
	)

	var lines: PackedStringArray = _record_lines(log)
	assert_eq(lines.size(), 1, "3. and the durable record gained exactly one line")
	if lines.size() == 1:
		gut.p(lines[0])
		assert_true(lines[0].contains("fallback"), "tagged as a fallback")
		assert_true(lines[0].contains("fast"), "naming the rung it happened on")


## **The one that matters: a failing test is a red gate, not a reason to re-run anything.**
##
## Driven against a real sharded run of a real failing test rather than a fixture, because what is
## being asserted is that the *script* does not reach for the fallback when the merge reports
## failures — and a fixture would be asserting a second implementation of that decision.
##
## Uses a one-file, one-shard map so the whole thing costs a gate floor rather than a suite.
func test_a_failing_test_fails_the_gate_and_never_falls_back() -> void:
	var map: String = _write(
		"probe_map.json",
		(
			'{"shards": {"0": ["res://test/unit/test_exit_code_probe.gd"]}, '
			+ '"shard_count": 1, "generated_from": "test-only"}'
		)
	)
	var log: String = "%s/fallbacks.log" % _dir
	OS.set_environment("HB_SHARD_MAP", map)
	# The map names one file, so the gate correctly reads it as stale. The repack is stubbed
	# because otherwise this test would rewrite both committed maps.
	OS.set_environment("HB_REPACK_CMD", "true")
	OS.set_environment("HB_FALLBACK_LOG", log)
	OS.set_environment(TestExitCodeProbe.FORCE_FAILURE_ENV, "1")

	var result: Dictionary = _run([] as Array[String])
	var out: String = String(result["out"])

	gut.p("exit %d" % result["code"])
	assert_eq(int(result["code"]), 1, "a failing test fails the gate")
	assert_true(out.contains("GATE FAIL"), "and the verdict line says so")
	assert_true(out.contains("sharded"), "having stayed sharded throughout")
	assert_false(out.contains("FELL BACK"), "a test failure is NEVER an infrastructure fallback")
	assert_false(
		out.contains("SHARDED GATE UNAVAILABLE"), "and no banner claims the gate was unavailable"
	)

	# **The stale-map branch is exercised here too**, since a one-file map is maximally stale: it
	# reports the staleness, repacks, and carries the repack into the verdict rather than failing
	# with an instruction for a human to follow.
	assert_true(out.contains("is stale"), "the stale map is detected before launch")
	assert_true(out.contains("REPACKED"), "the repack reaches the verdict line")

	var fallbacks: Array[String] = []
	for line: String in _record_lines(log):
		if line.contains("\tfallback\t"):
			fallbacks.append(line)
	assert_eq(
		fallbacks,
		[] as Array[String],
		"and nothing was recorded as a fallback, because nothing fell back"
	)


## **`BR67.01`: a shard that dies keeps its log, because otherwise nobody can ever say why.**
##
## Observed once for real — shard 0 died after ~499 s, the other seven green at 0 failures, and
## nothing could be said about the cause: it was green in isolation and green on the next gate.
## The shard logs live in a `mktemp -d` under a cleanup trap, so **the one artifact that would
## name the cause is deleted at the moment the gate reports the failure.**
##
## Driven against a real death rather than a crafted log. `HB_FORCE_SHARD_DEATH` makes the probe
## kill its own process, which reproduces the signature exactly — engine banner present, no
## summary line, terminated by signal. A fixture would assert that the copy works; this asserts
## that the copy happens for the event it was written for.
##
## **It must also stay a gate failure.** A shard that started and died is not an infrastructure
## fallback, and re-running it single-process would launder a real crash into a slow green run.
func test_a_shard_that_dies_keeps_its_log_and_still_fails_the_gate() -> void:
	var map: String = _write(
		"death_map.json",
		(
			'{"shards": {"0": ["res://test/unit/test_exit_code_probe.gd"]}, '
			+ '"shard_count": 1, "generated_from": "test-only"}'
		)
	)
	var log: String = "%s/fallbacks.log" % _dir
	OS.set_environment("HB_SHARD_MAP", map)
	OS.set_environment("HB_REPACK_CMD", "true")
	OS.set_environment("HB_FALLBACK_LOG", log)
	OS.set_environment(TestExitCodeProbe.FORCE_DEATH_ENV, "1")

	var result: Dictionary = _run([] as Array[String])
	var out: String = String(result["out"])

	assert_eq(int(result["code"]), 1, "a dead shard is a failed gate")
	assert_true(out.contains("DID NOT FINISH"), "and the merge names it")
	assert_false(out.contains("FELL BACK"), "a shard that STARTED and died never falls back")

	# The path is printed so it can be followed, and it has to be printed to be followed.
	assert_true(out.contains("logs kept in"), "the gate says where the evidence went")
	var kept: String = ""
	for line: String in out.split("\n"):
		if line.contains("logs kept in "):
			kept = line.split("logs kept in ")[1].split(" ")[0].strip_edges()
	assert_ne(kept, "", "and the line carries a usable path")
	if kept == "":
		return

	var shard_log: String = "%s/shard0.log" % kept
	assert_true(FileAccess.file_exists(shard_log), "the dead shard's log survived the cleanup trap")
	var text: String = FileAccess.get_file_as_string(shard_log)
	gut.p("preserved %d bytes at %s" % [text.length(), shard_log])
	# **Diagnostic, not merely present.** What was missing in the real incident was the last thing
	# the shard was doing, and that is exactly what the tail of this log now carries.
	assert_true(text.contains("Godot Engine"), "it proves the engine started")
	assert_true(
		text.contains("test_exit_code_probe.gd"), "and names the file it was in when it died"
	)

	var recorded := false
	for line: String in _record_lines(log):
		if line.contains("shard-no-summary"):
			recorded = true
	assert_true(recorded, "and the incident is in the durable record, so a pattern can be seen")
