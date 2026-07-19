extends GutTest

## taskblock-20 Pass D: "wounds — the failure model's missing middle." A
## non-terminal, per-part, repairable consequence — the state between "fine"
## and "failed" — distinct from `is_mangled`/`is_disabled` (whole-part,
## only ever at 0 hp). Covers the mechanism (`WoundEffects`, `WoundDef`,
## `Shell.operable_parts()`) end to end; taskblock-20 Pass C4's own
## `test_penetration_traverses_body.gd` already covers `lodged_bullet`'s
## own concrete automatic trigger — this file is the general machinery.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## A weapon requiring one TRIGGER manipulator, and a separate arm part that
## provides it — attached to a bare root so `PartGraph.can_operate` has a
## real socket tree to work from, no torso/reactor complexity needed.
func _armed_unit() -> Dictionary:
	var root := Part.new()
	root.id = &"test_root"
	root.hp = 10
	root.max_hp = 10
	var weapon_socket := Socket.new(&"GRIP")
	var arm_socket := Socket.new(&"SHOULDER")
	root.sockets = [weapon_socket, arm_socket]

	var weapon := Part.new()
	weapon.id = &"test_weapon"
	weapon.hp = 5
	weapon.max_hp = 5
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.requires = {&"TRIGGER": 1}
	weapon.attaches_to = [&"GRIP"]

	var arm := Part.new()
	arm.id = &"test_arm"
	arm.hp = 5
	arm.max_hp = 5
	arm.capabilities = [&"TRIGGER"]
	arm.attaches_to = [&"SHOULDER"]

	PartGraph.attach(weapon, root, weapon_socket)
	PartGraph.attach(arm, root, arm_socket)

	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0))
	var enemy := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(1, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit, enemy])
	unit.ap = 10
	return {
		"root": root, "weapon": weapon, "arm": arm, "unit": unit, "enemy": enemy, "state": state
	}


## The wound roster the taskblock names — must actually be authored and
## loadable, not just documented.
func test_the_three_named_wounds_are_authored_and_loadable() -> void:
	assert_not_null(DataLibrary.get_wound_def(&"severed_controls"))
	assert_not_null(DataLibrary.get_wound_def(&"burnt_electronics"))
	assert_not_null(DataLibrary.get_wound_def(&"lodged_bullet"))


## "burnt_electronics carries higher repair difficulty."
func test_burnt_electronics_carries_higher_repair_difficulty() -> void:
	var burnt: WoundDef = DataLibrary.get_wound_def(&"burnt_electronics")
	var lodged: WoundDef = DataLibrary.get_wound_def(&"lodged_bullet")
	assert_gt(burnt.repair_difficulty, lodged.repair_difficulty)


## taskblock-21 Pass A2: "each entry is a <5-char short blurb now."
func test_short_label_is_at_most_five_characters() -> void:
	var wound := WoundDef.new()
	wound.id = &"severed_controls"

	assert_eq(wound.short_label(), "SEVER")
	assert_lt(wound.short_label().length(), 6)


## "a wound disables/degrades without 0 HP" — a `severed_controls`-wounded
## manipulator can no longer operate a weapon that needs it, even though the
## arm's own hp is fully intact (never touched, never mangled/disabled).
func test_a_severed_controls_wound_disables_a_manipulator_without_0_hp() -> void:
	var built: Dictionary = _armed_unit()
	var attack := AttackAction.new(built.unit, &"test_weapon", built.enemy.cell)
	assert_true(attack.is_legal(built.state), "sanity: operable before the wound")

	WoundEffects.inflict(built.arm, &"severed_controls")

	assert_eq(built.arm.hp, built.arm.max_hp, "the arm's own hp is untouched")
	assert_false(attack.is_legal(built.state), "no operating manipulator left")


## The same wound on the WEAPON itself (not just a manipulator) blocks it
## too — a `disables` wound degrades whichever part carries it, not only
## limbs.
func test_a_severed_controls_wound_on_the_weapon_itself_disables_it() -> void:
	var built: Dictionary = _armed_unit()
	var attack := AttackAction.new(built.unit, &"test_weapon", built.enemy.cell)

	WoundEffects.inflict(built.weapon, &"severed_controls")

	assert_eq(built.weapon.hp, built.weapon.max_hp)
	assert_false(attack.is_legal(built.state))


## `burnt_electronics` is explicitly non-disabling — "works but hard to
## field-repair," not "works or doesn't."
func test_burnt_electronics_does_not_disable_anything() -> void:
	var built: Dictionary = _armed_unit()

	WoundEffects.inflict(built.arm, &"burnt_electronics")
	WoundEffects.inflict(built.weapon, &"burnt_electronics")

	var attack := AttackAction.new(built.unit, &"test_weapon", built.enemy.cell)
	assert_true(attack.is_legal(built.state))


## "a direct precise hit inflicts the right wound" — the generic mechanism
## any future precise-hit trigger (melee, a called shot) uses; idempotent,
## never doubling up the same wound.
func test_direct_infliction_adds_the_named_wound_exactly_once() -> void:
	var part := Part.new()
	part.id = &"test_part"

	WoundEffects.inflict(part, &"severed_controls")
	WoundEffects.inflict(part, &"severed_controls")

	assert_eq(part.wounds, [&"severed_controls"])


## "removing a wounded part clears it" — already true by construction once
## the part leaves the socket tree: nothing downstream (`all_parts()`,
## `operable_parts()`, `AttackAction.is_legal`) can see a wound on a part
## that's no longer attached.
func test_removing_a_wounded_part_clears_its_effect_on_the_unit() -> void:
	var built: Dictionary = _armed_unit()
	WoundEffects.inflict(built.arm, &"severed_controls")
	var attack := AttackAction.new(built.unit, &"test_weapon", built.enemy.cell)
	assert_false(attack.is_legal(built.state), "sanity: disabled while the wounded arm is attached")

	var arm_socket: Socket = built.root.sockets[1]
	var removed: Part = PartGraph.detach(arm_socket)

	assert_eq(removed, built.arm)
	assert_false(built.unit.shell.all_parts().has(built.arm), "gone from the assembly entirely")
	assert_true(&"severed_controls" in removed.wounds, "the wound travels WITH the removed part")


## "effect carries provenance" — a wound-disabled part's own stat_mods
## contribution disappears from the resolver's own source list, the same
## place a tooltip would read WHY a number is what it is (docs/08: the
## tooltip and the damage come from the same call).
func test_a_wound_disabled_parts_stat_contribution_drops_out_of_the_resolver_sources() -> void:
	var part := Part.new()
	part.id = &"test_agility_part"
	part.hp = 5
	part.max_hp = 5
	part.stat_mods = {&"agility": 2.0}

	var context := ResolverContext.new()
	context.parts = [part]
	var before: StatValue = StatResolver.resolve(&"agility", context)
	assert_eq(
		before.sources.size(), 1, "the part contributes a real, visible source before the wound"
	)

	WoundEffects.inflict(part, &"severed_controls")
	var shell := Shell.new(part)
	var after_context := ResolverContext.new()
	after_context.parts = shell.operable_parts()
	var after: StatValue = StatResolver.resolve(&"agility", after_context)

	assert_eq(after.sources.size(), 0, "the wounded part's own source is gone, not just zeroed")
	assert_eq(
		after.current, after.base, "no residual contribution once the source itself is absent"
	)


## "the threshold path exists (fires when statuses exist)" — no status
## system exists to call this from yet, so this is a real, tested, but
## currently uncalled hook: a generic magnitude-vs-threshold crossing, never
## a hardcoded status vocabulary this pass has no business inventing.
func test_status_threshold_hook_inflicts_the_wound_once_the_threshold_is_crossed() -> void:
	var part := Part.new()
	part.id = &"test_part"

	WoundEffects.apply_if_status_crosses_threshold(part, 2.0, 5.0, &"burnt_electronics")
	assert_eq(part.wounds, [] as Array[StringName], "below threshold: no wound yet")

	WoundEffects.apply_if_status_crosses_threshold(part, 6.0, 5.0, &"burnt_electronics")
	assert_eq(part.wounds, [&"burnt_electronics"])


## The weapons panel's own "shows its reason" contract (already established
## for `is_disabled`/missing-manipulator cases) extends to a disabling wound
## without a new UI concept.
func test_weapon_rows_reports_a_wound_disabled_weapon_with_its_reason() -> void:
	var built: Dictionary = _armed_unit()
	WoundEffects.inflict(built.weapon, &"severed_controls")

	var rows: Array[WeaponRow] = WeaponRows.build(built.unit)
	var row: WeaponRow = null
	for candidate: WeaponRow in rows:
		if candidate.part == built.weapon:
			row = candidate
	assert_not_null(row)
	assert_false(row.active)
	assert_true(row.why.contains("severed_controls"))
