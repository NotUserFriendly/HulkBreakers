extends GutTest

## taskblock-13 Pass D: recoil = base_recoil(ammo.damage) /
## barrel_factor(barrel_length), applied cumulatively within a burst.


func _weapon(barrel_length: float) -> Part:
	var weapon := Part.new()
	weapon.id = &"test_gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.barrel_length = barrel_length
	return weapon


## "a higher-damage round produces more recoil than a light one from the
## same gun."
func test_higher_damage_produces_more_recoil() -> void:
	var weapon := _weapon(1.0)
	var light: float = RecoilResolver.step_amount(weapon, 2.0)
	var heavy: float = RecoilResolver.step_amount(weapon, 10.0)

	assert_gt(heavy, light)


## "a longer barrel reduces recoil for the same round."
func test_longer_barrel_reduces_recoil() -> void:
	var short_barrel := _weapon(0.5)
	var long_barrel := _weapon(2.0)

	var short_recoil: float = RecoilResolver.step_amount(short_barrel, 5.0)
	var long_recoil: float = RecoilResolver.step_amount(long_barrel, 5.0)

	assert_lt(long_recoil, short_recoil)


## Pass H's own "zero barrel length" extreme — must read as worse
## recoil, never a crash/NaN/infinity.
func test_zero_barrel_length_does_not_crash_or_produce_nan_or_infinity() -> void:
	var weapon := _weapon(0.0)
	var recoil: float = RecoilResolver.step_amount(weapon, 5.0)

	assert_false(is_nan(recoil))
	assert_false(is_inf(recoil))
	assert_gt(recoil, 0.0)


func test_widen_at_step_zero_returns_an_unchanged_copy() -> void:
	var scatter: Array[Ring] = [Ring.new(0.1, 1.0)]

	var widened: Array[Ring] = RecoilResolver.widen(scatter, 0.5, 0)

	assert_almost_eq(widened[0].radius, 0.1, 0.0001)


## `widen` must never mutate its input — a later, non-zero-step call
## reusing the same resolved `scatter` (as BurstAction's own loop does,
## once per pull) must always widen from the ORIGINAL radius, not
## whatever a previous pull's widening already wrote into it.
func test_widen_never_mutates_the_input_scatter() -> void:
	var scatter: Array[Ring] = [Ring.new(0.1, 1.0)]

	RecoilResolver.widen(scatter, 0.5, 3)

	assert_almost_eq(scatter[0].radius, 0.1, 0.0001, "the original ring must be untouched")


## "within a burst, shot N's dartboard is wider than shot N-1's."
func test_each_successive_step_widens_further_than_the_last() -> void:
	var scatter: Array[Ring] = [Ring.new(0.1, 1.0)]

	var step0: Array[Ring] = RecoilResolver.widen(scatter, 0.2, 0)
	var step1: Array[Ring] = RecoilResolver.widen(scatter, 0.2, 1)
	var step2: Array[Ring] = RecoilResolver.widen(scatter, 0.2, 2)

	assert_lt(step0[0].radius, step1[0].radius)
	assert_lt(step1[0].radius, step2[0].radius)


func test_widen_never_touches_ring_weight() -> void:
	var scatter: Array[Ring] = [Ring.new(0.1, 3.0)]

	var widened: Array[Ring] = RecoilResolver.widen(scatter, 0.5, 4)

	assert_almost_eq(widened[0].weight, 3.0, 0.0001)
