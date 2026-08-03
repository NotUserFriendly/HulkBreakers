extends GutTest

## taskblock-54 Pass A: **`tile` means the walkable part and nothing else.** `cell` is the grid
## square — already the code's word (`Vector2i cell` everywhere) — and `tile` is reserved for the
## walkable part itself, a `floor_bulkhead` sitting inside a cell. Walkable parts needed their own
## word now that floors, walls, ramps and ladders are all `Part`s and only some are stood on.
##
## Before the sweep the word appeared **303 times** across `src`, `test` and `tools`, almost all of
## it meaning "cell in the casual sense".
##
## ## The boundary, now shared
##
## The first sweep used `\b…\b` and reported clean while `test_..._extraction_tiles` and
## `EXTRACTION_TILE_HEIGHT` still carried the word — `_` is a word character, so the pattern never
## looked inside an identifier. taskblock-55 moved the working rule into `VocabularySweep` and put
## all three vocabulary guards on it, since two of them had already been wrong the same way.
##
## Only `tileable` is allow-listed — ordinary English, as in "a ladder is *tileable* to arbitrary
## height". When a walkable part named `tile` exists in code, this list is where it earns its place.

const SELF_PATH := "res://test/unit/test_cell_vocabulary_guard.gd"
## Ordinary-English survivors, matched case-insensitively at the hit's own position.
const ALLOWED: Array[String] = ["tileable"]


func test_tile_is_reserved_for_the_walkable_part() -> void:
	var regex: RegEx = VocabularySweep.word_regex("tiles?")
	var offending: Array[String] = VocabularySweep.scan(
		[".gd"],
		SELF_PATH,
		func(path: String, line_number: int, line: String) -> String:
			if regex.search(line) == null or _is_allowed_only(line, regex):
				return ""
			return "%s:%d: %s" % [path, line_number, line.strip_edges()]
	)
	assert_eq(
		offending,
		[] as Array[String],
		(
			(
				"the reserved word survives meaning something other than the walkable part — `cell` is"
				+ " the grid square (taskblock-54 Pass A): %s"
			)
			% [offending]
		)
	)


## True when every hit on this line is a permitted ordinary-English word. Checked **per
## occurrence**, so a line carrying both `tileable` and a bare use is still reported — a
## whole-line exemption is how a sweep quietly stops sweeping.
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
