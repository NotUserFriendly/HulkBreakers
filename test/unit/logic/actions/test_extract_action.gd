extends GutTest

## taskblock-22 Pass A2: ExtractAction is now the FAST, asymmetric half of
## extraction only — "an Extract ACTION: reach a team extraction tile,
## spend 1 AP, gone immediately," restricted to a non-player squad. The
## player's own squad (squad 0, `MissionState.player_squad_id`'s own
## default) has to hold the tile instead (EndTurnAction's own hold-check,
## test_end_turn_action.gd) — every fixture here is squad 1 on purpose,
## never squad 0.


func _make_unit(cell: Vector2i, squad_id: int = 1) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, squad_id)


func test_extract_illegal_off_the_extraction_cell() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	assert_false(ExtractAction.new(mission, unit).is_legal(state))


## taskblock-22 Pass A2: the player's own squad never gets the fast action
## at all, regardless of cell/AP — it's illegal even standing right on its
## own tile with a full AP pool.
func test_extract_illegal_for_the_player_squad_even_on_the_tile() -> void:
	var unit := _make_unit(Vector2i(4, 4), 0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	assert_false(
		ExtractAction.new(mission, unit).is_legal(state),
		"the player squad must hold, never use the fast action"
	)


func test_extract_illegal_without_enough_ap() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	unit.ap = 0
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	assert_false(ExtractAction.new(mission, unit).is_legal(state))


## taskblock-22 Pass A2: the fast path never checks mission objectives —
## those are a player-side concept (gather-then-extract); an enemy fleeing
## the board doesn't care whether the PLAYER'S OWN objective is done.
func test_extract_legal_at_the_zone_regardless_of_incomplete_objectives() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.objectives = [&"gather_minerals"]

	assert_true(ExtractAction.new(mission, unit).is_legal(state))


func test_extract_spends_its_ap_cost() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	var starting_ap: int = unit.ap

	ExtractAction.new(mission, unit).apply(state)

	assert_eq(unit.ap, starting_ap - ExtractAction.AP_COST)


## taskblock-22 Pass A1: a lone non-player unit extracting is, by
## definition, its own squad's WHOLE remaining squad — so this still ends
## up banking the haul, same observable outcome as before this pass, just
## reached through `MissionState.extract_unit()`'s own whole-squad check
## instead of a direct, unconditional `mission.extract()` call.
func test_extract_removes_the_unit_and_marks_it_extracted() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	ExtractAction.new(mission, unit).apply(state)

	assert_false(unit.alive)
	assert_true(unit.extracted)
	assert_eq(state.grid.get_occupant_id(unit.cell), -1)


func test_extract_emits_an_extract_event() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	ExtractAction.new(mission, unit).apply(state)

	assert_eq(sink.events_of_kind(&"extract").size(), 1)


## taskblock-21 Pass D2: "team-coded cells win when this unit's own squad
## has any authored." A tile in `team_extraction_cells` legal, the SAME
## cell absent from the old flat `extraction_cells` field entirely —
## proves the team-coded lookup is really consulted first, not just
## merged in.
func test_extract_uses_team_coded_cells_when_present_for_this_squad() -> void:
	var unit := _make_unit(Vector2i(1, 1))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.team_extraction_cells = {1: [Vector2i(1, 1)]}

	assert_true(ExtractAction.new(mission, unit).is_legal(state))


## The flat `extraction_cells` field stays the fallback for a squad with no
## team-coded entry of its own — a bout mission whose caller only populated
## the OTHER squad's tiles must never fall through to a stray leftover
## zone for this one.
func test_extract_falls_back_to_extraction_cells_when_this_squads_own_entry_is_absent() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.team_extraction_cells = {0: [Vector2i(0, 0)]}  # squad 0 only, this unit is squad 1

	assert_true(ExtractAction.new(mission, unit).is_legal(state))


func test_extract_on_a_preview_never_removes_the_real_unit() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	var preview: CombatState = state.dup()
	var previewed_unit: Unit = preview.find_unit(unit.id)
	ExtractAction.new(mission, previewed_unit).apply(preview)

	assert_true(unit.alive, "a preview must never actually extract the real unit")
	assert_false(unit.extracted)
