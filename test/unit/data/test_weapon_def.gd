extends GutTest

## taskblock-13 Pass A: WeaponDef — a plain sub-resource embedded on a
## weapon Part, null everywhere else. These tests exercise the four
## reference guns' own authored .tres values, not a fixture rebuild of
## them (see test_data_migration_losslessness.gd's own header on why a
## hand-typed second copy of authored data is the wrong shape to check
## against) — the numbers here are read straight from the taskblock's own
## table.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func test_a_non_weapon_part_has_no_weapon_def() -> void:
	var torso: Part = DataLibrary.get_part(&"torso")
	assert_null(torso.weapon_def)


func test_chaingun_loads_with_its_table_values() -> void:
	var chaingun: Part = DataLibrary.get_part(&"chaingun")
	assert_not_null(chaingun)
	assert_not_null(chaingun.weapon_def)
	assert_almost_eq(chaingun.weapon_def.damage_multiplier, 0.8, 0.0001)
	assert_almost_eq(chaingun.weapon_def.mechanical_accuracy, 0.8, 0.0001)
	assert_eq(chaingun.weapon_def.burst_size, 12)
	assert_eq(chaingun.provides_actions, [&"burst"] as Array[StringName])


func test_pump_shotgun_loads_with_its_table_values() -> void:
	var pump: Part = DataLibrary.get_part(&"pump_shotgun")
	assert_not_null(pump)
	assert_not_null(pump.weapon_def)
	assert_almost_eq(pump.weapon_def.damage_multiplier, 1.0, 0.0001)
	assert_almost_eq(pump.weapon_def.mechanical_accuracy, 0.85, 0.0001)
	assert_eq(pump.provides_actions, [&"shoot"] as Array[StringName])


func test_auto_shotgun_loads_with_its_table_values() -> void:
	var auto: Part = DataLibrary.get_part(&"auto_shotgun")
	assert_not_null(auto)
	assert_not_null(auto.weapon_def)
	assert_almost_eq(auto.weapon_def.damage_multiplier, 0.9, 0.0001)
	assert_almost_eq(auto.weapon_def.mechanical_accuracy, 0.9, 0.0001)
	assert_eq(auto.weapon_def.burst_size, 3)
	assert_eq(auto.provides_actions, [&"shoot", &"burst"] as Array[StringName])


func test_sniper_rifle_loads_with_its_table_values() -> void:
	var sniper: Part = DataLibrary.get_part(&"sniper_rifle")
	assert_not_null(sniper)
	assert_not_null(sniper.weapon_def)
	assert_almost_eq(sniper.weapon_def.damage_multiplier, 1.1, 0.0001)
	assert_almost_eq(sniper.weapon_def.mechanical_accuracy, 0.95, 0.0001)
	assert_eq(sniper.provides_actions, [&"shoot"] as Array[StringName])


## Only Chaingun/Auto Shotgun carry a real burst_size (12/3) — Pump
## Shotgun/Sniper Rifle never provide BURST at all, so their burst_size
## stays WeaponDef's own inert default of 1 rather than an authored "n/a."
func test_guns_with_no_burst_mode_keep_the_default_burst_size() -> void:
	var pump: Part = DataLibrary.get_part(&"pump_shotgun")
	var sniper: Part = DataLibrary.get_part(&"sniper_rifle")
	assert_eq(pump.weapon_def.burst_size, 1)
	assert_eq(sniper.weapon_def.burst_size, 1)
	assert_false(pump.provides_actions.has(&"burst"))
	assert_false(sniper.provides_actions.has(&"burst"))
