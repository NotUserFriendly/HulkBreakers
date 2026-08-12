extends SceneTree

## tb67 Pass A — **the drift guard, over totals a sharded gate produced.**
##
##     godot --headless --path . -s res://tools/check_budget.gd -- --totals=<path>
##
## Reads the JSON `tools/merge_shards.py --totals-json=` wrote and runs
## `SuiteBudget.violations()` over it. Exit 1 if the suite's work grew past its budget, 0 if
## not, 2 if it could not read the file at all.
##
## ## Why this process exists rather than the merge deciding
##
## The merge is Python and the budget rule is GDScript, so the two shapes available were
## *teach Python the rule* or *hand the numbers back to the rule*. **This is the second.**
## `SuiteBudget`'s header argues `HEADROOM`, `GATED`, the `sampled_turns` subtraction and every
## `BASELINE` figure over four taskblocks of measurement; a Python copy would be a second
## implementation of all of it, re-ratcheted in one place and not the other. The failure that
## costs is the silent direction: a stale Python baseline **passes** a run the real rule fails,
## and a drift guard that reads low looks exactly like a suite that did not drift.
##
## The price is one engine start at the end of a sharded gate — about 2 s against 220–626 s
## (tb66 F), paid once per gate rather than once per shard.
##
## ## What this cannot check, said out loud rather than left to be inferred
##
## **Totals only. The per-file caps in `SuiteBudget.PER_FILE` are not evaluated here**, because
## a sharded run has no trustworthy per-file measurement to evaluate them against — per-file
## `usec` is scrambled by eight processes competing for cores, which is why tb66 E6 kept the
## profile on the single-process path. `violations()` is handed an empty `files` array and
## therefore names no file, and this script prints that fact beside its verdict. A merged report
## that quietly reported "no per-file violations" would be claiming a check nobody ran.

const USAGE := "godot --headless --path . -s res://tools/check_budget.gd -- --totals=<path>"

## What `run_tests.sh` prints when this goes red, carried here so the fix is beside the failure
## rather than in a doc somebody has to know exists. Same wording as `test_suite_budget.gd`'s,
## because it is the same ratchet.
const RATCHET := (
	"This is a ratchet, not a wall — raise the number in test/support/suite_budget.gd and say "
	+ "why in the same commit, or find the work and remove it."
)


func _initialize() -> void:
	var totals_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--totals="):
			totals_path = arg.substr("--totals=".length())

	if totals_path == "":
		push_error("no --totals=<path> given. usage: %s" % USAGE)
		quit(2)
		return

	if not FileAccess.file_exists(totals_path):
		push_error("no such totals file: %s" % totals_path)
		quit(2)
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(totals_path))
	if not parsed is Dictionary:
		push_error(
			"%s is not a JSON object — the merge did not write what it says it does" % totals_path
		)
		quit(2)
		return

	var profile: Dictionary = parsed
	# **An empty `totals` is a failure, not a pass.** Every counter would read zero, every budget
	# would be satisfied, and a gate that reports "within budget" because it measured nothing is
	# the same silent-partial-success shape the merge already refuses for a dead shard.
	if (profile.get("totals", {}) as Dictionary).is_empty():
		push_error(
			"%s carries no totals — nothing to check, which is not the same as green" % totals_path
		)
		quit(2)
		return

	var violations: Array[String] = SuiteBudget.violations(profile)

	print("")
	print("--- work budget ---")
	print("  totals only — per-file caps are not checked on a sharded run (see this file's header)")
	# **Printed above the verdict, because it qualifies it.** A counter whose draw-caused half this
	# run did not record cannot be judged, and a green line with nothing beside it would read as a
	# check that happened. Not a failure: the next full gate writes the missing key.
	for note: String in SuiteBudget.unevaluable(profile):
		print("  %s" % note)
	if violations.is_empty():
		print("  within budget")
		quit(0)
		return
	for message: String in violations:
		print("  OVER BUDGET: %s" % message)
	print("  %s" % RATCHET)
	quit(1)
