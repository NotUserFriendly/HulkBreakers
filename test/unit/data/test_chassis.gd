extends GutTest

var _torso_part: Part
var _head_part: Part
var _chassis: Chassis


func before_each() -> void:
	_torso_part = Part.new()
	_torso_part.id = &"torso_plate"
	_torso_part.slot_type = Enums.SlotType.TORSO
	_torso_part.part_type = Enums.PartType.ARMOR
	_torso_part.hp = 10
	_torso_part.max_hp = 10
	_torso_part.stat_mods = {"armor": 5, "mass_cap": 2}

	_head_part = Part.new()
	_head_part.id = &"sensor_head"
	_head_part.slot_type = Enums.SlotType.HEAD
	_head_part.part_type = Enums.PartType.SENSOR
	_head_part.hp = 4
	_head_part.max_hp = 4
	_head_part.stat_mods = {"sight": 3}

	_chassis = Chassis.new()
	_chassis.max_mass = 100.0


func test_install_fills_slot() -> void:
	_chassis.install(_torso_part)
	assert_eq(_chassis.slots[Enums.SlotType.TORSO], _torso_part)


func test_aggregate_stats_sums_installed_parts() -> void:
	_chassis.install(_torso_part)
	_chassis.install(_head_part)
	var stats: Dictionary = _chassis.aggregate_stats()
	assert_eq(stats["armor"], 5)
	assert_eq(stats["mass_cap"], 2)
	assert_eq(stats["sight"], 3)


func test_remove_removes_stat_contribution() -> void:
	_chassis.install(_torso_part)
	_chassis.install(_head_part)
	var removed: Part = _chassis.remove(Enums.SlotType.TORSO)
	assert_eq(removed, _torso_part)
	assert_false(_chassis.slots.has(Enums.SlotType.TORSO))
	var stats: Dictionary = _chassis.aggregate_stats()
	assert_false(stats.has("armor"))
	assert_false(stats.has("mass_cap"))
	assert_eq(stats["sight"], 3)


func test_remove_missing_slot_returns_null() -> void:
	var removed: Part = _chassis.remove(Enums.SlotType.LEGS)
	assert_null(removed)


func test_living_parts_excludes_destroyed() -> void:
	_head_part.hp = 0
	_chassis.install(_torso_part)
	_chassis.install(_head_part)
	var living: Array[Part] = _chassis.living_parts()
	assert_eq(living.size(), 1)
	assert_eq(living[0], _torso_part)


func test_save_load_round_trip_with_nested_containers() -> void:
	var backpack := Part.new()
	backpack.id = &"backpack"
	backpack.slot_type = Enums.SlotType.LEGS
	backpack.part_type = Enums.PartType.STORAGE
	backpack.hp = 5
	backpack.max_hp = 5
	backpack.mass = 2.0
	backpack.volume = 1.0
	backpack.is_container = true
	backpack.max_volume = 20.0
	backpack.mass_multiplier = 0.5

	var pouch := Part.new()
	pouch.id = &"pouch"
	pouch.slot_type = Enums.SlotType.LEGS
	pouch.part_type = Enums.PartType.STORAGE
	pouch.mass = 1.0
	pouch.volume = 2.0
	pouch.is_container = true
	pouch.max_volume = 5.0
	pouch.mass_multiplier = 0.8

	var loose_item := Part.new()
	loose_item.id = &"loose_item"
	loose_item.slot_type = Enums.SlotType.LEGS
	loose_item.part_type = Enums.PartType.STORAGE
	loose_item.mass = 10.0
	loose_item.volume = 3.0

	pouch.contents = [loose_item]
	backpack.contents = [pouch]

	var chassis := Chassis.new()
	chassis.max_mass = 150.0
	chassis.install(_torso_part)
	chassis.install(backpack)

	var matrix := Matrix.new()
	matrix.id = &"matrix_001"
	matrix.display_name = "Test Matrix"
	matrix.level = 3
	matrix.xp = 42
	matrix.perks = [&"perk_a", &"perk_b"]

	var chassis_path := "user://tmp_test_chassis.tres"
	var matrix_path := "user://tmp_test_matrix.tres"
	assert_eq(ResourceSaver.save(chassis, chassis_path), OK)
	assert_eq(ResourceSaver.save(matrix, matrix_path), OK)

	var loaded_chassis: Chassis = ResourceLoader.load(chassis_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var loaded_matrix: Matrix = ResourceLoader.load(matrix_path, "", ResourceLoader.CACHE_MODE_IGNORE)

	assert_eq(loaded_chassis.max_mass, 150.0)
	var loaded_torso: Part = loaded_chassis.slots[Enums.SlotType.TORSO]
	assert_eq(loaded_torso.id, &"torso_plate")
	assert_eq(loaded_torso.stat_mods["armor"], 5)

	var loaded_backpack: Part = loaded_chassis.slots[Enums.SlotType.LEGS]
	assert_eq(loaded_backpack.id, &"backpack")
	assert_eq(loaded_backpack.mass_multiplier, 0.5)
	assert_eq(loaded_backpack.max_volume, 20.0)
	assert_eq(loaded_backpack.contents.size(), 1)

	var loaded_pouch: Part = loaded_backpack.contents[0]
	assert_eq(loaded_pouch.id, &"pouch")
	assert_eq(loaded_pouch.volume, 2.0)
	assert_eq(loaded_pouch.mass_multiplier, 0.8)
	assert_eq(loaded_pouch.contents.size(), 1)

	var loaded_loose_item: Part = loaded_pouch.contents[0]
	assert_eq(loaded_loose_item.id, &"loose_item")
	assert_eq(loaded_loose_item.mass, 10.0)
	assert_eq(loaded_loose_item.volume, 3.0)

	# Appendix D: pouch's 0.8 multiplier is ignored since it's nested, not worn directly;
	# only the backpack's 0.5 applies to the flat sum of pouch (1kg) + loose item (10kg).
	assert_almost_eq(loaded_chassis.carried_mass(), _torso_part.mass + 2.0 + (1.0 + 10.0) * 0.5, 0.0001)

	DirAccess.remove_absolute(chassis_path)
	DirAccess.remove_absolute(matrix_path)

	assert_eq(loaded_matrix.id, &"matrix_001")
	assert_eq(loaded_matrix.display_name, "Test Matrix")
	assert_eq(loaded_matrix.level, 3)
	assert_eq(loaded_matrix.xp, 42)
	assert_eq(loaded_matrix.perks, [&"perk_a", &"perk_b"])
