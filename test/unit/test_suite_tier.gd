extends GutTest

## taskblock-47 Pass C: **the fast gate is bout-free, and stays that way.**
##
## A fast gate that has silently stopped being fast is worse than no fast gate: people
## keep running it expecting seconds, and the thing it was protecting them from is
## back without anyone deciding it should be.
##
## So the tier list is checked against the profile's **own bout counter** every run,
## never against a directory. That distinction is not theoretical here — eight of the
## twelve bout-building files live under `test/unit/`, including the most expensive
## file in the suite, so a `skip integration/` rule would have declared the fast gate
## bout-free while it played almost all of them.
##
## Cheap by construction: it parses one JSON file and compares two sorted lists. It
## does not run either gate, because a test that ran the suite to check the suite
## would be the thing it is complaining about.

const PROFILE_PATH := "res://test/suite_profile.json"


func _profile() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert_not_null(file, "the committed profile must exist — regenerate it")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


# --- the tier list is the measured truth ----------------------------------------


## **The gate's own gate.** If a file starts building bouts and nobody adds it to the
## list, this fails — which is the point, because the alternative is the fast gate
## quietly getting slower until someone stops trusting it.
func test_the_fast_gate_skips_exactly_the_files_that_build_bouts() -> void:
	var measured: Array[String] = SuiteBudget.bout_building_files(_profile())
	var declared: Array[String] = SuiteTier.BOUT_FILES.duplicate()
	declared.sort()

	var unlisted: Array[String] = []
	for path: String in measured:
		if not declared.has(path):
			unlisted.append(path)
	var stale: Array[String] = []
	for path: String in declared:
		if not measured.has(path):
			stale.append(path)

	gut.p("%d bout-building file(s) measured, %d declared" % [measured.size(), declared.size()])
	assert_eq(
		unlisted,
		[] as Array[String],
		(
			(
				"these files build bouts but the fast gate does not skip them — add "
				+ "`should_skip_script()` and list them in `SuiteTier.BOUT_FILES`: %s"
			)
			% [unlisted]
		)
	)
	assert_eq(
		stale,
		[] as Array[String],
		(
			(
				"these are skipped by the fast gate but no longer build bouts — drop them "
				+ "from the list, or the fast gate is skipping work for free: %s"
			)
			% [stale]
		)
	)


## **The list is not a directory in disguise**, and this is the assertion that proves
## the directory rule would have been wrong rather than merely arguing it.
func test_bout_files_are_not_confined_to_one_directory() -> void:
	var outside: Array[String] = []
	for path: String in SuiteTier.BOUT_FILES:
		if not path.begins_with("res://test/integration/"):
			outside.append(path)

	gut.p(
		(
			"%d of %d bout files live outside integration/"
			% [outside.size(), SuiteTier.BOUT_FILES.size()]
		)
	)
	assert_gt(
		outside.size(),
		SuiteTier.BOUT_FILES.size() / 2,
		"most bout-building files are not in integration/ — a directory rule cannot work"
	)


## The full gate is a strict superset of the fast one: the skip only ever subtracts,
## so nothing exists in the fast tier that the full gate would miss.
##
## **Asserted as agreement with the gate actually running**, not against a fixed
## value — this file has to pass under both gates, and a test that hardcodes one of
## them is a test that goes red exactly when someone uses the other.
func test_the_skip_only_ever_subtracts() -> void:
	var skip: Variant = SuiteTier.skip_if_fast()

	if SuiteTier.is_fast_gate():
		assert_eq(typeof(skip), TYPE_STRING, "fast gate: a String, which is what GUT skips on")
	else:
		# **`false`, not `""`.** GUT skips on any String, empty included, so an
		# empty-string "don't skip" silently removed every bout file from the full
		# gate — caught by the suite going green with 11 fewer files in it.
		assert_eq(skip, false, "full gate: skips nothing")
		assert_eq(typeof(skip), TYPE_BOOL, "and says so in GUT's own terms")


# --- the switch itself ------------------------------------------------------------


## The environment variable is the whole mechanism, so it gets a test. GUT owns the
## command line, which is why this is not a flag.
func test_the_switch_agrees_with_the_environment() -> void:
	var set_in_env: bool = OS.get_environment(SuiteTier.FAST_GATE_ENV) != ""

	assert_eq(
		SuiteTier.is_fast_gate(), set_in_env, "the switch reads the environment and nothing else"
	)


## **Restores the variable rather than clearing it, and that is not fussiness.**
##
## The first version set it and then set it back to `""`. `OS.set_environment` is
## process-wide, so under the fast gate that switched the gate OFF for every file GUT
## had not reached yet — this file sorts before `unit/view/`, and exactly the three
## bout-building files under it ran their bouts anyway. The fast gate silently
## stopped being fast partway through, which is the precise failure this pass exists
## to prevent, introduced by the test written to prevent it.
func test_the_skip_reason_says_what_to_run_instead() -> void:
	var original: String = OS.get_environment(SuiteTier.FAST_GATE_ENV)

	OS.set_environment(SuiteTier.FAST_GATE_ENV, "1")
	var reason: Variant = SuiteTier.skip_if_fast()
	OS.set_environment(SuiteTier.FAST_GATE_ENV, original)

	gut.p(reason)
	assert_eq(typeof(reason), TYPE_STRING, "fast mode produces a String, which is what skips")
	assert_true(String(reason).contains("run_tests.sh"), "and it names the command that runs them")
	assert_eq(
		OS.get_environment(SuiteTier.FAST_GATE_ENV),
		original,
		"and the environment is left exactly as it was found"
	)


## Every listed file must actually implement the hook, or listing it does nothing. The
## list and the hook are two halves of one mechanism and this is the half that would
## fail silently.
func test_every_listed_file_implements_the_skip_hook() -> void:
	var missing: Array[String] = []
	for path: String in SuiteTier.BOUT_FILES:
		var script: GDScript = load(path)
		if script == null:
			missing.append("%s (did not load)" % path)
			continue
		var source: String = script.source_code
		if not source.contains("func should_skip_script()"):
			missing.append(path)

	assert_eq(missing, [] as Array[String], "listed but not hooked: %s" % [missing])
