class_name SuiteRun
extends RefCounted

## taskblock-48 Pass B: **the game launches the test suite and watches it run.**
##
## The value is seeing what CC actually runs. A curated list would be CC's own
## selection of what is worth watching, which makes it the wrong instrument for
## checking CC's work — so this tails the real output of the real script, unedited.
## Filtering is a view over this feed, never a second source, so it cannot drift from
## what really happened.
##
## ## Why a subprocess rather than hosting GUT
##
## GUT is a command-line addon. Hosting it inside a running game buys nothing the
## subprocess does not, and it would mean the thing under test shares a process with
## the thing observing it. The subprocess also gets the **real** `run_tests.sh` —
## lint gate, import, parse guard and all — so what the window reports is what the
## terminal reports, which `test_suite_run.gd` asserts rather than assumes.
##
## ## Why the output goes through a file
##
## `OS.execute` blocks the calling thread, which would freeze the window for the
## length of a suite run — the exact failure taskblock-42 spent a pass removing from
## the AI batch. `OS.create_process` does not block but gives no pipe, so the command
## is wrapped in a shell that redirects to a log, and `poll()` reads whatever has
## arrived since last time. **Chopping a run early is the point**, so the PID is kept
## and `kill()` is not optional garnish.

## Where a run's output lands. Under `user://` because it is scratch — the run is the
## artifact, not the log of it, and nothing here is meant to outlive the session.
##
## **One file per instance, not one file per project.** A fixed path was the first
## version and it was wrong in a way that only showed up under test: two `SuiteRun`s
## alive at once — or one killed run whose log outlived it — read and wrote the same
## bytes, and the feed became a splice of two suites. It surfaced as tests failing
## differently on every invocation, which is the worst possible symptom because it
## reads as an engine problem rather than as shared state.
const LOG_PREFIX := "user://suite_run_"
## Written by the shell wrapper after the script exits, because `OS.create_process`
## reports a PID and never an exit status. **The marker is how the window knows
## pass from fail**, so it is parsed rather than inferred from the text.
const EXIT_MARKER := "__SUITE_EXIT__"

## The three rungs, as the panel offers them. Values are the argument `run_tests.sh`
## takes; `full` deliberately passes nothing, since that is how the script defines it.
const RUNGS: Dictionary = {
	&"full": "",
	&"fast": "fast",
}

## Distinguishes concurrent runs. A counter rather than a clock read: two runs started
## in the same millisecond are exactly the case this has to survive.
static var _next_id: int = 0

var pid: int = -1
var lines: Array[String] = []
var exit_code: int = -1
var finished: bool = false
var started_msec: int = 0
var _read_offset: int = 0
var _rung: StringName = &"full"
var _log_path: String = ""
var _pgid_path: String = ""


## Starts `rung` (or a single file when `target` is given) and returns whether it
## launched. Never blocks.
func start(rung: StringName, target: String = "") -> bool:
	var argument: String = target if target != "" else String(RUNGS.get(rung, ""))
	_next_id += 1
	_log_path = "%s%d.log" % [LOG_PREFIX, _next_id]
	var log_file: String = ProjectSettings.globalize_path(_log_path)
	# Truncated up front rather than appended to: a panel showing the tail of two runs
	# spliced together is worse than one showing nothing.
	var truncate := FileAccess.open(_log_path, FileAccess.WRITE)
	if truncate != null:
		truncate.close()
	_pgid_path = "%s%d.pgid" % [LOG_PREFIX, _next_id]
	var pgid_file: String = ProjectSettings.globalize_path(_pgid_path)
	DirAccess.remove_absolute(pgid_file)
	# `$$` inside the `setsid`-ed shell is the new session leader, which is also the
	# process group every descendant inherits — the handle `kill()` needs.
	var command: String = (
		'echo $$ > %s; ./run_tests.sh %s > %s 2>&1; echo "%s=$?" >> %s'
		% [pgid_file, argument, log_file, EXIT_MARKER, log_file]
	)
	pid = OS.create_process("/usr/bin/env", ["setsid", "bash", "-c", command])
	if pid <= 0:
		return false
	_rung = rung
	lines = []
	exit_code = -1
	finished = false
	_read_offset = 0
	started_msec = Time.get_ticks_msec()
	return true


## Reads whatever the run has written since the last call. Cheap enough to call every
## frame — it seeks to a stored offset rather than re-reading the file.
##
## **Completion is decided by the exit marker, not by the process disappearing.** A
## process can vanish without the script having finished writing, and a run reported
## as passed because its PID went away would be exactly the kind of lie that makes
## this window worthless.
func poll() -> void:
	if _log_path == "":
		return
	var file := FileAccess.open(_log_path, FileAccess.READ)
	if file == null:
		return
	file.seek(_read_offset)
	var fresh: String = file.get_as_text()
	_read_offset = int(file.get_length())
	file.close()
	ingest(fresh)


## Folds raw output into the feed. **Split out of `poll()` so the verdict logic can be
## tested without a subprocess**, which matters because "does a failing suite read as
## failed" is a parsing question and testing it through a real run made it a question
## about whether GUT had discovered a just-written file — a race that produced a
## passing verdict for the wrong reason.
##
## The end-to-end claim is still tested against a real subprocess; it just no longer
## has to manufacture a failure to do it.
func ingest(text: String) -> void:
	if text == "":
		return
	for line: String in text.split("\n"):
		if line.begins_with(EXIT_MARKER):
			exit_code = line.split("=")[-1].to_int()
			finished = true
			continue
		lines.append(line)


## **Started and not yet finished** — and finished means the exit marker, exactly as
## `poll()` documents.
##
## This used to also require `OS.is_process_running(pid)`, which was wrong twice over
## once the run moved under `setsid`: `setsid` forks, so the pid the engine hands back
## is a launcher that exits immediately, and a run was reported as over about a
## millisecond after it started. The pid is kept for diagnostics; the group is what
## can be signalled and the marker is what says it ended.
func is_running() -> bool:
	return _log_path != "" and not finished


## Stops the run. The log keeps whatever it managed, because the reason to kill a run
## is usually that you have already seen the thing you were waiting for.
func kill() -> void:
	var group: int = process_group()
	if group > 0:
		# `kill -- -PGID` signals every process in the group, which is the shell AND
		# the Godot it launched. Run **through bash**, not as a bare `OS.execute("kill",
		# ...)`: `kill` is a shell builtin, the standalone binary is not guaranteed to
		# be on the path, and `OS.execute` fails silently when it cannot find one — the
		# grandchild simply carried on and nothing said why.
		#
		# `-KILL` after `-TERM` because a Godot mid-suite does not always take a polite
		# signal, and a kill button that sometimes does not kill is worse than none.
		(
			OS
			. execute(
				"bash",
				(
					[
						"-c",
						(
							"kill -TERM -- -%d 2>/dev/null; sleep 0.5; kill -KILL -- -%d 2>/dev/null; true"
							% [group, group]
						)
					]
					as Array[String]
				)
			)
		)
	elif pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	finished = true
	if exit_code == -1:
		exit_code = -2


## The process group the run owns, or -1 before the shell has written it. Read from
## the file rather than assumed from `pid`, since `setsid` may fork.
func process_group() -> int:
	if _pgid_path == "":
		return -1
	var file := FileAccess.open(_pgid_path, FileAccess.READ)
	if file == null:
		return -1
	var text: String = file.get_as_text().strip_edges()
	file.close()
	return text.to_int() if text.is_valid_int() else -1


## Zero for a run that was never started — one handed its output directly has no start
## time, and reporting the process's whole uptime as its duration put "FAILED in 365s"
## in a header describing a run that took no time at all.
func elapsed_seconds() -> float:
	if started_msec == 0:
		return 0.0
	return float(Time.get_ticks_msec() - started_msec) / 1000.0


## Whether the run passed. **`false` until the exit marker lands**, so a run in
## progress never reads as green.
func passed() -> bool:
	return finished and exit_code == 0


## The file GUT is currently in, from the feed. Empty before the first one.
func current_script() -> String:
	for i in range(lines.size() - 1, -1, -1):
		var line: String = lines[i].strip_edges()
		if line.begins_with("res://test/") and line.ends_with(".gd"):
			return line.replace("res://test/", "")
	return ""


## The work counts the runner prints at the end, or an empty dictionary before then.
## Parsed from the same line a terminal shows, so the two cannot disagree.
func work_counts() -> Dictionary:
	for i in range(lines.size() - 1, -1, -1):
		var line: String = lines[i]
		if not line.contains("bouts ") or not line.contains("turns "):
			continue
		var counts: Dictionary = {}
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		var key := ""
		for part: String in parts:
			if part.is_valid_int() and key != "":
				counts[key] = part.to_int()
				key = ""
			else:
				key = part
		return counts
	return {}


## `{passing, failing}` from GUT's own summary lines. Reported as they land rather
## than only at the end, which is what makes a run killable on the evidence.
func tallies() -> Dictionary:
	var result: Dictionary = {"passing": 0, "failing": 0}
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("Passing Tests"):
			result["passing"] = trimmed.split(" ", false)[-1].to_int()
		elif trimmed.begins_with("Failing Tests"):
			result["failing"] = trimmed.split(" ", false)[-1].to_int()
	return result


## Which tests failed, as `[{"script": String, "test": String}, ...]`, in the order
## GUT reported them.
##
## Read from the **Run Summary**, not from the inline `[Failed]` lines scattered
## through the feed: the summary is GUT's own deduplicated list, so a test that failed
## three assertions appears once rather than three times. Replaying the same fixture
## three times would be exactly the noise the cap exists to avoid.
##
## Parsed rather than tracked, for the same reason everything else here is: the feed is
## the real output, and anything derived from a second source could disagree with what
## the terminal showed.
func failures() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var in_summary := false
	var script := ""
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.contains("Run Summary"):
			in_summary = true
			continue
		if not in_summary:
			continue
		if trimmed.begins_with("res://") and trimmed.ends_with(".gd"):
			script = trimmed
		elif trimmed.begins_with("- test_") and script != "":
			found.append({"script": script, "test": trimmed.substr(2).strip_edges()})
	return found


## One line for the panel's header. **States what is happening, not just a spinner** —
## a progress indicator that cannot say what it is doing is something to interpret.
func status_line() -> String:
	# **Keyed off what is known, not off how it was learned.** This checked `pid`
	# first, so a run that had been handed its output rather than spawning it reported
	# "no run started" while holding a complete verdict — the header contradicting the
	# fields beside it.
	if pid <= 0 and lines.is_empty() and not finished:
		return "no run started"
	if not finished:
		var where: String = current_script()
		return (
			"running %s — %.0fs%s"
			% [_rung, elapsed_seconds(), "" if where == "" else " — " + where]
		)
	if exit_code == -2:
		return "killed after %.0fs" % elapsed_seconds()
	var counts: Dictionary = tallies()
	return (
		"%s in %.0fs — %d passing, %d failing (exit %d)"
		% [
			"PASSED" if passed() else "FAILED",
			elapsed_seconds(),
			int(counts["passing"]),
			int(counts["failing"]),
			exit_code,
		]
	)
