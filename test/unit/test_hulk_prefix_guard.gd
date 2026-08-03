extends GutTest

## taskblock-50 Pass A: **the `HULK_` prefix is retired from tooling identifiers.**
##
## `HULK_FAST_GATE`, `HULK_TEST_ROOT` and `HULK_FORCE_TEST_FAILURE` are now `HB_…`. The
## prefix was doing a real job — environment variables are global to the process, so a
## bare `FAST_GATE` could collide with anything else on the machine — and `HB_` does that
## job identically without spending a setting word on a shell variable.
##
## ## What is banned is the prefix, not the word
##
## This game is about hulks. `Hulk`, `HulkTheme`, `hulk_seed`, the whole domain vocabulary
## stays, and a case-insensitive grep for the word would flag hundreds of correct uses.
## What is retired is the **screaming-case `HULK_` prefix on an identifier**, which only
## ever meant "this belongs to our tooling".
##
## `LootTable.HULK_SOURCE` keeps it, and is allow-listed by name below: loot sourced from
## the hulk is the word meaning what it means, which is the use the vocabulary exists for.
## The allow-list is data — a future domain constant is added there, not by loosening the
## rule.
##
## Shell scripts are scanned too. The three retired names were environment variables and
## `run_tests.sh` is where they were read; a sweep that only looked at GDScript would have
## declared this clean while the shell still exported the old names.

const SCAN_ROOTS: Array[String] = ["res://src", "res://test", "res://tools"]
const SCAN_EXTENSIONS: Array[String] = [".gd", ".sh"]

## Domain constants that legitimately carry the prefix, by full name.
const ALLOWED: Array[String] = ["HULK_SOURCE"]

## This file necessarily spells out the retired names to explain the rule — exempt from
## its own scan, as any guard test is.
const SELF_PATH := "res://test/unit/test_hulk_prefix_guard.gd"


## taskblock-55 Pass A: the prefix now carries `VocabularySweep`'s **shared** left boundary
## rather than none at all. This guard was never under-reporting the way the others
## vocabulary guards were — a prefix pattern with no lookbehind matches *more*, not less — but
## all three read their boundary from one place now, so a future correction lands everywhere
## instead of in whichever guard someone happened to be looking at.
func _offenders_in(text: String, path: String) -> Array[String]:
	var regex: RegEx = _line_regex()
	var found: Array[String] = []
	var line_number := 0
	for line: String in text.split("\n"):
		line_number += 1
		for hit: RegExMatch in regex.search_all(line):
			if not ALLOWED.has(hit.get_string()):
				found.append("%s:%d: %s" % [path, line_number, hit.get_string()])
	return found


func test_no_tooling_identifier_carries_the_hulk_prefix() -> void:
	var offending: Array[String] = VocabularySweep.scan(
		SCAN_EXTENSIONS,
		SELF_PATH,
		func(path: String, line_number: int, line: String) -> String:
			for hit: RegExMatch in _line_regex().search_all(line):
				if not ALLOWED.has(hit.get_string()):
					return "%s:%d: %s" % [path, line_number, hit.get_string()]
			return ""
	)
	# The shell entry point sits outside the shared roots and is where the retired names were
	# actually exported — a sweep that only looked at the roots would call this clean while
	# `run_tests.sh` still exported them.
	offending.append_array(
		_offenders_in(FileAccess.get_file_as_string("res://run_tests.sh"), "res://run_tests.sh")
	)
	assert_eq(
		offending,
		[] as Array[String],
		"HULK_ survives on a tooling identifier (HB_ from taskblock-50 on): %s" % [offending]
	)


## **The companion assertion.** A guard whose regex never matched anything would pass this
## file exactly as a working one does — `docs/11`'s named failure mode, and the reason
## every restriction in this repo is asserted in both directions. Feeding it the retired
## names proves the scan can still see them.
func test_the_guard_would_actually_catch_a_reintroduction() -> void:
	var reintroduced := 'var gate := OS.get_environment("HULK_FAST_GATE")'
	assert_eq(
		_offenders_in(reintroduced, "res://fake.gd").size(),
		1,
		"a reintroduced HULK_ name is caught"
	)
	assert_eq(
		_offenders_in("LootTable.HULK_SOURCE", "res://fake.gd").size(),
		0,
		"and the allow-listed domain constant is not"
	)
	assert_eq(
		_offenders_in("var hulk := HulkTheme.build()", "res://fake.gd").size(),
		0,
		"nor is the domain word itself — only the screaming-case prefix is retired"
	)


## The rename is only finished if the new names are actually in use. Asserting the absence
## of the old ones alone would pass a repo where all three variables had simply been
## deleted and the features silently stopped working.
func test_the_replacement_names_are_the_ones_in_use() -> void:
	var shell: String = FileAccess.get_file_as_string("res://run_tests.sh")
	assert_true(shell.contains("HB_FAST_GATE"), "the fast gate reads HB_FAST_GATE")
	assert_true(shell.contains("HB_TEST_ROOT"), "the test-root seam reads HB_TEST_ROOT")
	assert_eq(SuiteTier.FAST_GATE_ENV, "HB_FAST_GATE", "and the tier agrees with the shell")
	assert_eq(
		TestExitCodeProbe.FORCE_FAILURE_ENV,
		"HB_FORCE_TEST_FAILURE",
		"as does the force-failure probe",
	)


func _line_regex() -> RegEx:
	var regex := RegEx.new()
	regex.compile("%sHULK_[A-Z0-9_]+" % VocabularySweep.boundary_before())
	return regex
