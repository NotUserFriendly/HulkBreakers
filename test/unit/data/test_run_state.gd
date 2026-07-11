extends GutTest


func _make_unit(cell: Vector2i, squad: int, matrix_id: StringName) -> Unit:
	var chassis := Chassis.new()
	var core := Part.new()
	core.slot_type = Enums.SlotType.CORE
	core.part_type = Enums.PartType.ARMOR
	core.hp = 5
	core.max_hp = 5
	core.exposure_weight = 40.0
	var weapon := Part.new()
	weapon.slot_type = Enums.SlotType.R_ARM
	weapon.part_type = Enums.PartType.WEAPON
	weapon.hp = 3
	weapon.max_hp = 3
	chassis.install(core)
	chassis.install(weapon)
	var matrix := Matrix.new()
	matrix.id = matrix_id
	matrix.xp = 5
	return Unit.new(matrix, chassis, cell, squad)


func test_resolve_defeat_strips_parts_but_keeps_matrices() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0), 0, &"pilot_a")
	var b := _make_unit(Vector2i(1, 0), 1, &"enemy_a")
	var state := CombatState.new(grid, [a, b])

	var run := RunState.new()
	run.resolve_defeat(state, 0)

	assert_true(run.roster.has(a.matrix))
	assert_eq(a.matrix.xp, 5, "defeat keeps whatever XP the matrix already had")
	assert_true(a.chassis.slots.is_empty())


func test_resolve_victory_grants_xp_and_salvages_enemy_parts() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0), 0, &"pilot_a")
	var b := _make_unit(Vector2i(1, 0), 1, &"enemy_a")
	var state := CombatState.new(grid, [a, b])

	var run := RunState.new()
	run.resolve_victory(state, 0)

	assert_true(run.roster.has(a.matrix))
	assert_eq(a.matrix.xp, 5 + RunState.VICTORY_XP_REWARD)
	assert_true(b.chassis.slots.is_empty())
	assert_eq(run.part_stash.size(), 2)  # enemy's core + weapon
	assert_true(run.chassis_stash.has(b.chassis))


func test_matrix_never_ejected_ends_recovered() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0), 0, &"pilot_a")
	var b := _make_unit(Vector2i(1, 0), 1, &"enemy_a")
	var state := CombatState.new(grid, [a, b])

	var run := RunState.new()
	run.resolve_victory(state, 0)

	assert_eq(a.matrix.recovery_state, Enums.RecoveryState.RECOVERED)
	assert_false(a.matrix.pending_return_penalty)


func test_ejected_and_recovered_matrix_ends_recovered_with_no_flag() -> void:
	var grid := Grid.new(10, 10)
	var victim := _make_unit(Vector2i(3, 3), 0, &"pilot_victim")
	var ally := _make_unit(Vector2i(5, 5), 0, &"pilot_ally")
	var enemy := _make_unit(Vector2i(0, 0), 1, &"enemy_a")
	var state := CombatState.new(grid, [victim, ally, enemy])

	var core: Part = victim.chassis.slots[Enums.SlotType.CORE]
	core.hp = 1
	var hit := HitResult.new()
	hit.part = core
	DamageResolver.apply(hit, 5, state, victim)  # ejects victim's matrix as a MatrixCore

	assert_false(victim.alive)

	var drop_cell := Vector2i(4, 4)  # unique free neighbor of (3,3) nearest ally at (5,5)
	var ejected: MatrixCore = state.grid.field_items[drop_cell][0]
	state.advance_turn()  # victim is dead -> lands directly on ally, next in turn order
	assert_eq(state.current_unit(), ally)

	var pickup := PickUpAction.new(ally, drop_cell, ejected)
	assert_true(state.try_apply(pickup))

	var run := RunState.new()
	run.resolve_victory(state, 0)

	assert_eq(victim.matrix.recovery_state, Enums.RecoveryState.RECOVERED)
	assert_false(victim.matrix.pending_return_penalty)
	assert_true(run.roster.has(victim.matrix))


func test_ejected_and_abandoned_matrix_ends_left_behind_but_stays_in_roster() -> void:
	var grid := Grid.new(10, 10)
	var victim := _make_unit(Vector2i(3, 3), 0, &"pilot_victim")
	var enemy := _make_unit(Vector2i(0, 0), 1, &"enemy_a")
	var state := CombatState.new(grid, [victim, enemy])

	var core: Part = victim.chassis.slots[Enums.SlotType.CORE]
	core.hp = 1
	var hit := HitResult.new()
	hit.part = core
	DamageResolver.apply(hit, 5, state, victim)  # ejects, nobody picks it up

	var run := RunState.new()
	run.resolve_defeat(state, 0)

	assert_eq(victim.matrix.recovery_state, Enums.RecoveryState.LEFT_BEHIND)
	assert_true(victim.matrix.pending_return_penalty)
	assert_true(run.roster.has(victim.matrix), "roguelike rule is absolute: the matrix still returns")


func test_apply_perk_is_idempotent() -> void:
	var matrix := Matrix.new()
	var run := RunState.new()
	run.apply_perk(matrix, &"tough")
	run.apply_perk(matrix, &"tough")
	assert_eq(matrix.perks, [&"tough"])


func test_run_state_save_load_round_trip_including_recovery_state() -> void:
	var matrix := Matrix.new()
	matrix.id = &"pilot_a"
	matrix.xp = 42
	matrix.recovery_state = Enums.RecoveryState.LEFT_BEHIND
	matrix.pending_return_penalty = true

	var run := RunState.new()
	run.roster = [matrix]
	run.salvage = 12
	run.credits = 99
	run.seed = 777

	var part := Part.new()
	part.id = &"salvaged_plate"
	run.part_stash = [part]
	var chassis := Chassis.new()
	run.chassis_stash = [chassis]

	var path := "user://tmp_test_run_state.tres"
	assert_eq(ResourceSaver.save(run, path), OK)
	var loaded: RunState = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(path)

	assert_eq(loaded.roster.size(), 1)
	assert_eq(loaded.roster[0].id, &"pilot_a")
	assert_eq(loaded.roster[0].xp, 42)
	assert_eq(loaded.roster[0].recovery_state, Enums.RecoveryState.LEFT_BEHIND)
	assert_true(loaded.roster[0].pending_return_penalty)
	assert_eq(loaded.salvage, 12)
	assert_eq(loaded.credits, 99)
	assert_eq(loaded.seed, 777)
	assert_eq(loaded.part_stash.size(), 1)
	assert_eq(loaded.part_stash[0].id, &"salvaged_plate")
	assert_eq(loaded.chassis_stash.size(), 1)
