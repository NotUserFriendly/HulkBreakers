extends GutTest

## taskblock-54 Pass A: enforces the block's own acceptance grep — **`tile` means the walkable
## part and nothing else** — as a real test rather than a shell command nobody re-runs. Modelled
## on taskblock-40's own vocabulary guard, which does the same job for the word that block
## retired. **That word is deliberately not spelled anywhere here** — its guard scans this file,
## so naming it makes each of these two tests fail the other. Two vocabulary guards policing each
## other is a good sign the rule is real; the prose just has to be careful.
##
## ## The rule
##
## `cell` is the grid square; it is already the code's word (`Vector2i cell` everywhere).
## **`tile` is reserved for the walkable part itself** — a `floor_bulkhead` sitting inside a cell
## is a tile. Giving walkable parts their own word matters now that floors, walls, ramps and
## ladders are all `Part`s and only some of them are stood on.
##
## Before this sweep the word appeared **303 times** across `src`, `test` and `tools`, almost all
## of it meaning "cell in the casual sense" — nearly four times the size of taskblock-40's sweep.
##
## ## Why the boundary is "not a letter" rather than `\b`
##
## `\btiles?\b` treats `_` as a boundary character, so it reports clean on
## `test_..._extraction_tiles` and `EXTRACTION_TILE_HEIGHT` while the word is plainly still
## there — the first version of this sweep did exactly that and left a tail of identifiers
## behind. Requiring a **non-letter** on each side catches those, and gets every genuine
## substring right for free with no exception list to maintain: `hostile`, `percentile`,
## `volatile`, `versatile`, `projectile` and `stiletto` all have a letter on one side.
##
## ## What is allowed through
##
## Only `tileable` — ordinary English, as in "a ladder is *tileable* to arbitrary height". When
## a walkable part named `tile` actually exists in code, this list is where it earns its place,
## and the reserved sense is why the word was kept at all.
const SCAN_ROOTS: Array[String] = ["res://src", "res://test", "res://tools"]
## This file necessarily spells out the word it polices, in prose, to explain the rule — exempt
## from itself, the same way taskblock-40's guard is exempt from its own.
const SELF_PATH := "res://test/unit/test_cell_vocabulary_guard.gd"
## Ordinary-English survivors. Matched case-insensitively as whole words by the same non-letter
## boundary rule, so adding one here cannot accidentally permit a bare `tile`.
const ALLOWED: Array[String] = ["tileable"]


func test_tile_is_reserved_for_the_walkable_part() -> void:
	var regex := RegEx.new()
	regex.compile("(?i)(?<![A-Za-z])tiles?(?![A-Za-z])")
	var offending: Array[String] = []
	for root: String in SCAN_ROOTS:
		_scan_dir(root, regex, offending)
	assert_eq(
		offending,
		[] as Array[String],
		(
			(
				'"tile" survives meaning something other than the walkable part — `cell` is the grid'
				+ " square (taskblock-54 Pass A): %s"
			)
			% [offending]
		)
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
		if regex.search(line) == null:
			continue
		if _is_allowed_only(line, regex):
			continue
		offending.append("%s:%d: %s" % [path, line_number, line.strip_edges()])


## True when every hit on this line is one of the permitted ordinary-English words. Checked per
## occurrence rather than per line, so a line carrying both `tileable` and a bare `tile` is still
## reported — a whole-line exemption is how a sweep quietly stops sweeping.
func _is_allowed_only(line: String, regex: RegEx) -> bool:
	for found: RegExMatch in regex.search_all(line):
		var start: int = found.get_start()
		var permitted := false
		for word: String in ALLOWED:
			if line.substr(start, word.length()).to_lower() == word:
				permitted = true
				break
		if not permitted:
			return false
	return true
