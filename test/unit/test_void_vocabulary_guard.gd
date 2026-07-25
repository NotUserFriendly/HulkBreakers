extends GutTest

## taskblock-40 Pass A: enforces the taskblock's own acceptance grep —
## `grep -rniE "\bvoid\b" --include=*.gd src test tools | grep -v -- "-> void"`
## must return zero lines — as a real test rather than a one-off shell
## command nobody re-runs. Modeled on `test_map_gen.gd`'s
## `test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking`
## file-scan pattern, but repo-wide rather than single-file. GDScript's
## own `-> void` return annotation is unavoidable and explicitly exempted
## (filtered by literal substring, matching the acceptance grep exactly);
## every other occurrence of the word is a live regression back toward
## "void" meaning physical absence — retired taskblock-39 Pass D, made a
## grep-clean rule taskblock-40 Pass A.
const SCAN_ROOTS: Array[String] = ["res://src", "res://test", "res://tools"]
## This file's own doc comment above necessarily spells out the banned
## word to explain the rule — exempted from scanning itself, same as any
## guard test is exempt from the rule it enforces.
const SELF_PATH := "res://test/unit/test_void_vocabulary_guard.gd"


func test_no_gd_file_uses_void_for_anything_but_the_return_annotation() -> void:
	var regex := RegEx.new()
	regex.compile("(?i)\\bvoid\\b")
	var offending: Array[String] = []
	for root: String in SCAN_ROOTS:
		_scan_dir(root, regex, offending)
	assert_eq(
		offending,
		[] as Array[String],
		'"void" survives outside `-> void` (lore-only from taskblock-39/40 on): %s' % [offending]
	)


func _scan_dir(path: String, regex: RegEx, offending: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full_path: String = path + "/" + entry
		if dir.current_is_dir():
			_scan_dir(full_path, regex, offending)
		elif entry.ends_with(".gd") and full_path != SELF_PATH:
			_scan_file(full_path, regex, offending)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, regex: RegEx, offending: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var line_number := 0
	while not file.eof_reached():
		var line: String = file.get_line()
		line_number += 1
		if regex.search(line) != null and not ("-> void" in line):
			offending.append("%s:%d: %s" % [path, line_number, line.strip_edges()])
