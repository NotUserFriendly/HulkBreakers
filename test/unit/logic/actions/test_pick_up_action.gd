extends GutTest


func _make_unit_with_backpack(cell: Vector2i) -> Dictionary:
	var backpack := Part.new()
	backpack.slot_type = Enums.SlotType.TORSO
	backpack.is_container = true
	var chassis := Chassis.new()
	chassis.install(backpack)
	var unit := Unit.new(Matrix.new(), chassis, cell, 0)
	return {"unit": unit, "backpack": backpack}


func test_pick_up_part_into_carried_container() -> void:
	var grid := Grid.new(5, 5)
	var rig: Dictionary = _make_unit_with_backpack(Vector2i(0, 0))
	var unit: Unit = rig["unit"]
	var backpack: Part = rig["backpack"]
	var state := CombatState.new(grid, [unit])

	var salvage := Part.new()
	salvage.id = &"salvage_plate"
	grid.field_items[Vector2i(1, 0)] = [salvage]

	var action := PickUpAction.new(unit, Vector2i(1, 0), salvage, backpack)
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_true(backpack.contents.has(salvage))
	assert_false(grid.field_items.has(Vector2i(1, 0)))
	assert_eq(unit.ap, unit.max_ap - PickUpAction.AP_COST)


func test_pick_up_matrix_goes_to_held_matrix_not_container() -> void:
	var grid := Grid.new(5, 5)
	var rig: Dictionary = _make_unit_with_backpack(Vector2i(0, 0))
	var unit: Unit = rig["unit"]
	var backpack: Part = rig["backpack"]
	var state := CombatState.new(grid, [unit])

	var matrix := Matrix.new()
	grid.field_items[Vector2i(0, 1)] = [matrix]

	var action := PickUpAction.new(unit, Vector2i(0, 1), matrix)
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.held_matrix, matrix)
	assert_eq(backpack.contents.size(), 0)


func test_pick_up_rejects_item_not_present_at_cell() -> void:
	var grid := Grid.new(5, 5)
	var rig: Dictionary = _make_unit_with_backpack(Vector2i(0, 0))
	var unit: Unit = rig["unit"]
	var backpack: Part = rig["backpack"]
	var state := CombatState.new(grid, [unit])

	var phantom := Part.new()
	var action := PickUpAction.new(unit, Vector2i(1, 0), phantom, backpack)
	assert_false(action.is_legal(state))


func test_pick_up_rejects_too_far_away() -> void:
	var grid := Grid.new(10, 10)
	var rig: Dictionary = _make_unit_with_backpack(Vector2i(0, 0))
	var unit: Unit = rig["unit"]
	var backpack: Part = rig["backpack"]
	var state := CombatState.new(grid, [unit])

	var item := Part.new()
	grid.field_items[Vector2i(5, 5)] = [item]
	var action := PickUpAction.new(unit, Vector2i(5, 5), item, backpack)
	assert_false(action.is_legal(state))


func test_pick_up_rejects_when_container_not_carried() -> void:
	var grid := Grid.new(5, 5)
	var rig: Dictionary = _make_unit_with_backpack(Vector2i(0, 0))
	var unit: Unit = rig["unit"]
	var state := CombatState.new(grid, [unit])

	var item := Part.new()
	grid.field_items[Vector2i(1, 0)] = [item]
	var foreign_container := Part.new()
	foreign_container.is_container = true

	var action := PickUpAction.new(unit, Vector2i(1, 0), item, foreign_container)
	assert_false(action.is_legal(state))
