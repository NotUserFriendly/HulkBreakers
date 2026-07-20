extends GutTest

## docs/10 Phase 12.2: SelectionController is the pure TACTICS-time layer —
## nothing it does may mutate the authoritative CombatState. Two units on an
## open 10x10 grid, matching test_action_queue.gd's fixture style.


func _make_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad)


func test_select_accepts_only_the_current_units_turn() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var selection := SelectionController.new(state)

	selection.select(a)
	assert_eq(selection.selected_unit, a, "a is the current unit — turn order starts with a")

	selection.select(b)
	assert_null(selection.selected_unit, "b isn't the current unit, so selecting it clears")


func test_reachable_cells_matches_pathfinder_exactly() -> void:
	var a := _make_unit(Vector2i(4, 4), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var budget: float = a.mp + a.mp_per_ap() * a.ap
	var expected: Array[Vector2i] = pf.reachable(a.cell, budget)

	assert_eq(selection.reachable_cells(), expected)


func test_queue_move_to_an_unreachable_cell_fails() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(20, 20), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_false(selection.queue_move(Vector2i(19, 19)), "far outside any reachable budget")


func test_queuing_two_moves_shows_two_ghosts_the_second_starting_where_the_first_left_off() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_true(selection.queue_move(Vector2i(1, 0)))
	assert_true(selection.queue_move(Vector2i(2, 0)))

	var ghosts: Array[Array] = selection.ghost_paths()
	assert_eq(ghosts.size(), 2)
	assert_eq(ghosts[0][0], Vector2i(0, 0))
	assert_eq(ghosts[0][ghosts[0].size() - 1], Vector2i(1, 0))
	assert_eq(ghosts[1][0], Vector2i(1, 0), "the second ghost must start where the first ends")
	assert_eq(ghosts[1][ghosts[1].size() - 1], Vector2i(2, 0))


func test_queuing_never_mutates_the_real_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)

	var cell_before: Vector2i = a.cell
	var ap_before: int = a.ap
	var mp_before: float = a.mp
	var occupant_before: int = state.grid.get_occupant_id(Vector2i(1, 0))

	selection.select(a)
	selection.reachable_cells()
	selection.queue_move(Vector2i(1, 0))
	selection.queue_move(Vector2i(2, 0))
	selection.queue_end_turn()

	assert_eq(a.cell, cell_before, "queuing must never move the real unit")
	assert_eq(a.ap, ap_before, "queuing must never spend the real unit's AP")
	assert_eq(a.mp, mp_before, "queuing must never spend the real unit's MP")
	assert_eq(
		state.grid.get_occupant_id(Vector2i(1, 0)),
		occupant_before,
		"queuing must never touch the real grid's occupancy"
	)


## docs/10 taskblock03 D2: "the running MP cost per leg and the total."
func test_leg_costs_matches_pathfinders_own_cost_per_queued_leg() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	selection.queue_move(Vector2i(2, 0))
	selection.queue_move(Vector2i(2, 2))

	var costs: Array[float] = selection.leg_costs()
	assert_eq(costs.size(), 2)
	assert_almost_eq(costs[0], 2.0, 0.0001, "two default-cost steps: (0,0)->(1,0)->(2,0)")
	assert_almost_eq(costs[1], 2.0, 0.0001, "two more steps: (2,0)->(2,1)->(2,2)")


## docs/10 taskblock03 D3: "RMB pops the last queued action."
func test_undo_last_pops_the_most_recently_queued_action() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))
	selection.queue_move(Vector2i(2, 0))

	assert_true(selection.undo_last())

	assert_eq(selection.ghost_paths().size(), 1, "only the first leg remains")
	var remaining: Array = selection.ghost_paths()[0]
	assert_eq(remaining[remaining.size() - 1], Vector2i(1, 0))


func test_undo_last_with_an_empty_queue_returns_false() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_false(selection.undo_last())


func test_undo_last_refunds_the_popped_actions_cost_against_the_speculative_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	var full_budget: Array[Vector2i] = selection.reachable_cells()
	selection.queue_move(Vector2i(1, 0))

	selection.undo_last()

	assert_eq(
		selection.reachable_cells(),
		full_budget,
		"undoing the only queued move must restore the full original reach"
	)


## docs/10 taskblock03 D4: "Reset Turn" restores position, facing, MP, AP,
## and empties the queue — but keeps the unit selected.
func test_reset_turn_clears_the_queue_but_keeps_the_unit_selected() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))
	selection.queue_face(1.0)

	selection.reset_turn()

	assert_eq(selection.selected_unit, a, "still mid-TACTICS for the same unit")
	assert_eq(selection.ghost_paths(), [] as Array[Array])
	assert_almost_eq(selection.previewed_orientation(), 0.0, 0.0001)


func test_reset_turn_with_nothing_selected_is_a_no_op() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)

	selection.reset_turn()  # must not crash with no selection

	assert_null(selection.selected_unit)


## docs/10 taskblock03 F1: previewed_unit()'s own cell/orientation ARE the
## queued end state — the ghost's whole source of truth.
func test_previewed_unit_reflects_the_queued_end_cell() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	selection.queue_move(Vector2i(2, 0))

	assert_eq(selection.previewed_unit().cell, Vector2i(2, 0))
	assert_eq(a.cell, Vector2i(0, 0), "the real unit must still be untouched")


func test_nothing_selected_yields_no_preview_and_no_queue_entries() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)

	assert_null(selection.previewed_unit(), "previewed_unit")
	assert_eq(selection.queue_entries(), [] as Array[Dictionary], "queue_entries")


func test_reset_clears_selection_and_queues() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))

	selection.reset()

	assert_null(selection.selected_unit)
	selection.select(a)
	assert_eq(selection.ghost_paths(), [] as Array[Array], "a fresh queue must have no ghosts")


## docs/10 taskblock06 G2: "each entry: what, its cost, the running AP/MP
## total after it." Cross-checked against the SAME replay ActionQueue.
## preview() does, one action at a time — queue_entries() must never
## drift from what "Resolve to Here" would actually apply.
func test_queue_entries_reports_what_and_the_running_ap_mp_total_per_action() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)

	selection.queue_move(Vector2i(1, 0))
	selection.queue_face(1.0)

	var queue: ActionQueue = selection.current_queue()
	var expected_after_move: CombatState = state.dup()
	queue.actions[0].apply(expected_after_move)
	var expected_after_face: CombatState = expected_after_move.dup()
	queue.actions[1].apply(expected_after_face)

	var entries: Array[Dictionary] = selection.queue_entries()
	assert_eq(entries.size(), 2)
	assert_true((entries[0]["describe"] as String).contains("MoveAction"))
	assert_true((entries[1]["describe"] as String).contains("FaceAction"))
	var after_move: Unit = expected_after_move.find_unit(a.id)
	assert_eq(entries[0]["ap"], after_move.ap)
	assert_almost_eq(entries[0]["mp"] as float, after_move.mp, 0.0001)
	var after_face: Unit = expected_after_face.find_unit(a.id)
	assert_eq(entries[1]["ap"], after_face.ap)
	assert_almost_eq(entries[1]["mp"] as float, after_face.mp, 0.0001)


func test_queue_entries_never_mutates_the_real_state() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [a])
	var selection := SelectionController.new(state)
	selection.select(a)
	selection.queue_move(Vector2i(1, 0))
	var cell_before: Vector2i = a.cell
	var ap_before: int = a.ap

	selection.queue_entries()

	assert_eq(a.cell, cell_before)
	assert_eq(a.ap, ap_before)


func test_queue_end_turn_appends_an_end_turn_action_that_resolves_cleanly() -> void:
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var selection := SelectionController.new(state)
	selection.select(a)

	assert_true(selection.queue_move(Vector2i(1, 0)))
	assert_true(selection.queue_end_turn())

	state.resolve_turn(selection.current_queue())

	assert_eq(a.cell, Vector2i(1, 0), "resolution must actually move the real unit")
	assert_eq(state.current_unit(), b, "ending the turn must advance turn order")


## taskblock-22 Pass A2: mission, when the controller was given one, must
## actually reach EndTurnAction — the human end-turn path is the only way
## a player-driven squad's own extraction hold ever starts.
func test_queue_end_turn_threads_mission_through_for_the_extraction_hold() -> void:
	var a := _make_unit(Vector2i(4, 4), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	var selection := SelectionController.new(state, mission)
	selection.select(a)

	selection.queue_end_turn()
	state.resolve_turn(selection.current_queue())

	assert_eq(
		a.extraction_hold_start_round,
		0,
		"standing on its own tile at end of turn must start the hold"
	)


## taskblock-22 Pass E: repair's own player-facing entry point — a real
## RepairAction, resolved through the normal queue, never a debug-style
## direct mutation.
func test_queue_repair_appends_a_repair_action_that_resolves_cleanly() -> void:
	var target := Part.new()
	target.id = &"leg"
	target.material = &"steel"
	target.hp = 5
	target.max_hp = 10

	var battery := Part.new()
	battery.id = &"tool_battery"
	battery.hp = 3
	battery.max_hp = 3
	battery.battery_capacity = 6.0
	battery.battery_power_out = 3.0
	battery.battery_charge = 6.0
	battery.tags = [&"POWER_SOURCE", &"BATTERY", &"TOOL_BATTERY"]

	var welder := Part.new()
	welder.id = &"welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.tags = [&"WELDER"]
	var battery_socket := Socket.new(&"TOOL_BATTERY")
	battery_socket.occupant = battery
	welder.sockets = [battery_socket]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = welder
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var leg_socket := Socket.new(&"LEG")
	leg_socket.occupant = target
	torso.sockets = [hand_socket, leg_socket]

	var a := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(5, 5), 1)
	var state := CombatState.new(Grid.new(10, 10), [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.gather_resource(&"steel", 5)
	var selection := SelectionController.new(state, mission)
	selection.select(a)

	assert_true(selection.queue_repair(&"welder", &"leg"))
	state.resolve_turn(selection.current_queue())

	assert_eq(target.hp, 8, "5 hp + 3 (capped heal), resolved for real")
