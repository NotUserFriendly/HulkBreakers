extends GutTest


func _make_unit(cell: Vector2i, agility: float = 0.0) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	root.stat_mods = {"agility": agility}
	return Unit.new(Matrix.new(), Frame.new(root), cell, 0)


func test_move_costs_right_mp_and_burns_ap_in_chunks() -> void:
	# agility=0 -> mp_per_ap = BASE_MP = 2.0; max_ap default = 2.
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var action := MoveAction.new(unit, path)
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_eq(unit.cell, Vector2i(3, 0))
	# step1: mp 0<1 -> burn 1 AP for +2 MP (mp=2), spend 1 -> mp=1, ap=1
	# step2: mp 1>=1 -> spend 1 -> mp=0, ap=1
	# step3: mp 0<1 -> burn 1 AP for +2 MP (mp=2), spend 1 -> mp=1, ap=0
	assert_eq(unit.ap, 0)
	assert_almost_eq(unit.mp, 1.0, 0.0001)


func test_move_fails_when_ap_runs_out_mid_path() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	unit.max_ap = 1
	var state := CombatState.new(grid, [unit])

	# 3 steps at cost 1 each needs 2 AP-worth of MP conversions (2 AP -> 4 MP for 3 MP of movement);
	# with only 1 AP available, the 3rd step can't be covered.
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var action := MoveAction.new(unit, path)
	assert_false(action.is_legal(state))
	assert_false(state.try_apply(action))
	assert_eq(unit.cell, Vector2i(0, 0), "an illegal move must not partially apply")
	assert_eq(unit.ap, 1, "AP must be untouched when the action is rejected")


func test_move_rejects_path_not_starting_at_units_cell() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var action := MoveAction.new(unit, [Vector2i(5, 5), Vector2i(6, 5)])
	assert_false(action.is_legal(state))


func test_move_rejects_when_not_units_turn() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0))
	var b := _make_unit(Vector2i(5, 5))
	b.squad_id = 1
	var state := CombatState.new(grid, [a, b])

	var action := MoveAction.new(b, [Vector2i(5, 5), Vector2i(6, 5)])
	assert_false(action.is_legal(state))


func test_move_rejects_blocked_destination() -> void:
	var grid := Grid.new(10, 10)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.WALL)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var action := MoveAction.new(unit, [Vector2i(0, 0), Vector2i(1, 0)])
	assert_false(action.is_legal(state))


func test_move_rejects_non_adjacent_step() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var action := MoveAction.new(unit, [Vector2i(0, 0), Vector2i(5, 5)])
	assert_false(action.is_legal(state))


func test_move_rejects_trivial_single_cell_path() -> void:
	var grid := Grid.new(10, 10)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var action := MoveAction.new(unit, [Vector2i(0, 0)])
	assert_false(action.is_legal(state))


func test_leftover_mp_is_discarded_at_end_of_turn() -> void:
	var grid := Grid.new(10, 10)
	var mover := _make_unit(Vector2i(0, 0))
	var other := _make_unit(Vector2i(9, 9))
	other.squad_id = 1
	var state := CombatState.new(grid, [mover, other])

	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	assert_true(state.try_apply(MoveAction.new(mover, path)))
	assert_almost_eq(mover.mp, 1.0, 0.0001, "leftover MP exists right after moving")

	assert_true(state.try_apply(EndTurnAction.new(mover)))
	assert_true(state.try_apply(EndTurnAction.new(other)))  # cycle back to mover

	assert_eq(state.current_unit(), mover)
	assert_eq(mover.mp, 0.0, "leftover MP must not bank into the next turn")
	assert_eq(mover.ap, mover.max_ap)
