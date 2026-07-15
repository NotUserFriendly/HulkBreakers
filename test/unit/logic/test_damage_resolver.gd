extends GutTest


func _make_torso_only_unit(cell: Vector2i, squad: int, matrix_id: StringName) -> Unit:
	var chassis := Chassis.new()
	var torso := Part.new()
	torso.slot_type = Enums.SlotType.TORSO
	torso.hp = 1
	torso.max_hp = 5
	var matrix := Matrix.new()
	matrix.id = matrix_id
	chassis.install(torso)
	return Unit.new(matrix, chassis, cell, squad)


func test_destroying_a_part_removes_stat_mods_and_drops_contents() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	var backpack := Part.new()
	backpack.slot_type = Enums.SlotType.HEAD
	backpack.hp = 1
	backpack.max_hp = 1
	backpack.stat_mods = {"armor": 5}
	var loose_item := Part.new()
	loose_item.id = &"loose"
	backpack.contents = [loose_item]
	chassis.install(backpack)

	var unit := Unit.new(Matrix.new(), chassis, Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])

	var hit := HitResult.new()
	hit.part = backpack
	DamageResolver.apply(hit, 5, state, unit)

	assert_false(chassis.slots.has(Enums.SlotType.HEAD))
	assert_eq(chassis.aggregate_stats().get("armor", 0), 0)
	assert_true(grid.field_items.has(Vector2i(2, 2)))
	assert_true((grid.field_items[Vector2i(2, 2)] as Array).has(loose_item))


func test_destroying_weapon_part_removes_it_from_chassis() -> void:
	var grid := Grid.new(5, 5)
	var chassis := Chassis.new()
	var weapon := Part.new()
	weapon.slot_type = Enums.SlotType.R_ARM
	weapon.part_type = Enums.PartType.WEAPON
	weapon.hp = 3
	weapon.max_hp = 3
	chassis.install(weapon)
	var unit := Unit.new(Matrix.new(), chassis, Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var hit := HitResult.new()
	hit.part = weapon
	DamageResolver.apply(hit, 3, state, unit)

	assert_false(chassis.slots.has(Enums.SlotType.R_ARM))


func test_destroying_torso_disables_chassis_and_ejects_matrix() -> void:
	var grid := Grid.new(7, 7)
	var victim := _make_torso_only_unit(Vector2i(3, 3), 0, &"victim_matrix")
	# pure-diagonal offset -> unique nearest neighbor
	var ally := _make_torso_only_unit(Vector2i(5, 5), 0, &"ally_matrix")
	var enemy := _make_torso_only_unit(Vector2i(0, 0), 1, &"enemy_matrix")
	var state := CombatState.new(grid, [victim, ally, enemy])

	var torso: Part = victim.chassis.slots[Enums.SlotType.TORSO]
	var hit := HitResult.new()
	hit.part = torso
	DamageResolver.apply(hit, 5, state, victim)

	assert_false(victim.alive)
	assert_eq(grid.get_occupant_id(Vector2i(3, 3)), -1)
	assert_not_null(victim.matrix, "the matrix itself persists regardless of ejection")

	var drop_cell := Vector2i(4, 4)  # the unique free neighbor of (3,3) nearest ally at (5,5)
	assert_true(grid.field_items.has(drop_cell))
	var items: Array = grid.field_items[drop_cell]
	assert_eq(items.size(), 1)
	var ejected: Matrix = items[0]
	assert_eq(ejected, victim.matrix)


func test_eject_tie_break_uses_lowest_row_major_cell_index() -> void:
	var grid := Grid.new(7, 7)
	# Ally at (5,4): (4,3) and (4,4) both tie at chebyshev distance 1 from the
	# ally; (4,3) has the lower row-major index (y*width+x) and must win.
	var victim := _make_torso_only_unit(Vector2i(3, 3), 0, &"victim_matrix")
	var ally := _make_torso_only_unit(Vector2i(5, 4), 0, &"ally_matrix")
	var state := CombatState.new(grid, [victim, ally])

	var torso: Part = victim.chassis.slots[Enums.SlotType.TORSO]
	var hit := HitResult.new()
	hit.part = torso
	DamageResolver.apply(hit, 5, state, victim)

	assert_true(grid.field_items.has(Vector2i(4, 3)))
	assert_false(grid.field_items.has(Vector2i(4, 4)))


func test_eject_with_no_living_ally_falls_back_to_nearest_own_cell() -> void:
	var grid := Grid.new(7, 7)
	var victim := _make_torso_only_unit(Vector2i(3, 3), 0, &"lone_matrix")
	var state := CombatState.new(grid, [victim])

	var torso: Part = victim.chassis.slots[Enums.SlotType.TORSO]
	var hit := HitResult.new()
	hit.part = torso
	DamageResolver.apply(hit, 5, state, victim)

	# All 8 neighbors of (3,3) are equidistant (1) from (3,3) itself; lowest
	# row-major index among them (width 7) is (2,2) at index 16.
	assert_true(grid.field_items.has(Vector2i(2, 2)))


func test_ejected_matrix_is_recoverable_by_adjacent_ally() -> void:
	var grid := Grid.new(7, 7)
	var victim := _make_torso_only_unit(Vector2i(3, 3), 0, &"victim_matrix")
	var ally := _make_torso_only_unit(Vector2i(5, 5), 0, &"ally_matrix")
	var state := CombatState.new(grid, [victim, ally])

	var torso: Part = victim.chassis.slots[Enums.SlotType.TORSO]
	var hit := HitResult.new()
	hit.part = torso
	DamageResolver.apply(hit, 5, state, victim)

	var drop_cell := Vector2i(4, 4)
	assert_true(grid.field_items.has(drop_cell))
	var ejected: Matrix = grid.field_items[drop_cell][0]

	state.advance_turn()  # victim is dead, so this reaches the ally
	assert_eq(state.current_unit(), ally)

	var pickup := PickUpAction.new(ally, drop_cell, ejected)
	assert_true(pickup.is_legal(state))
	assert_true(state.try_apply(pickup))
	assert_eq(ally.held_matrix, ejected)


func test_damage_resolver_damages_cover_object_via_hit_result() -> void:
	var grid := Grid.new(5, 5)
	var cell := Vector2i(2, 2)
	grid.set_cover_value(cell, 1.0)
	var crate := Part.new()
	crate.is_destructible = true
	crate.hp = 5
	crate.max_hp = 5
	grid.blockers[cell] = crate

	var unit := Unit.new(Matrix.new(), Chassis.new(), Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var hit := HitResult.new()
	hit.cover_object = crate
	hit.cover_cell = cell
	DamageResolver.apply(hit, 5, state, unit)

	assert_eq(crate.hp, 0)
	assert_false(grid.blockers.has(cell))
	assert_eq(grid.get_cover_value(cell), 0.0)


func test_damage_resolver_blocked_hit_has_no_effect() -> void:
	var grid := Grid.new(5, 5)
	var unit := Unit.new(Matrix.new(), Chassis.new(), Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [unit])

	var hit := HitResult.new()
	hit.blocked = true
	DamageResolver.apply(hit, 5, state, unit)

	assert_true(unit.alive)
	assert_eq(grid.field_items.size(), 0)
