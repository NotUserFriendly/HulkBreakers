extends GutTest

## tb67 Pass A — **the thing that makes a sharded gate go red on drift.**
##
## `tools/merge_shards.py --totals-json=` writes the controlled totals; `tools/check_budget.gd`
## runs `SuiteBudget.violations()` over them and its exit code is the gate's. So the acceptance
## *"an induced counter overage fails a sharded gate and names the counter"* is a statement about
## this script's exit code and its stdout, and that is what is asserted here.
##
## ## Why this spawns a real engine rather than calling `violations()` in-process
##
## `violations()` is already pinned by `test_suite_budget.gd` against synthetic profiles, and
## repeating that here would test the rule twice and the wiring zero times. **The wiring is the new
## thing.** A `-s` script that computed the right answer and exited 0 anyway would leave the gate
## green on drift, which is exactly the state tb67 Pass A exists to end, and no in-process call can
## see it.
##
## **Two spawns, and they are the two cases the acceptance names.** Spawning is the most expensive
## unit of work in the suite per occurrence (`SuiteProcess`), so the argument-handling and
## unreadable-file branches — `quit(2)` — are deliberately left unasserted rather than bought at
## another engine start each. They fail loudly by construction; these two decide a gate.

const SCRIPT_PATH := "res://tools/check_budget.gd"

var _dir: String = ""


func before_each() -> void:
	_dir = "%s/tb67_budget_%d" % [OS.get_temp_dir(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	if _dir != "":
		OS.move_to_trash(ProjectSettings.globalize_path(_dir))


## Runs the checker over `totals` the way `run_tests.sh` does, and returns its verdict.
func _check(totals: Dictionary) -> Dictionary:
	var path: String = "%s/totals.json" % _dir
	# The `sampled_*` keys are written at zero rather than omitted, because omitting one means
	# something specific — `violations()` declines to judge that counter — and a fixture that
	# left them out would exercise the skip instead of the budget.
	var recorded: Dictionary = totals.duplicate()
	for counter: String in SuiteBudget.SAMPLED_BY_COUNTER:
		var key: String = SuiteBudget.SAMPLED_BY_COUNTER[counter]
		if not recorded.has(key):
			recorded[key] = 0
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"totals": recorded, "files": []}))
	file.close()

	var args: Array[String] = [
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"-s",
		SCRIPT_PATH,
		"--",
		"--totals=%s" % path,
	]
	var out: Array = []
	var code: int = SuiteProcess.execute(OS.get_executable_path(), args, out, true)
	return {"code": code, "text": "\n".join(PackedStringArray(out))}


## The passing direction, so the failure below means something. Totals exactly at the recorded
## baseline are within budget by definition — `HEADROOM` sits on top of them.
func test_a_suite_within_budget_passes_the_sharded_gate() -> void:
	var result: Dictionary = _check(SuiteBudget.BASELINE.duplicate())

	gut.p("exit %d" % result["code"])
	assert_eq(result["code"], 0, "at the baseline the gate is green")
	assert_true("within budget" in result["text"], "and it says so rather than saying nothing")
	# **The per-file half is absent and the output says so.** `violations()` is handed an empty
	# `files` array, so it can name no file — and a green verdict printed without that sentence
	# would be claiming a check nobody ran. Asserted here rather than in its own test because a
	# separate test would be a third engine start to read one line.
	assert_true(
		"per-file caps are not checked" in result["text"],
		"a sharded run cannot evaluate PER_FILE and must not imply it did"
	)


## **The acceptance: an induced overage fails, and the message names the counter.** "The suite got
## more expensive" is not something anyone can act on; the counter and the delta are.
func test_an_induced_overage_fails_and_names_the_counter() -> void:
	var over: Dictionary = SuiteBudget.BASELINE.duplicate()
	over["ui_builds"] = SuiteBudget.limit_for("ui_builds") + 500

	var result: Dictionary = _check(over)

	gut.p("exit %d" % result["code"])
	assert_eq(result["code"], 1, "over budget is a red gate, not a printed warning")
	assert_true("OVER BUDGET" in result["text"], "and it is loud")
	assert_true("ui_builds" in result["text"], "named by counter")
	assert_true("+500" in result["text"], "and by how far over")
	# The gated counters that did not move must not be reported — a guard that names everything
	# names nothing.
	assert_false("suite maps" in result["text"], "counters inside their budget stay quiet")
