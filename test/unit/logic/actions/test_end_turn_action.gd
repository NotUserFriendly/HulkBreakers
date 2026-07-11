extends GutTest


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var chassis := Chassis.new()
	var torso := Part.new()
	torso.slot_type = Enums.SlotType.TORSO
	torso.hp = 5
	torso.max_hp = 5
	chassis.install(torso)
	return Unit.new(Matrix.new(), chassis, cell, squad)


func test_end_turn_advances_turn_order() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])

	assert_true(state.try_apply(EndTurnAction.new(a)))
	assert_eq(state.current_unit(), b)
	assert_eq(state.action_log[-1], "EndTurnAction: unit %d ended turn" % a.id)


func test_end_turn_rejects_when_not_units_turn() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	assert_false(state.try_apply(EndTurnAction.new(b)))
