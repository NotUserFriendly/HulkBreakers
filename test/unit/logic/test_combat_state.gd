extends GutTest


func _make_unit(cell: Vector2i, squad: int) -> Unit:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


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


func test_round_number_increments_once_per_full_cycle_not_per_unit_turn() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var c := _make_unit(Vector2i(2, 0), 0)
	var state := CombatState.new(grid, [a, b, c])
	assert_eq(state.round_number, 0)

	state.advance_turn()  # a -> b, still round 0
	assert_eq(state.current_unit(), b)
	assert_eq(state.round_number, 0)

	state.advance_turn()  # b -> c, still round 0
	assert_eq(state.current_unit(), c)
	assert_eq(state.round_number, 0)

	state.advance_turn()  # c -> a, wraps: round 1
	assert_eq(state.current_unit(), a)
	assert_eq(state.round_number, 1)

	state.advance_turn()
	state.advance_turn()
	state.advance_turn()
	assert_eq(state.round_number, 2)


func test_round_number_increments_every_turn_with_a_single_unit() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [a])
	assert_eq(state.round_number, 0)
	state.advance_turn()
	assert_eq(state.round_number, 1)
	state.advance_turn()
	assert_eq(state.round_number, 2)


func test_round_number_wraps_correctly_around_a_dead_unit() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var c := _make_unit(Vector2i(2, 0), 0)
	var state := CombatState.new(grid, [a, b, c])
	b.alive = false

	state.advance_turn()  # a -> c (b skipped), still round 0
	assert_eq(state.current_unit(), c)
	assert_eq(state.round_number, 0)

	state.advance_turn()  # c -> a, wraps: round 1
	assert_eq(state.current_unit(), a)
	assert_eq(state.round_number, 1)


func test_advance_turn_emits_turn_start_for_the_incoming_unit() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.advance_turn()

	var starts: Array[LogEvent] = sink.events_of_kind(&"turn_start")
	assert_eq(starts.size(), 1)
	assert_eq(starts[0].unit_id, b.id)


func test_organics_decay_demotion_emits_surrogate_demoted() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(grid, [a])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	a.exposed_turns = 1
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	while a.exposed_turns < Unit.DECAY_TURNS:
		state.advance_turn()
		assert_true(sink.events_of_kind(&"surrogate_demoted").is_empty())

	state.advance_turn()  # crosses the decay threshold: demotes exactly once

	var demotions: Array[LogEvent] = sink.events_of_kind(&"surrogate_demoted")
	assert_eq(demotions.size(), 1)
	assert_eq(demotions[0].unit_id, a.id)
	assert_eq(demotions[0].data.get("to"), SurrogateLadder.demote(ladder[0], ladder).id)


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


## docs/10 taskblock02 F1: "Control All Squads," the default this build
## ships with — every squad starts HUMAN with no override needed.
func test_every_squad_defaults_to_human_control() -> void:
	var state := CombatState.new(Grid.new(5, 5))

	assert_eq(state.controller_for(0), Enums.SquadController.HUMAN)
	assert_eq(state.controller_for(1), Enums.SquadController.HUMAN)


func test_a_squad_can_be_set_to_ai_control() -> void:
	var state := CombatState.new(Grid.new(5, 5))

	state.set_squad_controller(1, Enums.SquadController.AI)

	assert_eq(state.controller_for(0), Enums.SquadController.HUMAN, "only squad 1 was touched")
	assert_eq(state.controller_for(1), Enums.SquadController.AI)


func test_dup_carries_squad_controllers_into_the_preview() -> void:
	var state := CombatState.new(Grid.new(5, 5))
	state.set_squad_controller(1, Enums.SquadController.AI)

	var preview: CombatState = state.dup()

	assert_eq(preview.controller_for(1), Enums.SquadController.AI)
