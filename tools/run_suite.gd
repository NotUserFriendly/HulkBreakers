extends SceneTree

## **The one way this project runs its tests**, and what each run cost.
##
## taskblock-47 Pass A: what the suite spends, per file and per test.
## taskblock-48 Pass A2: **and it is the runner now, not a second entry point.**
##
## ## Why the two collapsed
##
## Work counts exist only in-process, and only this file collected them, because it
## hosts `GutRunner` itself to reach the `start_script`/`end_script` boundaries. A
## normal run went through `gut_cmdln.gd` and produced no counts at all — two entry
## points into one suite, and **only one of them failed the build**: `gut_cmdln.gd`
## passes `-gexit`, while this file used to set `should_exit = false` and `quit(0)`
## after writing its JSON.
##
## A runner that reports counts beautifully and exits 0 on a red suite is worse than
## no runner at all, so the exit code is the load-bearing part of the collapse and
## `test_run_suite.gd` asserts it against a deliberately failing test.
##
## The suite went ~355 s to ~1370 s across one taskblock and became the dominant
## cost of doing work here. This measures that before anything is changed, because
## this project has now optimized an unprofiled function three times — taskblock-35,
## taskblock-42 and taskblock-43 each attacked the wrong one, and taskblock-43's
## bench settled it in an afternoon.
##
## ## Two currencies, and the difference between them is the finding
##
## **Wall-clock** is what a human waits through, and it is the softer number: it
## moves with the machine, the CPU's mood, and whatever else is running.
##
## **Work counts** — bouts built, turns resolved, candidates scored, `ShotPlane`
## builds, pathfinder floods — are exact and machine-independent. They are what Pass
## B's budgets gate on, because a seconds threshold is the kind of constant this
## project has a documented habit of raising when it flaps.
##
## The two top-20 lists are printed separately and deliberately: a file that is slow
## *without* resolving turns is slow for a reason worth understanding rather than a
## reason worth budgeting.
##
## ## Why it drives `GutRunner` rather than parsing GUT's output
##
## The counters only exist in-process. GUT publishes `start_script`/`end_script` and
## `start_test`/`end_test`, so a snapshot at each boundary costs a handful of integer
## reads — the profiler is close to free, which is the standing requirement for
## instrumentation that ships. Nothing here changes what any test does.
##
## ## Artifacts are opt-in
##
## `SUITE-PROFILE.md` and `suite_profile.json` are committed, so rewriting them on
## every run would churn the tree and drop noise into unrelated diffs. They are
## written only with `--write`; counts print either way.
##
## Usage — normally reached through `run_tests.sh` rather than directly:
## ```
## godot --headless --path . -s res://tools/run_suite.gd -- --dir=res://test --write
## godot --headless --path . -s res://tools/run_suite.gd -- --test=res://test/unit/foo.gd
## ```

const OUTPUT_PATH := "res://test/SUITE-PROFILE.md"
## The same run, machine-readable and complete. The markdown carries the top 20
## because that is what a human reads; **the budget check needs every file**, and
## having it re-parse a table that was formatted for reading would make the gate
## depend on column alignment.
const DATA_PATH := "res://test/suite_profile.json"
## How many rows each of the two tables carries. The taskblock asks for 20.
const TOP_N := 20

var _runner: Node = null
var _script_rows: Array[Dictionary] = []
var _test_rows: Array[Dictionary] = []
var _script_path: String = ""
var _script_mark: Dictionary = {}
var _script_usec: int = 0
var _test_name: String = ""
var _test_mark: Dictionary = {}
var _test_usec: int = 0
var _run_usec: int = 0
var _dirs: Array[String] = []
var _tests: Array[String] = []
var _write_artifacts: bool = false


func _init() -> void:
	var version_conversion: Object = load("res://addons/gut/version_conversion.gd")
	if version_conversion.error_if_not_all_classes_imported():
		quit(1)
		return
	# Mirrors `gut_cmdln.gd`: the loader's `_static_init` has to run, and the main
	# loop is occasionally not up on the first frame.
	var loader: Object = load("res://addons/gut/gut_loader.gd")
	assert(loader != null, "gut_loader must load")
	var iterations := 0
	while Engine.get_main_loop() == null and iterations < 20:
		await create_timer(0.01).timeout
		iterations += 1

	DataLibrary.load_all()
	_parse_args()
	var config: Object = load("res://addons/gut/gut_config.gd").new()
	config.options.include_subdirs = true
	# **`should_exit` stays false and the exit code is computed by hand below.** GUT
	# would otherwise quit before `end_run` finishes writing, and the whole point of
	# this collapse is that the process still fails when the suite does.
	config.options.should_exit = false
	config.options.log_level = 0
	if _tests.is_empty():
		config.options.dirs = _dirs if not _dirs.is_empty() else ["res://test"]
	else:
		config.options.tests = _tests

	_runner = load("res://addons/gut/gui/GutRunner.tscn").instantiate()
	_runner.set_gut_config(config)
	get_root().add_child(_runner)

	var gut: Object = _runner.gut
	gut.start_script.connect(_on_start_script)
	gut.end_script.connect(_on_end_script)
	gut.start_test.connect(_on_start_test)
	gut.end_test.connect(_on_end_test)
	gut.end_run.connect(_on_end_run)

	_run_usec = Time.get_ticks_usec()
	_runner.run_tests(false)


## `--dir=`, `--test=` and `--write`, from the user args after `--`. Deliberately
## tiny: `run_tests.sh` is the interface people use, and a second option surface here
## would be somewhere for the two to disagree.
func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dirs.append(arg.trim_prefix("--dir="))
		elif arg.begins_with("--test="):
			_tests.append(arg.trim_prefix("--test="))
		elif arg == "--write":
			_write_artifacts = true


## **Printed on every run, artifacts or not.** The counts are what taskblock-48 Pass
## A3 diffs against the committed profile, and a number you have to opt into is a
## number nobody reads.
##
## The per-file delta is only printed for a targeted run: over the whole suite it
## would be 245 lines of noise, and the interesting case is exactly the one where
## someone just changed one file.
func _print_summary(total_usec: int, failures: int) -> void:
	var total: Dictionary = _totals()
	print("")
	print("--- suite cost ---")
	print(
		(
			"%d script(s), %d test(s), %d failure(s), %.1f s"
			% [_script_rows.size(), _test_rows.size(), failures, float(total_usec) / 1_000_000.0]
		)
	)
	var parts: Array[String] = []
	for key: String in [
		"bouts", "turns", "plans", "candidates", "shot_planes", "floods", "ui_builds"
	]:
		parts.append("%s %d" % [key, int(total.get(key, 0))])
	print("  ".join(parts))
	if _script_rows.size() == 1:
		_print_delta(_script_rows[0])


## `+3 tests, +47 turns in test_utility_planner` — a vetoable statement, where
## "+47 turns somewhere" is not.
##
## The committed profile already holds this file's previous numbers, so the diff is
## exact and costs a file read. A file with no row yet is new, and says so rather than
## reporting its whole cost as an increase.
func _print_delta(row: Dictionary) -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var path: String = String(row["path"])
	var previous: Dictionary = {}
	for candidate: Dictionary in (parsed as Dictionary).get("files", []):
		if String(candidate.get("path", "")) == path:
			previous = candidate
			break
	var short: String = path.replace("res://test/", "")
	if previous.is_empty():
		print("delta: %s is new — no previous numbers to compare against" % short)
		return
	var moved: Array[String] = []
	for key: String in ["turns", "bouts", "floods", "ui_builds", "candidates"]:
		var change: int = int(row.get(key, 0)) - int(previous.get(key, 0))
		if change != 0:
			moved.append("%+d %s" % [change, key])
	if moved.is_empty():
		print("delta: no change in %s" % short)
		return
	print("delta: %s in %s" % [", ".join(moved), short])


## Every deterministic counter, read at once. **One function, so a new counter is
## added in a single place** — a snapshot assembled at two call sites drifts, and a
## profile whose start and end read different fields silently reports nonsense.
func _snapshot() -> Dictionary:
	return {
		"bouts": CombatState.bouts_built,
		"turns": CombatState.turns_resolved,
		"candidates": UtilityPlanner.candidates_scored,
		"plans": AiPlanner.plans,
		"shot_planes": ShotPlane.builds,
		"floods": Pathfinder.floods,
		"lookahead_fields": UtilityLookahead.fields_built,
		# taskblock-48 Pass D: the one counter here that is not AI work. Without it a
		# view-only regression is invisible to every budget.
		"ui_builds": HulkTheme.ui_builds,
	}


## **A counter the measured code resets underneath you reads as negative work.**
##
## Four test files zero these in their own `before_each` — they were diagnostics
## long before they were budgets — and GUT fires `start_test` *before* `before_each`,
## so the reset lands inside the measurement window. The first full profile duly
## reported `test_utility_planner.gd` as having scored **minus 1,272,441**
## candidates, which then subtracted from the suite totals and made every number in
## the file wrong rather than merely one row.
##
## A drop can only mean a reset, because every counter is monotonic between them. So
## a drop is read as exactly that: the counter went to zero and counted back up, and
## the work done since is the value now sitting in it. That loses whatever was
## counted between the window opening and the reset, which for a `before_each` is
## nothing at all — the reset is the first thing that happens.
##
## Detecting it beats forbidding it: telling four test files to stop resetting their
## own diagnostics would make the profiler's correctness depend on every future test
## author knowing that, and this is the kind of rule nobody is told twice.
func _delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in after:
		var moved: int = int(after[key]) - int(before[key])
		out[key] = moved if moved >= 0 else int(after[key])
	return out


func _on_start_script(script_obj: Object) -> void:
	_script_path = String(script_obj.path)
	_script_mark = _snapshot()
	_script_usec = Time.get_ticks_usec()


## **A script's counts are the sum of its tests', not its own start-to-end delta.**
##
## The script window spans every `before_each` in the file, so a file that resets a
## counter it also drives reports whatever happens to be sitting in the counter when
## the last test finishes — `test_work_counters.gd` measured 0 bouts while plainly
## playing several, because its final test ends on a deliberate reset. The per-test
## windows are short enough that the reset heuristic in `_delta` is exact, so
## summing them is both finer and more correct than measuring the outer window.
##
## Wall-clock still comes from the script window, because that one is genuinely the
## outer measure: it includes `before_all` and file load, which no test owns.
func _on_end_script() -> void:
	if _script_path == "":
		return
	var row: Dictionary = {}
	for test_row: Dictionary in _test_rows:
		if String(test_row["script"]) != _script_path:
			continue
		for key: String in test_row:
			if key == "path" or key == "script" or key == "usec":
				continue
			row[key] = int(row.get(key, 0)) + int(test_row[key])
	row["path"] = _script_path
	row["usec"] = Time.get_ticks_usec() - _script_usec
	_script_rows.append(row)
	_script_path = ""


func _on_start_test(test_name: String) -> void:
	_test_name = test_name
	_test_mark = _snapshot()
	_test_usec = Time.get_ticks_usec()


func _on_end_test() -> void:
	if _test_name == "":
		return
	var row: Dictionary = _delta(_test_mark, _snapshot())
	row["path"] = "%s::%s" % [_script_path.get_file(), _test_name]
	row["script"] = _script_path
	row["usec"] = Time.get_ticks_usec() - _test_usec
	_test_rows.append(row)
	_test_name = ""


func _on_end_run() -> void:
	var total_usec: int = Time.get_ticks_usec() - _run_usec
	var failures: int = int(_runner.gut.get_fail_count())
	_print_summary(total_usec, failures)
	if not _write_artifacts:
		# **A clean run leaves the committed artifacts alone.** They are in git; a
		# runner that rewrote them every invocation would put unrelated churn in every
		# diff and train people to `git checkout` them without reading.
		quit(1 if failures > 0 else 0)
		return
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s" % OUTPUT_PATH)
		quit(1)
		return
	for line: String in _render(total_usec):
		file.store_line(line)
	file.close()

	var data := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if data == null:
		push_error("could not write %s" % DATA_PATH)
		quit(1)
		return
	# Sorted by path, so the committed file diffs as changed numbers rather than as
	# reordered rows.
	var by_path: Array[Dictionary] = _script_rows.duplicate()
	by_path.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["path"]) < String(b["path"])
	)
	data.store_line(
		JSON.stringify({"totals": _totals(), "wall_clock_usec": total_usec, "files": by_path}, "  ")
	)
	data.close()
	print("wrote %s and %s" % [OUTPUT_PATH, DATA_PATH])
	# **The exit code is the point of taskblock-48 Pass A2.** This used to be an
	# unconditional `quit(0)`.
	quit(1 if failures > 0 else 0)


func _totals() -> Dictionary:
	var total: Dictionary = {}
	for row: Dictionary in _script_rows:
		for key: String in row:
			if key == "path" or key == "script":
				continue
			total[key] = int(total.get(key, 0)) + int(row[key])
	return total


## Sorted descending on `key`, ties broken on path so two files with identical
## counts do not swap places between runs — the profile is committed and diffed,
## and a diff full of reordering is a diff nobody reads.
func _ranked(rows: Array[Dictionary], key: String) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = rows.duplicate()
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a[key]) == int(b[key]):
				return String(a["path"]) < String(b["path"])
			return int(a[key]) > int(b[key])
	)
	return sorted


func _render(total_usec: int) -> Array[String]:
	var total: Dictionary = _totals()
	var lines: Array[String] = []
	lines.append("# Suite profile")
	lines.append("")
	lines.append(
		(
			"**Generated by `tools/profile_suite.gd`. Do not hand-edit — regenerate.**"
			+ " Committed on purpose: `reports/` rolls at five blocks and this is a"
			+ " baseline meant to be compared against for much longer than that."
		)
	)
	lines.append("")
	lines.append(
		(
			"Work counts are exact and machine-independent; **wall-clock is the softer"
			+ " number** and will differ on your machine. Compare the counts across"
			+ " commits and the seconds only against themselves."
		)
	)
	lines.append("")
	lines.append("## Totals")
	lines.append("")
	lines.append("| measure | value |")
	lines.append("|---|---|")
	lines.append("| scripts | %d |" % _script_rows.size())
	lines.append("| tests | %d |" % _test_rows.size())
	lines.append("| wall-clock | %.1f s |" % (float(total_usec) / 1_000_000.0))
	for key: String in [
		"bouts", "turns", "plans", "candidates", "shot_planes", "floods", "ui_builds"
	]:
		lines.append("| %s | %d |" % [key, int(total.get(key, 0))])
	lines.append("")
	# Derived, never quoted. The taskblock's framing says "23 of 241 files run bouts";
	# a hardcoded 23 in generated output is a measurement that stops being re-taken
	# the moment someone adds a bout to a unit test, which is the exact drift this
	# whole file exists to catch.
	var with_bouts := 0
	var with_turns := 0
	for row: Dictionary in _script_rows:
		if int(row.get("bouts", 0)) > 0:
			with_bouts += 1
		if int(row.get("turns", 0)) > 0:
			with_turns += 1
	lines.append(
		(
			(
				"**%d of %d files build a bout, and %d resolve a turn by any route.**"
				+ " The gap between those two is the retargeting surface: a file that"
				+ " resolves turns without building a bout is already driving the board"
				+ " directly, which is what taskblock-47 Pass E moves work toward."
			)
			% [with_bouts, _script_rows.size(), with_turns]
		)
	)
	lines.append("")
	lines.append_array(_table("Top %d files by wall-clock" % TOP_N, _script_rows, "usec"))
	lines.append_array(_table("Top %d files by turns resolved" % TOP_N, _script_rows, "turns"))
	lines.append_array(_table("Top %d tests by wall-clock" % TOP_N, _test_rows, "usec"))
	return lines


func _table(title: String, rows: Array[Dictionary], key: String) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## %s" % title)
	lines.append("")
	lines.append("| | seconds | bouts | turns | plans | candidates | planes | floods |")
	lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
	var ranked: Array[Dictionary] = _ranked(rows, key)
	for i in range(mini(TOP_N, ranked.size())):
		var row: Dictionary = ranked[i]
		(
			lines
			. append(
				(
					"| `%s` | %.2f | %d | %d | %d | %d | %d | %d |"
					% [
						String(row["path"]).replace("res://test/", ""),
						float(row["usec"]) / 1_000_000.0,
						int(row.get("bouts", 0)),
						int(row.get("turns", 0)),
						int(row.get("plans", 0)),
						int(row.get("candidates", 0)),
						int(row.get("shot_planes", 0)),
						int(row.get("floods", 0)),
					]
				)
			)
		)
	lines.append("")
	return lines
