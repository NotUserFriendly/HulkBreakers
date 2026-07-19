extends GutTest

## docs/07: extraction is reached by a unit at the zone, not called directly
## by a test standing in for the player.


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func test_extract_illegal_off_the_extraction_cell() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]

	assert_false(ExtractAction.new(mission, unit).is_legal(state))


func test_extract_illegal_with_an_incomplete_objective() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.objectives = [&"gather_minerals"]

	assert_false(ExtractAction.new(mission, unit).is_legal(state))


func test_extract_legal_once_at_the_zone_with_every_objective_complete() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.objectives = [&"gather_minerals"]
	mission.complete_objective(&"gather_minerals")

	assert_true(ExtractAction.new(mission, unit).is_legal(state))


func test_extract_banks_the_haul_and_returns_the_matrix() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var run_state := RunState.new()
	var mission := MissionState.new(run_state, state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.gather_resource(&"minerals", 15)

	ExtractAction.new(mission, unit).apply(state)

	assert_eq(run_state.resource_count(&"minerals"), 15)
	assert_true(run_state.roster.has(unit.matrix))


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
	mission.team_extraction_cells = {0: [Vector2i(1, 1)]}

	assert_true(ExtractAction.new(mission, unit).is_legal(state))


## The flat `extraction_cells` field stays the fallback for a squad with no
## team-coded entry of its own — a bout mission whose caller only populated
## the OTHER squad's tiles must never fall through to a stray leftover
## squad-0 zone for this one.
func test_extract_falls_back_to_extraction_cells_when_this_squads_own_entry_is_absent() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.team_extraction_cells = {1: [Vector2i(0, 0)]}  # squad 1 only, this unit is squad 0

	assert_true(ExtractAction.new(mission, unit).is_legal(state))


func test_extract_on_a_preview_never_ends_the_real_mission() -> void:
	var unit := _make_unit(Vector2i(4, 4))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var run_state := RunState.new()
	var mission := MissionState.new(run_state, state)
	mission.extraction_cells = [Vector2i(4, 4)]
	mission.gather_resource(&"minerals", 15)

	var preview: CombatState = state.dup()
	var previewed_unit: Unit = preview.find_unit(unit.id)
	ExtractAction.new(mission, previewed_unit).apply(preview)

	assert_eq(run_state.resource_count(&"minerals"), 0, "a preview must never actually extract")
	assert_eq(mission.gathered_resources.get(&"minerals"), 15)
