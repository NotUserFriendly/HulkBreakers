extends GutTest

## taskblock-64 Pass D — **the seam between what a bout arms and what a planner can offer.**
##
## No test crossed it. taskblock-63's full gate fired **481 rounds** on the exact tree where an
## all-chaingun roster could not fire a single one, because headless bouts pick presets that
## provide `shoot` and every AI fixture in the suite hand-authors its weapon with
## `provides_actions = [&"shoot"]`. **The library was never asked whether it can arm a unit it can
## also plan for.**
##
## `BR63.04` was one authored combination proving the class exists: `chaingun.tres` is the only
## weapon in the library providing no `shoot`, and `combat_tester_chaingun.tres` was the only
## `GRUNT` preset. `BR63.05`'s `MINDLESS` half was the same defect wearing different clothes — a
## pump shotgun issued to the one tier that has no firing action at all.
##
## ## Enumerated, never listed
##
## Both pools come from `DataLibrary`. **A hand-written list goes stale the day a preset is added**
## (CLAUDE.md), and that is precisely how this gap survived: every existing test names its own
## weapon, so adding `combat_tester_chaingun` to the library changed no test's mind about anything.
##
## ## Static, and deliberately not a planning run
##
## `test_close_range_firing_decision.gd` runs the real planner and is the stronger evidence, but it
## costs a bout per case and is scoped to the combat presets. This asks the cheap question of the
## **whole** library: is there any tier/weapon/action combination that cannot possibly work? It is
## the cross-product; that one is the proof it resolves.


## Executors that build a firing action from a weapon. Read off `ActionCatalog`'s own vocabularies
## rather than restated, so a new melee verb is covered the day it is authored.
func _weapon_executors() -> Array[StringName]:
	var ids: Array[StringName] = [&"burst"]
	ids.append_array(ActionCatalog.ATTACK_ACTION_IDS)
	ids.append_array(ActionCatalog.MELEE_ACTION_IDS)
	ids.append_array(ActionCatalog.SLASH_ACTION_IDS)
	ids.append_array(ActionCatalog.GRIND_ACTION_IDS)
	return ids


## Every damaging part a preset's assembled unit actually carries.
func _weapons_of(unit: Unit) -> Array[Part]:
	var weapons: Array[Part] = []
	for part: Part in unit.shell.operable_parts():
		if part.damage > 0.0:
			weapons.append(part)
	return weapons


## The utility actions `tier` may select that this `weapon` can actually execute.
##
## Two gates, and they are the two that `BR63.04` fell between: the action's own `tiers` list
## (empty means every tier), and whether the weapon `provides_actions` the executor named. An
## action whose executor is not weapon-shaped at all — `move`, `gather` — is not a firing option
## and is excluded, or every weapon would look reachable through `roam`.
func _reachable_for(weapon: Part, tier: StringName) -> Array[String]:
	var executors: Array[StringName] = _weapon_executors()
	var reachable: Array[String] = []
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if not action.tiers.is_empty() and tier not in action.tiers:
			continue
		if action.executor_id not in executors:
			continue
		if action.executor_id not in weapon.provides_actions:
			continue
		reachable.append(str(action.id))
	reachable.sort()
	return reachable


## **`KitEquipper.equip` is deliberately NOT called**, and that is a stated coverage limit rather
## than an oversight.
##
## `BoutSetup` does call it, so this is one step short of what a real bout builds. But the only
## kitted preset in the library is `kitted_chaingun`, and equipping it emits `KitEquipper:
## chaingun never made it into its own kit container backpack` (`BR64.02`) — an engine
## `push_error`, which GUT scores as a failure. Importing a filed crash into an unrelated
## assertion would make this test red for a reason it is not about.
##
## **What that costs:** a kitted preset's weapons are not covered by this cross-product. It costs
## nothing today — `kitted_chaingun` assembles with no weapon whether the kit is equipped or not,
## so it contributes no rows either way — and **the line to delete is this one**, the moment
## `BR64.02` closes.
func _unit_from(preset: BotPreset) -> Unit:
	var matrix := Matrix.new()
	matrix.id = StringName("%s_probe" % preset.preset_name)
	return DeepStrike.assemble_from_preset(preset, matrix, Vector2i(2, 2), 0)


## **The cross-product.** Every preset, every weapon it carries, against its own tier.
func test_every_weapon_a_preset_carries_has_an_action_its_own_tier_can_reach() -> void:
	var presets: Array[BotPreset] = DataLibrary.presets_pool()
	presets.sort_custom(
		func(a: BotPreset, b: BotPreset) -> bool: return a.preset_name < b.preset_name
	)
	assert_gt(presets.size(), 0, "the library loaded")

	var unreachable: Array[String] = []
	var unarmed: Array[String] = []
	for preset: BotPreset in presets:
		var unit: Unit = _unit_from(preset)
		if unit == null:
			unarmed.append("%s (did not assemble)" % preset.preset_name)
			continue
		var tier: StringName = unit.intelligence_tier
		var weapons: Array[Part] = _weapons_of(unit)
		if weapons.is_empty():
			unarmed.append(preset.preset_name)
			gut.p("  %-32s %-9s carries no weapon" % [preset.preset_name, tier])
			continue
		for weapon: Part in weapons:
			var reachable: Array[String] = _reachable_for(weapon, tier)
			gut.p(
				(
					"  %-32s %-9s %-14s -> %s"
					% [
						preset.preset_name,
						tier,
						weapon.id,
						"NOTHING" if reachable.is_empty() else ", ".join(reachable)
					]
				)
			)
			if reachable.is_empty():
				unreachable.append("%s/%s @%s" % [preset.preset_name, weapon.id, tier])

	# **Reported, not asserted.** A preset that carries no weapon is a different defect —
	# `BR64.02` for `kitted_chaingun`, whose kit names a chaingun that `KitEquipper` then drops —
	# and the supervisor's call is that the kitted and laborer presets are test fixtures rather
	# than designed fighting units. Failing on them here would measure the fixtures.
	if not unarmed.is_empty():
		gut.p("  carrying no weapon (see BR64.02): %s" % ", ".join(unarmed))

	assert_eq(
		unreachable,
		[] as Array[String],
		(
			"a library that can arm a unit it cannot also plan for is the defect class BR63.04 "
			+ "proved with one authored combination: %s" % ", ".join(unreachable)
		)
	)


## **The negative control.** A cross-product that cannot fail proves nothing, and this one passes
## on the whole library — so the checker is pointed at a weapon deliberately built to be
## unreachable and must say so.
##
## The fixture authors its own broken part rather than the library carrying one (CLAUDE.md: *if a
## test needs a concrete list, the test authors it*).
func test_a_weapon_no_tier_can_reach_is_caught() -> void:
	var orphan := Part.new()
	orphan.id = &"test_orphan_gun"
	orphan.damage = 5.0
	orphan.provides_actions = [&"trebuchet"]

	for tier: StringName in [&"MINDLESS", &"GRUNT", &"TRAINED", &"ELITE"]:
		var reachable: Array[String] = _reachable_for(orphan, tier)
		gut.p(
			(
				"  orphan weapon at %-9s -> %s"
				% [tier, "NOTHING" if reachable.is_empty() else ", ".join(reachable)]
			)
		)
		assert_eq(
			reachable,
			[] as Array[String],
			"a weapon providing an action no utility action names is unreachable at every tier"
		)

	# And the converse, so "unreachable" is not simply what this helper always answers.
	var real := Part.new()
	real.id = &"test_real_gun"
	real.damage = 5.0
	real.provides_actions = [&"shoot"]
	assert_gt(
		_reachable_for(real, &"GRUNT").size(),
		0,
		"a GRUNT with a shoot-capable weapon must have something to select"
	)
	assert_eq(
		_reachable_for(real, &"MINDLESS"),
		[] as Array[String],
		(
			"and MINDLESS must not — docs/11 gates shoot to Grunt-and-above deliberately, so this "
			+ "is the design working and the reason an armed MINDLESS preset is a library defect"
		)
	)
