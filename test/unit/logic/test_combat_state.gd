extends GutTest


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Frame.new(root), cell, squad)


func test_add_unit_assigns_sequential_ids_and_occupies_cell() -> void:
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	state.add_unit(a)
	state.add_unit(b)
	assert_eq(a.id, 0)
	assert_eq(b.id, 1)
	assert_eq(grid.get_occupant_id(Vector2i(0, 0)), 0)
	assert_eq(grid.get_occupant_id(Vector2i(1, 0)), 1)


func test_initial_units_get_first_turn_started() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	assert_eq(state.current_unit(), a)
	assert_eq(a.ap, a.max_ap)
	assert_eq(a.mp, 0.0)


func test_advance_turn_cycles_and_resets_ap() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])

	a.ap = 0
	state.advance_turn()
	assert_eq(state.current_unit(), b)
	assert_eq(b.ap, b.max_ap)

	state.advance_turn()
	assert_eq(state.current_unit(), a)
	assert_eq(a.ap, a.max_ap)


func test_advance_turn_skips_dead_units() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var c := _make_unit(Vector2i(2, 0), 0)
	var state := CombatState.new(grid, [a, b, c])

	b.alive = false
	state.advance_turn()
	assert_eq(state.current_unit(), c)


func test_is_over_when_one_squad_remains() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	assert_false(state.is_over())
	b.alive = false
	assert_true(state.is_over())


func test_try_apply_rejects_illegal_action_without_mutating() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])

	var end_turn_for_b := EndTurnAction.new(b)  # not b's turn yet
	var ok: bool = state.try_apply(end_turn_for_b)
	assert_false(ok)
	assert_eq(state.current_unit(), a)
	assert_eq(state.action_log.size(), 0)
