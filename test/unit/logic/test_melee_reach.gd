extends GutTest

## taskblock-25 Pass A: reach = shell + weapon (docs/PLAN.md "Phase M —
## Melee"). Pure distance math — no Unit, no CombatState, no geometry.


func _shell(shell_reach: float) -> Shell:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shell := Shell.new(torso)
	shell.shell_reach = shell_reach
	return shell


func _weapon(length: float) -> Part:
	var weapon := Part.new()
	weapon.id = &"knife"
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.weapon_length = length
	return weapon


func test_weapon_length_is_zero_for_an_unarmed_strike() -> void:
	assert_eq(MeleeReach.weapon_length(null), 0.0)


func test_weapon_length_is_zero_for_a_weapon_with_no_weapon_def() -> void:
	var bare := Part.new()
	bare.id = &"fist"
	assert_eq(MeleeReach.weapon_length(bare), 0.0)


func test_total_reach_is_shell_reach_plus_weapon_length() -> void:
	var shell := _shell(0.7)
	var weapon := _weapon(0.3)
	assert_almost_eq(MeleeReach.total_reach(shell, weapon), 1.0, 0.0001)


func test_lean_needed_is_zero_when_weapon_alone_covers_the_distance() -> void:
	var weapon := _weapon(1.3)  # the spear, from the worked example
	assert_eq(MeleeReach.lean_needed(weapon, 1.0), 0.0)


func test_lean_needed_is_the_shortfall_after_weapon_length() -> void:
	var weapon := _weapon(0.3)  # the knife, from the worked example
	assert_almost_eq(MeleeReach.lean_needed(weapon, 1.0), 0.7, 0.0001)


## docs/PLAN.md Pass A's own worked example: Joe (shell_reach 0.7) stabs
## Todd at distance 1 — a knife (0.3) needs the full 0.7 lean; a spear
## (1.3) needs none at all, at the exact same distance.
func test_the_knife_and_spear_worked_example() -> void:
	var knife := _weapon(0.3)
	var spear := _weapon(1.3)

	assert_almost_eq(MeleeReach.lean_needed(knife, 1.0), 0.7, 0.0001)
	assert_eq(MeleeReach.lean_needed(spear, 1.0), 0.0)


func test_in_reach_is_true_within_total_reach() -> void:
	var shell := _shell(0.7)
	var weapon := _weapon(0.3)
	assert_true(MeleeReach.in_reach(shell, weapon, 1.0))


func test_in_reach_is_false_beyond_total_reach() -> void:
	var shell := _shell(0.7)
	var weapon := _weapon(0.3)
	assert_false(MeleeReach.in_reach(shell, weapon, 1.01))


func test_a_weapon_with_no_authored_length_leans_on_shell_reach_alone() -> void:
	var shell := _shell(1.0)
	var fist := Part.new()
	fist.id = &"fist"
	assert_almost_eq(MeleeReach.total_reach(shell, fist), 1.0, 0.0001)
	assert_almost_eq(MeleeReach.lean_needed(fist, 1.0), 1.0, 0.0001)
