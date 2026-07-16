extends GutTest


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_end_turn_advances_turn_order() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])

	assert_true(state.try_apply(EndTurnAction.new(a)))
	assert_eq(state.current_unit(), b)
	assert_eq(state.action_log[-1], "EndTurnAction: unit %d ended turn" % a.id)


func test_end_turn_emits_turn_end_for_the_ending_unit_then_turn_start_for_the_next() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(EndTurnAction.new(a))

	assert_eq(sink.events.size(), 2)
	assert_eq(sink.events[0].kind, &"turn_end")
	assert_eq(sink.events[0].unit_id, a.id)
	assert_eq(sink.events[1].kind, &"turn_start")
	assert_eq(sink.events[1].unit_id, b.id)


## A unit can die mid-turn from its own queued action (docs/09: e.g.
## cook-off, or a shot that reaches back to its own body) — ending that
## turn must still be legal, or turn order would stall on the corpse
## forever, since advance_turn() is only ever reached from here.
func test_end_turn_is_legal_and_advances_even_if_the_current_unit_just_died() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])

	a.alive = false

	assert_true(EndTurnAction.new(a).is_legal(state))
	assert_true(state.try_apply(EndTurnAction.new(a)))
	assert_eq(state.current_unit(), b)


func test_end_turn_rejects_when_not_units_turn() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	assert_false(state.try_apply(EndTurnAction.new(b)))
