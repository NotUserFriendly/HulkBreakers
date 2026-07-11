extends GutTest


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var core := Part.new()
	core.slot_type = Enums.SlotType.CORE
	core.hp = 5
	core.max_hp = 5
	var chassis := Chassis.new()
	chassis.install(core)
	return Unit.new(Matrix.new(), chassis, cell, squad)


func test_attack_deals_damage_and_costs_ap() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [attacker, target])

	var action := AttackAction.new(attacker, target)
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(attacker.ap, attacker.max_ap - AttackAction.AP_COST)
	var core: Part = target.chassis.slots[Enums.SlotType.CORE]
	assert_eq(core.hp, 5 - AttackAction.DEFAULT_DAMAGE)


func test_attack_kills_target_when_last_part_destroyed() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(1, 0), 1)
	var core: Part = target.chassis.slots[Enums.SlotType.CORE]
	core.hp = 1
	var state := CombatState.new(grid, [attacker, target])

	assert_true(state.try_apply(AttackAction.new(attacker, target)))
	assert_false(target.alive)
	assert_eq(grid.get_occupant_id(target.cell), -1)


func test_attack_rejects_own_squad() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var ally := _make_unit(Vector2i(1, 0), 0)
	var state := CombatState.new(grid, [attacker, ally])
	assert_false(AttackAction.new(attacker, ally).is_legal(state))


func test_attack_rejects_out_of_range() -> void:
	var grid := Grid.new(20, 20)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(19, 19), 1)
	var state := CombatState.new(grid, [attacker, target])
	assert_false(AttackAction.new(attacker, target).is_legal(state))


func test_attack_rejects_without_los() -> void:
	var grid := Grid.new(10, 10)
	for y in range(10):
		grid.set_opacity(Vector2i(3, y), 1.0)
	var attacker := _make_unit(Vector2i(0, 3), 0)
	var target := _make_unit(Vector2i(6, 3), 1)
	var state := CombatState.new(grid, [attacker, target])
	assert_false(AttackAction.new(attacker, target).is_legal(state))


func test_attack_rejects_when_insufficient_ap() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [attacker, target])
	attacker.ap = 0
	assert_false(AttackAction.new(attacker, target).is_legal(state))
