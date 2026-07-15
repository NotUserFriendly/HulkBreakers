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
