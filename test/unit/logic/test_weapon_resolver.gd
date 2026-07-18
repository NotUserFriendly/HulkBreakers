extends GutTest

## docs/08: the same call a tooltip renders from must be the call an attack
## actually fires with.


func _weapon(damage: float, crit_chance: float = 0.0) -> Part:
	var weapon := Part.new()
	weapon.id = &"pistol"
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.damage = damage
	weapon.crit_chance = crit_chance
	return weapon


func test_resolve_damage_with_no_modifiers_matches_the_base() -> void:
	var weapon := _weapon(5.0)
	assert_eq(WeaponResolver.resolve_damage(weapon).current, 5.0)


func test_resolve_damage_applies_a_part_stat_mod() -> void:
	var weapon := _weapon(5.0)
	weapon.stat_mods = {&"damage": 2.0}
	var resolved := WeaponResolver.resolve_damage(weapon)
	assert_eq(resolved.current, 7.0)
	assert_eq(resolved.sources.size(), 1)


func test_resolve_damage_applies_an_extra_source_eg_a_perk() -> void:
	var weapon := _weapon(5.0)
	var perk := ModSource.new("Overcharge", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, 3.0)
	var resolved := WeaponResolver.resolve_damage(weapon, [perk])
	assert_eq(resolved.current, 8.0)
	assert_eq(resolved.sources[0].source_name, "Overcharge")


func test_resolve_crit_chance_matches_the_base_with_no_modifiers() -> void:
	var weapon := _weapon(5.0, 0.25)
	assert_almost_eq(WeaponResolver.resolve_crit_chance(weapon).current, 0.25, 0.0001)


## taskblock-13 Pass A: "damage_multiplier feeds the shot through
## StatResolver (a sniper's 1.1 hits harder than a chaingun's 0.8 with the
## same ammo)" — same base damage, different WeaponDef.damage_multiplier,
## different resolved output.
func test_damage_multiplier_scales_the_resolved_damage() -> void:
	var chaingun := _weapon(5.0)
	chaingun.weapon_def = WeaponDef.new()
	chaingun.weapon_def.damage_multiplier = 0.8
	var sniper := _weapon(5.0)
	sniper.weapon_def = WeaponDef.new()
	sniper.weapon_def.damage_multiplier = 1.1

	var chaingun_damage: float = WeaponResolver.resolve_damage(chaingun).current
	var sniper_damage: float = WeaponResolver.resolve_damage(sniper).current

	assert_almost_eq(chaingun_damage, 4.0, 0.0001)
	assert_almost_eq(sniper_damage, 5.5, 0.0001)
	assert_gt(
		sniper_damage, chaingun_damage, "the same base round must hit harder from the 1.1x barrel"
	)


## A part with no WeaponDef at all (every weapon authored before this
## field existed, and every non-weapon part) resolves exactly as before —
## no phantom x1.0 multiplier source appears.
func test_no_weapon_def_means_no_multiplier_source_at_all() -> void:
	var weapon := _weapon(5.0)
	var resolved := WeaponResolver.resolve_damage(weapon)
	assert_eq(resolved.current, 5.0)
	assert_eq(resolved.sources.size(), 0)


## taskblock-13 Pass D: recoil_step is resolved through the same
## StatResolver pipeline as damage/crit_chance/bonus_pen — a stat_mods
## entry on the weapon must be able to adjust it with real provenance,
## same as everything else here.
func test_resolve_recoil_step_matches_the_pure_formula_with_no_modifiers() -> void:
	var weapon := _weapon(5.0)
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.barrel_length = 2.0

	var resolved := WeaponResolver.resolve_recoil_step(weapon, 4.0)

	assert_almost_eq(resolved.current, RecoilResolver.step_amount(weapon, 4.0), 0.0001)


func test_resolve_recoil_step_applies_a_part_stat_mod() -> void:
	var weapon := _weapon(5.0)
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.barrel_length = 1.0
	weapon.stat_mods = {&"recoil_step": -0.01}

	var base: float = RecoilResolver.step_amount(weapon, 4.0)
	var resolved := WeaponResolver.resolve_recoil_step(weapon, 4.0)

	assert_almost_eq(resolved.current, base - 0.01, 0.0001)
