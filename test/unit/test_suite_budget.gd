extends GutTest

## taskblock-47 Pass B: **the test for the tests.**
##
## Reads the committed profile and fails when the suite's work has grown past its
## budget. Deliberately cheap — it parses one JSON file and compares integers. **It
## must never re-run anything**: a budget check that costs a suite run to answer is a
## thing people disable.
##
## ## What "cheap" costs in coverage, stated rather than hidden
##
## Because it reads the committed profile rather than measuring the live run, it
## catches a regression when the profile is regenerated, not the instant it lands.
## That is the trade, and it is the right one: the alternative is measuring the whole
## suite from inside the suite, which is either circular or expensive. The profile is
## regenerated per taskblock, which is the same cadence the numbers move at.
##
## The checker's own logic is tested against synthetic profiles, so its behaviour is
## pinned regardless of what the committed one currently says.

const PROFILE_PATH := "res://test/suite_profile.json"


func _profile() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	assert_not_null(file, "the committed profile must exist — regenerate it")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary, "the profile must be a JSON object")
	return parsed if parsed is Dictionary else {}


# --- the budget itself ----------------------------------------------------------


## **The gate.** Everything else in this file exists to make this one trustworthy.
func test_the_suite_is_within_its_work_budget() -> void:
	var violations: Array[String] = SuiteBudget.violations(_profile())

	for message: String in violations:
		gut.p("OVER BUDGET: %s" % message)
	assert_eq(
		violations.size(),
		0,
		(
			(
				"the suite's work grew past budget:\n  %s\n\nThis is a ratchet, not a wall — "
				+ "raise the number in `suite_budget.gd` and say why in the same commit, or "
				+ "find the work and remove it."
			)
			% "\n  ".join(violations)
		)
	)


## The budget has to describe the suite that exists, or it is guarding a fiction. A
## baseline that has drifted far below reality means someone changed the suite and
## never re-ratcheted, and the gate has been passing on slack ever since.
func test_the_recorded_baseline_still_resembles_the_measured_suite() -> void:
	var totals: Dictionary = _profile().get("totals", {})

	var profile: Dictionary = _profile()
	for counter: String in SuiteBudget.GATED:
		# **Checked, not indexed.** Gating a counter with no baseline used to raise a
		# runtime error here, and under `-d` that is a debugger break: the run hung at a
		# `debug>` prompt instead of reporting anything. Adding `ui_builds` to `GATED`
		# without a baseline is exactly how it happened.
		assert_true(
			SuiteBudget.BASELINE.has(counter), "%s is gated but has no BASELINE entry" % counter
		)
		if not SuiteBudget.BASELINE.has(counter):
			continue
		var baseline: int = int(SuiteBudget.BASELINE[counter])
		var observed: int = int(totals.get(counter, 0))
		# The `turns` baseline is the total minus the randomly-sampled file, so the
		# measured side has to be too — comparing the raw total against it would be
		# comparing two different quantities and calling the difference drift.
		if counter == "turns":
			observed -= SuiteBudget._excluded_turns(profile)
		gut.p("%-8s baseline %d, measured %d" % [counter, baseline, observed])
		assert_gt(observed, 0, "%s should be non-zero in a real profile" % counter)
		# Below budget is the passing direction; this catches the *other* drift —
		# a baseline left far above what the suite now does, which is a budget with
		# nothing in it.
		assert_gt(
			float(observed),
			float(baseline) * 0.5,
			(
				(
					"%s has fallen to less than half its baseline — re-ratchet the budget "
					+ "down or it is guarding nothing"
				)
				% counter
			)
		)


# --- the checker's own behaviour, pinned on synthetic input ----------------------


func _synthetic(totals: Dictionary, files: Array = []) -> Dictionary:
	return {"totals": totals, "files": files}


func test_a_profile_at_the_baseline_passes() -> void:
	assert_eq(SuiteBudget.violations(_synthetic(SuiteBudget.BASELINE.duplicate())).size(), 0)


## Exactly at the limit is a pass; one over is a failure. Pinned because an
## off-by-one here makes the budget either unreachable or permanently red.
func test_the_boundary_is_inclusive() -> void:
	var at_limit: Dictionary = SuiteBudget.BASELINE.duplicate()
	at_limit["turns"] = SuiteBudget.limit_for("turns")
	assert_eq(SuiteBudget.violations(_synthetic(at_limit)).size(), 0, "exactly at budget passes")

	at_limit["turns"] = SuiteBudget.limit_for("turns") + 1
	assert_eq(SuiteBudget.violations(_synthetic(at_limit)).size(), 1, "one over fails")


## **The acceptance the taskblock names: the message says which file and by how
## much.** "The suite got more expensive" is not something anyone can act on.
func test_going_over_names_the_file_and_the_delta() -> void:
	var path: String = SuiteBudget.PER_FILE.keys()[0]
	var cap: int = int(SuiteBudget.PER_FILE[path]["turns"])
	var profile: Dictionary = _synthetic(
		SuiteBudget.BASELINE.duplicate(), [{"path": path, "turns": cap + 40, "bouts": 0}]
	)

	var violations: Array[String] = SuiteBudget.violations(profile)

	assert_eq(violations.size(), 1)
	gut.p(violations[0])
	assert_true(violations[0].contains(path.replace("res://test/", "")), "names the file")
	assert_true(violations[0].contains("+40"), "and states the delta")


## Every violation at once, not the first one. A change that pushes three files over
## is one investigation; reporting it as three consecutive red runs makes it three.
func test_every_violation_is_reported_not_just_the_first() -> void:
	var over: Dictionary = {}
	for counter: String in SuiteBudget.GATED:
		over[counter] = SuiteBudget.limit_for(counter) * 2

	var violations: Array[String] = SuiteBudget.violations(_synthetic(over))

	assert_eq(violations.size(), SuiteBudget.GATED.size(), "one per gated counter")


## A counter that is measured but not gated must not fail the build. `candidates` and
## `shot_planes` move with how the planner scores rather than with how much the suite
## asks of it, and an AI change failing a suite-cost test is the false positive that
## gets budgets deleted.
func test_an_ungated_counter_does_not_fail_the_build() -> void:
	var inflated: Dictionary = SuiteBudget.BASELINE.duplicate()
	inflated["candidates"] = int(inflated["candidates"]) * 100
	inflated["shot_planes"] = int(inflated["shot_planes"]) * 100

	assert_eq(SuiteBudget.violations(_synthetic(inflated)).size(), 0)
	assert_false(SuiteBudget.GATED.has("candidates"), "and it is ungated on purpose")


## A file with no entry in the per-file table is governed by the suite total alone —
## it must not silently pass *or* silently fail.
func test_a_file_without_its_own_budget_is_ignored_per_file() -> void:
	var profile: Dictionary = _synthetic(
		SuiteBudget.BASELINE.duplicate(),
		[{"path": "res://test/unit/logic/test_nothing_special.gd", "turns": 999999, "bouts": 9999}]
	)

	assert_eq(SuiteBudget.violations(profile).size(), 0, "no per-file entry, no per-file verdict")


# --- the tier definition Pass C builds on ---------------------------------------


## Bout-building files are identified by **the counter, never a directory glob** —
## a glob goes stale the moment someone adds a bout to a unit test, and the whole
## point of the fast tier is that it cannot quietly acquire one.
func test_bout_building_files_come_from_the_counter() -> void:
	var files: Array[String] = SuiteBudget.bout_building_files(_profile())

	gut.p("%d file(s) build bouts: %s" % [files.size(), files])
	assert_gt(files.size(), 0, "sanity: some file builds a bout")
	assert_true(
		files.has("res://test/unit/logic/test_completion_sampler.gd"),
		"the heaviest bout file is in the list"
	)
	# The counter finds them wherever they live — three of these are under unit/,
	# which is exactly why a directory glob would be wrong.
	var outside_integration := 0
	for path: String in files:
		if not path.begins_with("res://test/integration/"):
			outside_integration += 1
	assert_gt(outside_integration, 0, "bout-building files are not confined to integration/")


## **A quantity the suite does not control cannot be budgeted**, and pretending
## otherwise produces exactly the flaky threshold this file was written against.
##
## `test_full_mission.gd` seeds its sample from the clock deliberately — taskblock-46
## spent a pass establishing that, because a fixed window was measuring the wrong
## thing. Eight bouts each ending somewhere between ~10 turns and the 100-turn cap
## means its turn count swings by hundreds. Measured across three full runs, the suite
## total came out at **1680, 1578 and 1385 turns — a 19% spread against 15%
## headroom**, so the budget would eventually have gone red on nobody's change.
##
## The fix is exclusion, not a bigger number: its *bouts* are still gated, because
## that count is exactly `SAMPLE_SEEDS` and holds still.
func test_the_randomly_sampled_file_is_excluded_from_the_turns_budget() -> void:
	assert_true(
		SuiteBudget.TURNS_EXCLUDED.has("res://test/integration/test_full_mission.gd"),
		"the file that samples from the clock is excluded from the turns gate",
	)

	# Its turns can swing by any amount without tripping the budget...
	var wild: Dictionary = SuiteBudget.BASELINE.duplicate()
	wild["turns"] = int(SuiteBudget.BASELINE["turns"]) + 5000
	var profile: Dictionary = {
		"totals": wild,
		"files":
		[{"path": "res://test/integration/test_full_mission.gd", "turns": 5000, "bouts": 8}],
	}
	assert_eq(
		SuiteBudget.violations(profile).size(),
		0,
		"a wild swing in the sampled file's turns must not fail the build",
	)

	# ...but the same swing anywhere else still does.
	var elsewhere: Dictionary = {
		"totals": wild,
		"files": [{"path": "res://test/unit/logic/test_something.gd", "turns": 5000, "bouts": 0}],
	}
	assert_gt(
		SuiteBudget.violations(elsewhere).size(),
		0,
		"turns growing outside the excluded file is still a regression",
	)


## And the exclusion must not become a hiding place. A file listed here is exempt from
## the turns gate entirely, so the list staying short is the property worth pinning.
func test_the_exclusion_list_stays_small_and_gates_bouts_regardless() -> void:
	assert_lt(SuiteBudget.TURNS_EXCLUDED.size(), 3, "exclusions are exceptional, not a habit")
	assert_true(SuiteBudget.GATED.has("bouts"), "bouts are deterministic and stay gated")


## **Every key in the profile measures work.** The profile is built by summing each row's
## fields, so any field added to a row for bookkeeping is summed too unless it is
## explicitly excluded — and taskblock-49 Pass A added `test` (the name) and `order` (the
## declaration index) to per-test rows without excluding them. They aggregated into every
## file row and into `totals`, where `test_smoke.gd` reported `order: 1705` and the run
## total read `order: 2,953,665`, sitting in a committed artifact as though it were a
## measurement.
##
## Nothing gated on them, so nothing went red — which is the reason to assert it here.
## **This checks the shape, not the two names:** a counter is a non-negative integer that
## an equal amount of work reproduces, and a row's identity fields are not counters. A
## future bookkeeping field leaks the same way and this is what catches it.
func test_the_profile_carries_only_counters_and_no_bookkeeping() -> void:
	var profile: Dictionary = _profile()
	if profile.is_empty():
		return
	var totals: Dictionary = profile.get("totals", {})
	assert_gt(totals.size(), 0, "the profile has totals to check")

	# The identity fields a row carries. `path` names the row; the rest were the leak.
	for identity: String in ["path", "script", "test", "order"]:
		assert_false(
			totals.has(identity),
			(
				"'%s' identifies a row, it does not measure one — it must not be summed into totals"
				% identity
			)
		)

	var files: Array = profile.get("files", [])
	assert_gt(files.size(), 0, "and files to check")
	for row: Dictionary in files:
		for key: String in row:
			if key == "path":
				continue
			assert_true(
				row[key] is float or row[key] is int,
				"%s carries a numeric %s, not an identifier" % [row.get("path", "?"), key]
			)
			assert_true(int(row[key]) >= 0, "%s's %s is a count" % [row.get("path", "?"), key])

	# Every summed key reaches the totals, and every total is a real counter — the two
	# halves of "the file rows and the totals describe the same measurement".
	for row: Dictionary in files:
		for key: String in row:
			if key == "path":
				continue
			assert_true(totals.has(key), "%s is measured per file, so it must reach totals" % key)
