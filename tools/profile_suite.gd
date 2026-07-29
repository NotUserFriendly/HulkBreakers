extends SceneTree

## taskblock-47 Pass A: **what the test suite actually spends, per file and per test.**
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
## Usage: `godot --headless --path . -s res://tools/profile_suite.gd`

const OUTPUT_PATH := "res://test/SUITE-PROFILE.md"
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
	var config: Object = load("res://addons/gut/gut_config.gd").new()
	config.options.dirs = ["res://test"]
	config.options.include_subdirs = true
	config.options.should_exit = false
	config.options.log_level = 0

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
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not write %s" % OUTPUT_PATH)
		quit(1)
		return
	for line: String in _render(total_usec):
		file.store_line(line)
	file.close()
	print("wrote %s (%d scripts, %d tests)" % [OUTPUT_PATH, _script_rows.size(), _test_rows.size()])
	quit(0)


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
	for key: String in ["bouts", "turns", "plans", "candidates", "shot_planes", "floods"]:
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
