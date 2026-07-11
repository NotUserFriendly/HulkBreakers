extends GutTest

## Phase 7 acceptance: a scripted turn sequence yields the expected action
## log; illegal actions are rejected (and never logged/mutate state); turn
## order advances correctly.


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var chassis := Chassis.new()
	var core := Part.new()
	core.slot_type = Enums.SlotType.CORE
	core.hp = 5
	core.max_hp = 5
	chassis.install(core)
	return Unit.new(Matrix.new(), chassis, cell, squad)


func test_scripted_turn_sequence() -> void:
	var grid := Grid.new(10, 10)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(2, 0), 1)
	var state := CombatState.new(grid, [a, b])

	assert_eq(state.current_unit(), a)

	# Illegal: it's not b's turn yet.
	var out_of_turn_move := MoveAction.new(b, [Vector2i(2, 0), Vector2i(3, 0)])
	assert_false(state.try_apply(out_of_turn_move))
	assert_eq(state.action_log.size(), 0)
	assert_eq(b.cell, Vector2i(2, 0))

	# Legal: a moves adjacent to b.
	var move_a := MoveAction.new(a, [Vector2i(0, 0), Vector2i(1, 0)])
	assert_true(state.try_apply(move_a))
	assert_eq(a.cell, Vector2i(1, 0))

	# Legal: a attacks b.
	var attack := AttackAction.new(a, b)
	assert_true(state.try_apply(attack))
	var b_core: Part = b.chassis.slots[Enums.SlotType.CORE]
	assert_eq(b_core.hp, 5 - AttackAction.DEFAULT_DAMAGE)
	assert_true(b.alive)

	# Legal: a ends turn.
	assert_true(state.try_apply(EndTurnAction.new(a)))
	assert_eq(state.current_unit(), b)

	# Illegal: b tries to move onto a's occupied cell.
	var blocked_move := MoveAction.new(b, [Vector2i(2, 0), Vector2i(1, 0)])
	assert_false(state.try_apply(blocked_move))
	assert_eq(b.cell, Vector2i(2, 0))

	# Legal: b ends turn, wrapping back to a.
	assert_true(state.try_apply(EndTurnAction.new(b)))
	assert_eq(state.current_unit(), a)
	assert_eq(a.ap, a.max_ap, "a's AP must reset at the start of its next turn")

	var expected_log: Array[String] = [
		"MoveAction: unit %d moved to %s" % [a.id, Vector2i(1, 0)],
		"AttackAction: unit %d attacked unit %d" % [a.id, b.id],
		"EndTurnAction: unit %d ended turn" % a.id,
		"EndTurnAction: unit %d ended turn" % b.id,
	]
	assert_eq(state.action_log, expected_log)
