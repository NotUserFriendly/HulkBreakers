extends GutTest


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var torso := Part.new()
	torso.slot_type = Enums.SlotType.TORSO
	torso.part_type = Enums.PartType.ARMOR  # anything but WEAPON — Part.part_type defaults to WEAPON
	torso.hp = 5
	torso.max_hp = 5
	torso.exposure_weight = 40.0  # sole living part in these fixtures — must be selectable

	var weapon := Part.new()
	weapon.slot_type = Enums.SlotType.R_ARM
	weapon.part_type = Enums.PartType.WEAPON
	weapon.hp = 3
	weapon.max_hp = 3

	var chassis := Chassis.new()
	chassis.install(torso)
	chassis.install(weapon)
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
	var torso: Part = target.chassis.slots[Enums.SlotType.TORSO]
	assert_eq(torso.hp, 5 - AttackAction.DEFAULT_DAMAGE)


func test_attack_kills_target_when_torso_destroyed() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(1, 0), 1)
	var torso: Part = target.chassis.slots[Enums.SlotType.TORSO]
	torso.hp = 1
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


func test_attack_rejects_when_attacker_has_no_living_weapon() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(1, 0), 1)
	attacker.chassis.slots[Enums.SlotType.R_ARM].hp = 0
	var state := CombatState.new(grid, [attacker, target])
	assert_false(AttackAction.new(attacker, target).is_legal(state))


func test_destroying_attackers_weapon_removes_its_attack() -> void:
	var grid := Grid.new(10, 10)
	var attacker := _make_unit(Vector2i(0, 0), 0)
	var target := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [attacker, target])

	assert_true(AttackAction.new(attacker, target).is_legal(state))

	var weapon: Part = attacker.chassis.slots[Enums.SlotType.R_ARM]
	weapon.hp = 0
	attacker.chassis.remove(Enums.SlotType.R_ARM)

	assert_false(AttackAction.new(attacker, target).is_legal(state))
