extends GutTest

## taskblock-45 Pass E: **the engagement-score planner is gone, and this is what
## stops it coming back by reference.**
##
## The supervisor's requirement was "cleared out completely, no hanging
## references". A prose claim to that effect is worth nothing a month later —
## BR40.02 was exactly a rename that orphaned two files for fifteen taskblocks
## because nothing re-ran them, and BR45.02 was the same failure again, one
## directory over. So the sweep is a test, in the shape of taskblock-40's own
## vocabulary sweep.
##
## **Comments and doc-comments are included deliberately.** A stale comment
## describing a deleted system is precisely what `docs/SUPERSEDED.md` exists to
## prevent, and a sweep that skipped them would let the codebase keep explaining
## itself in terms of a file nobody can read.
##
## This will eventually delete itself. Once nothing in the tree remembers the old
## planner and nobody is tempted to write its name, the guard is pure ceremony —
## but that day is not the day the planner is deleted, which is the only day the
## reference could plausibly creep back.
##
## **taskblock-63 Pass A: the file-cap half of this guard has moved out and its
## number has changed.** `test_the_linter_file_cap_came_back_down` asserted
## `max-file-lines: 1000` here, on the reasoning that the cap coming back down was
## the objective proof the planner was gone. **That proof was delivered and cannot
## be delivered twice** — the planner is gone, the sweep below is what keeps it
## gone, and a frozen number in a file about a deleted planner became the reason an
## unrelated cap decision could not be made. The cap is now a project choice at
## 2500 (`BR62.02`: the 1000 was gdlint's default, inherited rather than decided,
## and it penalised exactly the files that explain themselves). The *mechanism* the
## old assertion was valued for — the cap cannot drift without someone saying why
## in a test — survives in `test/unit/test_lint_config.gd`.

## The retired planner's class name and its file. Both, because a reference can be
## either — `UnitAI.plan_turn` in code, `unit_ai.gd` in a comment or a path.
const RETIRED_NAMES: Array[String] = ["UnitAI", "unit_ai.gd"]

## Directories swept. `tools/` is on the list because leaving it off is what
## BR45.02 was: the AI planning bench referenced the planner's internals and
## stopped compiling for two whole taskblocks with nothing to notice.
const SWEPT_DIRS: Array[String] = ["res://src", "res://test", "res://tools"]

## This file names the retired planner on purpose — it is the guard's own subject.
const SELF_PATH := "res://test/unit/test_retired_planner_sweep.gd"


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			var full: String = "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	found.sort()
	return found


func _offending_lines(path: String) -> Array[String]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var offences: Array[String] = []
	var line_number := 0
	for raw: String in file.get_as_text().split("\n"):
		line_number += 1
		for needle: String in RETIRED_NAMES:
			if raw.contains(needle):
				offences.append("%s:%d  %s" % [path, line_number, raw.strip_edges()])
	return offences


## The sweep itself. Reports EVERY offending line rather than the first, because a
## reintroduction is usually a handful of lines in one file and fixing them one
## red run at a time is how a guard becomes something people route around.
func test_nothing_in_the_tree_names_the_retired_planner() -> void:
	var offences: Array[String] = []
	var swept := 0
	for root: String in SWEPT_DIRS:
		for path: String in _gd_files(root):
			if path == SELF_PATH:
				continue
			swept += 1
			offences.append_array(_offending_lines(path))

	assert_gt(swept, 200, "sanity: the sweep really walked the tree")
	assert_eq(
		offences,
		[] as Array[String],
		(
			"the retired engagement-score planner is named in %d place(s):\n%s"
			% [offences.size(), "\n".join(offences)]
		)
	)


## A guard that can only ever pass is not a guard. This proves the matcher fires on
## the exact string it is looking for, so the empty result above means the tree is
## clean rather than the check being broken.
func test_the_sweep_would_actually_catch_a_reintroduction() -> void:
	var offences: Array[String] = _offending_lines(SELF_PATH)

	assert_gt(offences.size(), 0, "this file names the planner, and the matcher sees it")
