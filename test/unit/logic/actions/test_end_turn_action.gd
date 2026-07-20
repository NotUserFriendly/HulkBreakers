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


## taskblock-22 Pass A2: "enter the tile, and if still there at the end of
## the next round, extracted." Standing on the player squad's own tile,
## objectives already complete, with no prior hold — the first EndTurnAction
## just STARTS the hold (records the current round), never extracts on the
## same turn it arrived.
func test_end_turn_starts_the_hold_on_the_players_own_tile() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(4, 4), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	var starting_round: int = state.round_number

	state.try_apply(EndTurnAction.new(a, mission))

	assert_eq(a.extraction_hold_start_round, starting_round)
	assert_true(a.alive, "one turn on the tile is not enough to extract yet")


func test_end_turn_cancels_the_hold_when_the_unit_is_off_the_tile() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	a.extraction_hold_start_round = 1

	state.try_apply(EndTurnAction.new(a, mission))

	assert_eq(a.extraction_hold_start_round, -1, "leaving the tile cancels an in-progress hold")


## The hold must survive into a LATER round, not just a later call — a
## unit whose own turn comes around again in the SAME round it started
## holding (impossible in real play, each unit gets one turn per round,
## but this is the precise boundary the logic itself checks) must not
## extract early.
func test_end_turn_hold_does_not_complete_within_the_same_round() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(4, 4), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	a.extraction_hold_start_round = state.round_number

	state.try_apply(EndTurnAction.new(a, mission))

	assert_true(a.alive, "same round — the hold has not survived into a later one yet")


func test_end_turn_hold_extracts_once_a_later_round_has_begun() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(4, 4), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	a.extraction_hold_start_round = state.round_number
	state.round_number += 1

	state.try_apply(EndTurnAction.new(a, mission))

	assert_false(a.alive)
	assert_true(a.extracted)


func test_end_turn_hold_requires_every_objective_complete() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(4, 4), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.objectives = [&"gather_minerals"]
	a.extraction_hold_start_round = state.round_number
	state.round_number += 1

	state.try_apply(EndTurnAction.new(a, mission))

	assert_true(a.alive, "an incomplete objective must block even a fully-held extraction")


## taskblock-22 Pass A2: the asymmetry itself — a non-player squad never
## holds at all, regardless of how long it stands on ITS OWN tile (it uses
## ExtractAction's own fast path instead, never this one).
func test_end_turn_hold_never_applies_to_a_non_player_squad() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(0, 0), 0)
	var b := _make_unit(Vector2i(4, 4), 1)
	var state := CombatState.new(grid, [a, b])
	var mission := MissionState.new(RunState.new(), state)
	mission.team_extraction_cells = {1: [Vector2i(4, 4)]}

	state.try_apply(EndTurnAction.new(a, mission))
	state.try_apply(EndTurnAction.new(b, mission))

	assert_eq(b.extraction_hold_start_round, -1, "a non-player squad never starts a hold at all")


## Once the LAST remaining active squad-0 unit's own hold completes,
## MissionState.extract() itself must actually fire — not just this one
## unit's own bookkeeping.
func test_end_turn_hold_completion_triggers_the_mission_extract_once_the_squad_is_out() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(4, 4), 0)
	var already_out := _make_unit(Vector2i(0, 0), 0)
	already_out.alive = false
	already_out.extracted = true
	var enemy := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, already_out, enemy])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	a.extraction_hold_start_round = state.round_number
	state.round_number += 1

	state.try_apply(EndTurnAction.new(a, mission))

	assert_eq(mission.outcome, Enums.MissionOutcome.EXTRACTED)


func test_end_turn_with_no_mission_skips_the_hold_check_entirely() -> void:
	var grid := Grid.new(5, 5)
	var a := _make_unit(Vector2i(4, 4), 0)
	var b := _make_unit(Vector2i(1, 0), 1)
	var state := CombatState.new(grid, [a, b])

	state.try_apply(EndTurnAction.new(a))

	assert_eq(a.extraction_hold_start_round, -1)
	assert_true(a.alive)
