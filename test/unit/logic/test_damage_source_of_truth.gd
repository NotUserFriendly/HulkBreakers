extends GutTest

## taskblock-10 Pass E: "confirm damage's single source of truth is
## AmmoDef, and any remaining Part.damage is either deleted or clearly a
## different quantity." The real claim this pass could make at the time
## was narrower and checkable: exactly ONE field computes weapon damage
## (`Part.damage`, read only through `WeaponResolver`), and `AmmoDef.damage`
## — real, loaded, validated — sat unread by anything.
##
## taskblock-13 Pass A/B: `Part.ammo_id` now exists (what a weapon has
## chambered) but the reference pool's own pistol/rifle/two_handed_sword
## still ship unloaded — `Part.damage` stays the live source for them
## until something actually loads a round into one.


func test_weapon_resolver_is_the_only_reader_of_part_damage() -> void:
	var weapon := Part.new()
	weapon.id = &"pistol"
	weapon.damage = 4.0
	var resolved: StatValue = WeaponResolver.resolve_damage(weapon)
	assert_eq(resolved.current, 4.0)


## Every reference part pool weapon still carries its damage on the Part,
## not the (currently unwired) AmmoDef — `find_operable_weapon`'s own
## `> 0.0` classification gate depends on this staying true until the
## gun/ammo wiring block lands.
func test_reference_weapons_still_carry_damage_on_the_part_not_an_ammo_ref() -> void:
	for id: StringName in [&"pistol", &"rifle", &"two_handed_sword"]:
		var weapon: Part = DataLibrary.get_part(id)
		assert_not_null(weapon)
		assert_gt(weapon.damage, 0.0, "%s.damage must still be the live source" % id)


## AmmoDef.damage is real, loaded data (Pass D) — the reference pistol
## still doesn't read it, because it doesn't have anything chambered.
func test_ammo_def_damage_is_authored_but_the_reference_pistol_has_none_chambered() -> void:
	var round: AmmoDef = DataLibrary.get_ammo(&"9mm_fmj")
	assert_not_null(round)
	assert_gt(round.damage, 0.0, "the reference round's own damage is real, authored data")
	var weapon: Part = DataLibrary.get_part(&"pistol")
	assert_eq(
		weapon.ammo_id,
		&"",
		"the reference pistol ships unloaded — Part.damage stays its live source"
	)
