extends GutTest

## taskblock-59 Pass E — **the intelligence tiers reach a bout.**
##
## `Unit.intelligence_tier` has existed since the AI's world model was built and **nothing ever set
## it** — no preset, no matrix, no roster entry — so every unit in every bout this project has run
## has been `TRAINED`, and every completion figure ever recorded is an all-`TRAINED` figure.
##
## **The tiers are not stubs.** The differences were already authored and they are large; what was
## missing is the authoring. These tests are the two halves: the capability gates really gate, and a
## preset really carries a tier into an assembled unit.

## The four tiers, **authored here as a fixture rather than read from a constant**, because
## CLAUDE.md's standing rule is that `intelligence_tier` is an open vocabulary and a test that needs
## a concrete list writes one.
const TIERS: Array[StringName] = [&"MINDLESS", &"GRUNT", &"TRAINED", &"ELITE"]


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _unit_at(tier: StringName) -> Unit:
	var unit := Unit.new(Matrix.new(), Shell.new(), Vector2i.ZERO, 0)
	unit.intelligence_tier = tier
	return unit


## A `WorldView` over an otherwise empty board — the capability gates read only the observer's own
## tier, so the board it is a view of does not matter to what is being asked here.
##
## **Restricted, because that is what production does.** `AiPlanner` sets `restricted = true` once
## for every planning call ("the view is restricted here, once, for everyone"), and an unrestricted
## view answers `true` to every capability regardless of tier — so a test that used `full()` alone
## would be asserting against a view no planner ever sees.
func _view() -> WorldView:
	var view: WorldView = WorldView.full(CombatState.new(Grid.new(4, 4), [] as Array[Unit], 1))
	view.restricted = true
	return view


# ---------------------------------------------------------------- the preset carries it


## The one line that lets a tier reach a bout: `DeepStrike.assemble_from_preset` is the only path
## with a preset to read one from.
func test_a_preset_authors_the_tier_its_units_are_assembled_with() -> void:
	for tier: StringName in TIERS:
		var preset: BotPreset = DataLibrary.get_preset(&"combat_tester_chaingun").duplicate(true)
		preset.intelligence_tier = tier
		var unit: Unit = DeepStrike.assemble_from_preset(preset, Matrix.new(), Vector2i(1, 1), 0)
		assert_not_null(unit, "the preset did not assemble at all")
		assert_eq(unit.intelligence_tier, tier, "the preset's tier did not reach the unit")


## The authored content really carries a spread, rather than the field existing and every row
## saying `TRAINED`.
func test_the_authored_presets_carry_more_than_one_tier() -> void:
	var seen: Dictionary = {}
	for preset: BotPreset in DataLibrary.presets_pool():
		seen[preset.intelligence_tier] = true
	gut.p("authored tiers: %s" % str(seen.keys()))
	assert_gt(seen.size(), 1, "every preset is the same tier, so nothing was authored")


## **The acceptance**: a generated bout contains more than one tier.
func test_a_generated_bout_contains_more_than_one_tier() -> void:
	var built: Dictionary = CompletionSampler.build_for_seed(4242)
	assert_eq(built.get("error", ""), "", "the bout did not build")

	var seen: Dictionary = {}
	for unit: Unit in (built["state"] as CombatState).units:
		seen[unit.intelligence_tier] = true
	gut.p("tiers in the bout: %s" % str(seen.keys()))
	assert_gt(seen.size(), 1, "a generated bout is still one row of the table")


## And the per-tier probe really holds every unit at one tier, which is what makes Pass F's
## breakdown a measurement of intelligence rather than of weapons.
func test_the_per_tier_probe_builds_a_bout_entirely_at_that_tier() -> void:
	for tier: StringName in TIERS:
		var built: Dictionary = CompletionSampler.build_at_tier(tier, 4242)
		assert_eq(built.get("error", ""), "", "the %s bout did not build" % tier)
		for unit: Unit in (built["state"] as CombatState).units:
			assert_eq(unit.intelligence_tier, tier, "a unit in the %s bout was not one" % tier)


## **The registry's own preset must not be written to.** Overriding a tier on the shared resource
## would leave every later bout in the process fighting at whichever tier was measured last.
func test_the_per_tier_probe_does_not_edit_the_registry() -> void:
	var before: StringName = DataLibrary.get_preset(&"combat_tester_chaingun").intelligence_tier

	CompletionSampler.build_at_tier(&"MINDLESS", 4242)

	assert_eq(
		DataLibrary.get_preset(&"combat_tester_chaingun").intelligence_tier,
		before,
		"the probe overwrote the authored preset"
	)


# ---------------------------------------------------------------- the gates really gate


## *"A `MINDLESS` unit is not a `TRAINED` unit with fewer options — it approaches and never
## fires."* The action pool is where that is decided.
func test_a_mindless_unit_is_offered_no_shoot_cover_or_overwatch() -> void:
	var gated: Array[StringName] = []
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if action.tiers.is_empty():
			continue
		if not &"MINDLESS" in action.tiers:
			gated.append(action.id)
	gut.p("actions a MINDLESS unit is not offered: %s" % str(gated))
	for verb: StringName in [&"shoot", &"take_cover", &"overwatch"]:
		assert_has(gated, verb, "%s is reachable by a MINDLESS unit" % verb)


## **A `GRUNT` shoots and takes cover. It does NOT overwatch — and that is a finding.**
##
## taskblock-59's own table describes `GRUNT` as *"memory and the shoot/cover/overwatch set"*, but
## the authored data has read `overwatch.tiers = [TRAINED, ELITE]` since taskblock-45. **The
## description and the content disagree**, and the content is what runs.
##
## Left as authored rather than edited to match the sentence: which tier gains overwatch is a
## balance decision about how capable a second-rung enemy is, and moving it because a summary table
## in a spec said so would be exactly the invented balance number the standing rule forbids. Pinned
## here so the disagreement is recorded rather than rediscovered.
func test_a_grunt_shoots_and_takes_cover_but_does_not_overwatch() -> void:
	var offered: Dictionary = {}
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if action.id in [&"shoot", &"take_cover", &"overwatch"]:
			offered[action.id] = action.tiers.is_empty() or &"GRUNT" in action.tiers
	gut.p("GRUNT is offered: %s" % str(offered))
	assert_true(offered[&"shoot"], "a GRUNT that cannot shoot is a MINDLESS unit")
	assert_true(offered[&"take_cover"], "a GRUNT that cannot take cover is a MINDLESS unit")
	assert_false(
		offered[&"overwatch"], "overwatch is authored TRAINED+; the taskblock's table says GRUNT"
	)


## Memory starts at `GRUNT`: a `MINDLESS` unit stops knowing an enemy exists the moment line of
## sight breaks.
func test_memory_starts_at_grunt() -> void:
	assert_does_not_have(WorldView.MEMORY_TIERS, &"MINDLESS")
	for tier: StringName in [&"GRUNT", &"TRAINED", &"ELITE"]:
		assert_has(WorldView.MEMORY_TIERS, tier, "%s should remember a sighting" % tier)


## **A `GRUNT` remembers and does not read the blackboard**, which is the one distinction between
## it and `TRAINED` that is not about the action pool.
func test_a_grunt_remembers_a_sighting_and_does_not_read_the_blackboard() -> void:
	var grunt: Unit = _unit_at(&"GRUNT")

	var view: WorldView = _view()

	assert_has(WorldView.MEMORY_TIERS, grunt.intelligence_tier, "a GRUNT must remember a sighting")
	assert_false(
		view.has_blackboard(grunt),
		"a GRUNT read the blackboard, which is what makes TRAINED a different tier"
	)
	assert_true(
		view.has_blackboard(_unit_at(&"TRAINED")), "a TRAINED unit cannot read the blackboard"
	)


## *"Only `ELITE` runs lookahead."*
func test_only_elite_runs_lookahead() -> void:
	for tier: StringName in TIERS:
		var expected: bool = tier == &"ELITE"
		assert_eq(
			UtilityLookahead.searches(_unit_at(tier)),
			expected,
			"lookahead for %s should be %s" % [tier, expected]
		)
