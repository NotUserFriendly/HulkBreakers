class_name VocabularySweep
extends RefCounted

## taskblock-55 Pass A: **the one word-boundary rule, and the one directory walk, that every
## vocabulary guard shares.**
##
## Two guards enforce retired vocabulary — `void` (tb40) and the `HULK_` tooling prefix (tb50).
## Each had grown its own copy of the same recursive scan, and they had grown *different* ideas
## of what a word boundary is. This is the one implementation.
##
## ## taskblock-55 Pass B: there were three, and the third retired
##
## A guard on the reserved walkable-part word came off with taskblock-54's sweep and is gone
## again here, because **the two jobs are not the same job**. `void` and `HULK_` are *retired*:
## they must never appear, so a total ban is exactly the right instrument and stays. The third
## word was *reserved* — swept out of its wrong sense in tb54 specifically so this block could
## give it its right one — and a total ban cannot tell a correct use from an incorrect one. It
## failed the first code that used the word as intended.
##
## Retiring it is not a loss of coverage, because the coverage it had was for a migration that
## finished: 303 wrong uses were renamed, and the reserved sense is now carried by real code and
## by `docs/00`'s terminology table rather than by a grep. **A guard built to hold a word empty
## has nothing left to do once the word is filled.**
##
## ## Why `\b` is the wrong boundary, which is what this exists to fix
##
## GDScript's `\b` follows the usual convention: `_` is a **word character**, so `\bvoid\b` does
## not match inside `_finalize_walls_and_void`, and `\btiles?\b` does not match inside
## `EXTRACTION_TILE_HEIGHT`. Both guards reported clean while the retired word was plainly still
## in the tree — taskblock-54 found this for the reserved word and taskblock-55 re-ran the rest.
##
## **The rule that works is a non-letter on each side.** `_` then breaks the token, so
## `and_void` and `EXTRACTION_TILE_HEIGHT` are caught — and every genuine substring is still
## excluded for free, because each has a *letter* on one side: `avoid`, `devoid`, `hostile`,
## `percentile`, `volatile`, `versatile`, `projectile`, `stiletto`. **No allowlist is needed for
## any of them**, which is the property that makes this boundary worth sharing rather than each
## guard maintaining its own exceptions.
##
## Digits are deliberately *not* boundary characters on the exclusion side: `void2` is the
## retired word with a suffix, not a different word.

## Roots every guard scans. A retired word in a tool rots exactly as fast as one in `src`.
const SCAN_ROOTS: Array[String] = ["res://src", "res://test", "res://tools"]

## **This file is exempt from every sweep it runs**, for the same reason each guard already
## exempts its own `SELF_PATH`: explaining a rule requires naming the word it forbids, and this
## file explains both of them at once. That is not a hole in the sweep — it is the guard
## implementation, which moved here when three copies were merged into one, and the exemption
## moved with it.
##
## Stated once, here, rather than added to each guard's own allowlist: an allowlist entry is a
## permission for a *word*, and this is a permission for a *file that is part of the mechanism*.
## Conflating the two is how an allowlist grows entries nobody can justify later.
const SELF_PATH := "res://test/support/vocabulary_sweep.gd"


## A case-insensitive `RegEx` matching `word` only when neither neighbour is a letter.
##
## Callers that need a pattern rather than a compiled object (a prefix rule like `HULK_`, say)
## should use `BOUNDARY_BEFORE`/`BOUNDARY_AFTER` around their own body instead of rebuilding the
## lookarounds by hand — that is the drift this class exists to prevent.
static func word_regex(word: String) -> RegEx:
	var regex := RegEx.new()
	regex.compile("(?i)%s%s%s" % [boundary_before(), word, boundary_after()])
	return regex


## The lookbehind and lookahead, exposed so a guard whose body is not a plain word can still use
## the shared rule.
static func boundary_before() -> String:
	return "(?<![A-Za-z])"


static func boundary_after() -> String:
	return "(?![A-Za-z])"


## Walks `roots` and hands every line of every matching file to `on_line`, collecting whatever it
## returns that is not empty.
##
## `on_line` is `Callable(path: String, line_number: int, line: String) -> String` — returning
## `""` for a clean line and an offender description otherwise. **Each guard keeps its own
## policy** (which allowlist applies, whether comments count, whether `-> void` is exempt) and
## shares only the walk and the boundary, because the policies genuinely differ and pretending
## otherwise would be a worse coupling than the duplication it replaced.
##
## `self_path` is skipped, as is this file — every guard's own doc comment has to spell out the
## word it forbids, and so does the shared implementation. See `SELF_PATH` above.
static func scan(extensions: Array[String], self_path: String, on_line: Callable) -> Array[String]:
	var offending: Array[String] = []
	for root: String in SCAN_ROOTS:
		_scan_dir(root, extensions, self_path, on_line, offending)
	return offending


static func _scan_dir(
	path: String,
	extensions: Array[String],
	self_path: String,
	on_line: Callable,
	offending: Array[String]
) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full_path: String = path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full_path, extensions, self_path, on_line, offending)
		elif (
			full_path != self_path and full_path != SELF_PATH and _has_extension(entry, extensions)
		):
			_scan_file(full_path, on_line, offending)
		entry = dir.get_next()
	dir.list_dir_end()


static func _has_extension(entry: String, extensions: Array[String]) -> bool:
	for extension: String in extensions:
		if entry.ends_with(extension):
			return true
	return false


static func _scan_file(path: String, on_line: Callable, offending: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var line_number := 0
	while not file.eof_reached():
		var line: String = file.get_line()
		line_number += 1
		var offence: String = on_line.call(path, line_number, line)
		if offence != "":
			offending.append(offence)
