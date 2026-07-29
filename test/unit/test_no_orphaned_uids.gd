extends GutTest

## taskblock-48 Pass B follow-up: **no `.uid` without its script.**
##
## Godot writes a `.uid` beside every script it imports. If the script is deleted and
## the `.uid` is not, the next import tries to open a file that is not there and the
## whole run dies with `Cannot open file '...'` — before a single test executes.
##
## This is not hypothetical. Pass B's exit-code test wrote a throwaway test file, ran
## it in a subprocess, and deleted it; the subprocess's own import step wrote the
## `.uid` *after* that deletion, the orphan got committed, and the supervisor's next
## full gate died on it. The technique is gone (see `test_exit_code_probe.gd`) and
## this is the guard, because the failure lands on whoever runs next rather than on
## whoever caused it.
##
## Cheap: it walks the tree and stats files. No engine work, no imports.

## `addons/` is vendored and carries an orphan of its own (`menu_manager.gd.uid`).
## **Left alone deliberately** — editing a third-party addon to satisfy a project test
## trades a harmless inconsistency for a real merge conflict at the next GUT update,
## and it has evidently never broken a run. Excluded, and said out loud, rather than
## quietly making the check pass.
const EXCLUDED_ROOTS: Array[String] = ["res://addons"]


func _walk(path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for root: String in EXCLUDED_ROOTS:
		if path.begins_with(root):
			return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk(full, found)
		elif entry.ends_with(".uid"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func test_no_uid_file_is_missing_its_script() -> void:
	var uids: Array[String] = []
	_walk("res://src", uids)
	_walk("res://test", uids)
	_walk("res://tools", uids)

	var orphans: Array[String] = []
	for uid: String in uids:
		if not FileAccess.file_exists(uid.trim_suffix(".uid")):
			orphans.append(uid)

	gut.p("%d .uid file(s) checked" % uids.size())
	assert_gt(uids.size(), 100, "sanity: the walk actually found the tree")
	assert_eq(
		orphans,
		[] as Array[String],
		(
			("these .uid files have no script beside them and will break the next " + "import: %s")
			% [orphans]
		)
	)
