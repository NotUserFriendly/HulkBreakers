extends GutTest

## taskblock-40 Pass A: enforces that the retired word for physical absence survives nowhere but
## GDScript's own `-> void` return annotation. Every other occurrence is a live regression back
## toward it meaning something — retired taskblock-39 Pass D, made a grep-clean rule taskblock-40
## Pass A.
##
## ## taskblock-55 Pass A: the boundary was wrong, and it was hiding a real one
##
## This used `\b…\b`, and `_` is a **word character**, so the pattern did not match inside an
## identifier. It reported clean while `grid_fixture.gd` still named
## `MapGen._finalize_walls_and_void` — a function that had also been *renamed*, so the stale
## vocabulary was sitting on top of a dangling reference.
##
## It now shares `VocabularySweep`'s non-letter boundary with the other two vocabulary guards: one
## implementation, not three that drift apart. **Their reserved words are deliberately not
## named here** — each guard scans the others, so spelling them makes these tests fail one
## another. That boundary excludes `avoid` and `devoid` for
## free, because each has a letter before the `v` — **no allowlist needed**.

const SELF_PATH := "res://test/unit/test_void_vocabulary_guard.gd"
## The one unavoidable use: GDScript's own return annotation. Matched as a literal substring,
## exactly as taskblock-40's acceptance grep did.
const RETURN_ANNOTATION := "-> void"


func test_no_gd_file_uses_the_retired_word_outside_the_return_annotation() -> void:
	var regex: RegEx = VocabularySweep.word_regex("void")
	var offending: Array[String] = VocabularySweep.scan(
		[".gd"],
		SELF_PATH,
		func(path: String, line_number: int, line: String) -> String:
			if regex.search(line) == null or RETURN_ANNOTATION in line:
				return ""
			return "%s:%d: %s" % [path, line_number, line.strip_edges()]
	)
	assert_eq(
		offending,
		[] as Array[String],
		(
			"the retired word survives outside `-> void` (lore-only from taskblock-39/40 on): %s"
			% [offending]
		)
	)


## The boundary's own property, pinned so a future "simplification" back to `\b` fails loudly
## rather than quietly reporting clean. `avoid` must stay legal and `and_void` must not.
func test_the_shared_boundary_catches_an_underscore_join_and_still_allows_avoid() -> void:
	var regex: RegEx = VocabularySweep.word_regex("void")
	assert_null(regex.search("var avoid_this := true"), "a letter before it is a different word")
	assert_null(regex.search("## devoid of meaning"), "so is this one")
	assert_not_null(regex.search("_finalize_walls_and_void"), "an underscore join is the word")
	assert_not_null(regex.search("void_cells"), "and so is a trailing join")
