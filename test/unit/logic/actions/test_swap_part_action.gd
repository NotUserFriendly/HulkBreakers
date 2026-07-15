extends GutTest


func _make_weapon(id: StringName, damage: int) -> Part:
	var w := Part.new()
	w.id = id
	w.slot_type = Enums.SlotType.R_ARM
	w.part_type = Enums.PartType.WEAPON
	w.hp = 3
	w.max_hp = 3
	w.stat_mods = {"damage": damage}
	return w


func test_swap_installs_new_part_and_returns_old_to_container() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	var old_weapon := _make_weapon(&"old_gun", 3)
	chassis.install(old_weapon)

	var backpack := Part.new()
	backpack.is_container = true
	var spare_weapon := _make_weapon(&"spare_gun", 7)
	backpack.contents = [spare_weapon]

	var unit := Unit.new(Matrix.new(), chassis, Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var action := SwapPartAction.new(unit, Enums.SlotType.R_ARM, backpack, spare_weapon)
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(chassis.slots[Enums.SlotType.R_ARM], spare_weapon)
	assert_eq(unit.ap, unit.max_ap - SwapPartAction.AP_COST)
	assert_true(backpack.contents.has(old_weapon))
	assert_false(backpack.contents.has(spare_weapon))
	assert_eq(chassis.aggregate_stats()["damage"], 7)


func test_swap_rejects_part_not_in_container() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	chassis.install(_make_weapon(&"old_gun", 3))
	var backpack := Part.new()
	backpack.is_container = true
	var unit := Unit.new(Matrix.new(), chassis, Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var stray_part := _make_weapon(&"not_in_bag", 9)
	var action := SwapPartAction.new(unit, Enums.SlotType.R_ARM, backpack, stray_part)
	assert_false(action.is_legal(state))


func test_swap_rejects_wrong_slot_type() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	var backpack := Part.new()
	backpack.is_container = true
	var leg_part := Part.new()
	leg_part.slot_type = Enums.SlotType.LEGS
	backpack.contents = [leg_part]
	var unit := Unit.new(Matrix.new(), chassis, Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var action := SwapPartAction.new(unit, Enums.SlotType.R_ARM, backpack, leg_part)
	assert_false(action.is_legal(state))


func test_swap_rejects_when_insufficient_ap() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	var backpack := Part.new()
	backpack.is_container = true
	var spare := _make_weapon(&"spare", 5)
	backpack.contents = [spare]
	var unit := Unit.new(Matrix.new(), chassis, Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])
	unit.ap = 0

	var action := SwapPartAction.new(unit, Enums.SlotType.R_ARM, backpack, spare)
	assert_false(action.is_legal(state))


func test_swap_rejects_when_displaced_part_would_not_fit_back_in_container() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	var bulky_old_weapon := _make_weapon(&"old_gun", 3)
	bulky_old_weapon.volume = 10.0
	chassis.install(bulky_old_weapon)

	var backpack := Part.new()
	backpack.is_container = true
	backpack.max_volume = 5.0  # too small for the bulky old weapon once it's displaced

	var spare_weapon := _make_weapon(&"spare_gun", 7)
	spare_weapon.volume = 1.0
	backpack.contents = [spare_weapon]

	var unit := Unit.new(Matrix.new(), chassis, Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var action := SwapPartAction.new(unit, Enums.SlotType.R_ARM, backpack, spare_weapon)
	assert_false(action.is_legal(state))
	assert_false(state.try_apply(action))
	assert_eq(
		chassis.slots[Enums.SlotType.R_ARM],
		bulky_old_weapon,
		"a rejected swap must not mutate the chassis"
	)
