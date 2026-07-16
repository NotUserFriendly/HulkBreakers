extends GutTest

## docs/07: the mission loop's own gather verb — a unit standing on a
## resource node consumes it, not a test calling MissionState.gather_resource()
## as a stand-in for the player.


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func _make_mission(state: CombatState) -> MissionState:
	return MissionState.new(RunState.new(), state)


func test_gather_consumes_the_node_and_banks_the_resource() -> void:
	var unit := _make_unit(Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := _make_mission(state)
	mission.resource_nodes[Vector2i(2, 2)] = {resource = &"minerals", amount = 20}

	var action := GatherAction.new(mission, unit, Vector2i(2, 2))
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_eq(mission.gathered_resources.get(&"minerals"), 20)
	assert_false(
		mission.resource_nodes.has(Vector2i(2, 2)), "the node must be consumed, not reusable"
	)
	assert_eq(unit.ap, unit.max_ap - GatherAction.DEFAULT_AP_COST)


func test_gather_completes_the_tied_objective() -> void:
	var unit := _make_unit(Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := _make_mission(state)
	mission.objectives = [&"gather_minerals"]
	mission.resource_nodes[Vector2i(2, 2)] = {
		resource = &"minerals", amount = 20, objective = &"gather_minerals"
	}

	GatherAction.new(mission, unit, Vector2i(2, 2)).apply(state)

	assert_eq(mission.completed_objectives, [&"gather_minerals"])


func test_gather_illegal_off_the_node_cell() -> void:
	var unit := _make_unit(Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := _make_mission(state)
	mission.resource_nodes[Vector2i(3, 3)] = {resource = &"minerals", amount = 20}

	assert_false(GatherAction.new(mission, unit, Vector2i(3, 3)).is_legal(state))


func test_gather_illegal_without_enough_ap() -> void:
	var unit := _make_unit(Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := _make_mission(state)
	mission.resource_nodes[Vector2i(2, 2)] = {resource = &"minerals", amount = 20}
	unit.ap = 0

	assert_false(GatherAction.new(mission, unit, Vector2i(2, 2)).is_legal(state))


func test_gather_emits_a_gather_event() -> void:
	var unit := _make_unit(Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var mission := _make_mission(state)
	mission.resource_nodes[Vector2i(2, 2)] = {resource = &"minerals", amount = 20}

	GatherAction.new(mission, unit, Vector2i(2, 2)).apply(state)

	var gathers: Array[LogEvent] = sink.events_of_kind(&"gather")
	assert_eq(gathers.size(), 1)
	assert_eq(gathers[0].data.get("resource"), &"minerals")
	assert_eq(gathers[0].data.get("amount"), 20)


func test_gather_on_a_preview_spends_ap_but_never_touches_the_mission() -> void:
	var unit := _make_unit(Vector2i(2, 2))
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := _make_mission(state)
	mission.resource_nodes[Vector2i(2, 2)] = {resource = &"minerals", amount = 20}

	var preview: CombatState = state.dup()
	var previewed_unit: Unit = preview.find_unit(unit.id)
	GatherAction.new(mission, previewed_unit, Vector2i(2, 2)).apply(preview)

	assert_eq(previewed_unit.ap, unit.max_ap - GatherAction.DEFAULT_AP_COST)
	assert_true(
		mission.resource_nodes.has(Vector2i(2, 2)), "a preview must never consume the real node"
	)
	assert_eq(mission.gathered_resources, {})
