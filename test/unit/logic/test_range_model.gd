extends GutTest

## taskblock-19 Pass C: RangeModel — effective/max/min range consolidated
## onto WeaponDef. Pure-function tests; AttackAction/Overwatch/UnitAI
## integration is covered in their own test files.


func _weapon(
	effective: float, max_r: float, min_r: float = 0.0, failure: StringName = &"none"
) -> Part:
	var weapon := Part.new()
	weapon.id = &"gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.effective_range = effective
	weapon.weapon_def.max_range = max_r
	weapon.weapon_def.min_range = min_r
	weapon.weapon_def.min_range_failure = failure
	return weapon


func test_full_accuracy_at_or_under_effective_range() -> void:
	var weapon: Part = _weapon(10.0, 20.0)

	assert_almost_eq(RangeModel.accuracy_multiplier(weapon, 5), 1.0, 0.0001)
	assert_almost_eq(RangeModel.accuracy_multiplier(weapon, 10), 1.0, 0.0001)


func test_accuracy_degrades_linearly_between_effective_and_max() -> void:
	var weapon: Part = _weapon(10.0, 20.0)

	var midpoint: float = RangeModel.accuracy_multiplier(weapon, 15)

	assert_almost_eq(
		midpoint, (1.0 + RangeModel.ACCURACY_FLOOR) / 2.0, 0.0001, "halfway through the band"
	)
	assert_lt(RangeModel.accuracy_multiplier(weapon, 17), midpoint, "worse further into the band")


func test_accuracy_floor_at_max_range() -> void:
	var weapon: Part = _weapon(10.0, 20.0)

	assert_almost_eq(RangeModel.accuracy_multiplier(weapon, 20), RangeModel.ACCURACY_FLOOR, 0.0001)


func test_is_in_max_range_blocks_beyond_max_but_not_at_or_under_it() -> void:
	var weapon: Part = _weapon(10.0, 20.0)

	assert_true(RangeModel.is_in_max_range(weapon, 20))
	assert_false(RangeModel.is_in_max_range(weapon, 21))


func test_an_unauthored_weapon_def_is_uncapped_and_full_accuracy() -> void:
	var weapon := Part.new()
	weapon.id = &"legacy_gun"
	weapon.weapon_def = WeaponDef.new()  # every field at its 0.0/&"none" default

	assert_true(RangeModel.is_in_max_range(weapon, 9999))
	assert_almost_eq(RangeModel.accuracy_multiplier(weapon, 9999), 1.0, 0.0001)
	assert_false(RangeModel.blocks_min_range(weapon, 0))


func test_a_weapon_with_no_weapon_def_at_all_is_uncapped_and_full_accuracy() -> void:
	var weapon := Part.new()
	weapon.id = &"bare_part"

	assert_true(RangeModel.is_in_max_range(weapon, 9999))
	assert_almost_eq(RangeModel.accuracy_multiplier(weapon, 9999), 1.0, 0.0001)
	assert_false(RangeModel.blocks_min_range(weapon, 0))
	assert_false(RangeModel.is_dud(weapon, 0))


## taskblock-19 Pass C2: "a unit under min range with a non-explosive
## weapon can't fire" — the default `min_range_failure` (&"none") blocks.
func test_min_range_blocks_a_non_dud_weapon() -> void:
	var weapon: Part = _weapon(10.0, 20.0, 3.0, &"none")

	assert_true(RangeModel.blocks_min_range(weapon, 2))
	assert_false(RangeModel.blocks_min_range(weapon, 3), "at min range exactly is legal")
	assert_false(RangeModel.is_dud(weapon, 2), "a non-dud weapon never duds — it's just blocked")


## taskblock-19 Pass C2: "an explosive shell fired under min range duds
## instead of detonating" — a dud-capable weapon is never blocked, but is
## flagged as a dud under min range.
func test_min_range_dud_weapon_is_never_blocked_but_flagged_as_dud() -> void:
	var weapon: Part = _weapon(10.0, 20.0, 3.0, &"dud")

	assert_false(RangeModel.blocks_min_range(weapon, 2), "dud-capable weapons are never blocked")
	assert_true(RangeModel.is_dud(weapon, 2))
	assert_false(RangeModel.is_dud(weapon, 3), "at or above min range, it's an ordinary hit")
