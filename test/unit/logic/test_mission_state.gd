extends GutTest

## docs/07/00: extract banks loot; terminate loses it. Matrices are never
## lost on either path.


func _make_unit(cell: Vector2i, matrix: Matrix) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	return Unit.new(matrix, Frame.new(root), cell)


func test_extract_banks_gathered_resources_and_items() -> void:
	var run_state := RunState.new()
	var combat_state := CombatState.new(Grid.new(5, 5))
	var mission := MissionState.new(run_state, combat_state)

	mission.gather_resource(&"minerals", 10)
	var loot_part := Part.new()
	loot_part.id = &"salvaged_plate"
	loot_part.hp = 3
	loot_part.max_hp = 3
	mission.gathered_items.append(loot_part)

	mission.extract()

	assert_eq(run_state.resource_count(&"minerals"), 10)
	assert_true(run_state.stash.has(loot_part))
	assert_eq(mission.gathered_resources, {})
	assert_eq(mission.gathered_items, [] as Array[Part])


func test_terminate_discards_gathered_loot() -> void:
	var run_state := RunState.new()
	var combat_state := CombatState.new(Grid.new(5, 5))
	var mission := MissionState.new(run_state, combat_state)

	mission.gather_resource(&"minerals", 10)
	var loot_part := Part.new()
	loot_part.id = &"salvaged_plate"
	mission.gathered_items.append(loot_part)

	mission.terminate()

	assert_eq(run_state.resource_count(&"minerals"), 0)
	assert_false(run_state.stash.has(loot_part))


func test_extract_returns_every_matrix_to_the_roster() -> void:
	var run_state := RunState.new()
	var alice := Matrix.new()
	alice.id = &"alice"
	var bob := Matrix.new()
	bob.id = &"bob"
	var unit_a := _make_unit(Vector2i(0, 0), alice)
	var unit_b := _make_unit(Vector2i(1, 0), bob)
	var combat_state := CombatState.new(Grid.new(5, 5), [unit_a, unit_b])
	var mission := MissionState.new(run_state, combat_state)

	mission.extract()

	assert_true(run_state.roster.has(alice))
	assert_true(run_state.roster.has(bob))


func test_terminate_still_returns_every_matrix_even_though_loot_is_lost() -> void:
	var run_state := RunState.new()
	var alice := Matrix.new()
	alice.id = &"alice"
	var unit_a := _make_unit(Vector2i(0, 0), alice)
	var combat_state := CombatState.new(Grid.new(5, 5), [unit_a])
	var mission := MissionState.new(run_state, combat_state)
	mission.gather_resource(&"minerals", 999)

	mission.terminate()

	assert_true(run_state.roster.has(alice), "matrices are never lost, on any path")
	assert_eq(run_state.resource_count(&"minerals"), 0)


func test_a_carried_matrix_that_was_never_reimplanted_still_comes_home() -> void:
	var run_state := RunState.new()
	var carrier_matrix := Matrix.new()
	carrier_matrix.id = &"carrier"
	var picked_up := Matrix.new()
	picked_up.id = &"picked_up_ally"
	var unit := _make_unit(Vector2i(0, 0), carrier_matrix)
	unit.held_matrix = picked_up
	var combat_state := CombatState.new(Grid.new(5, 5), [unit])
	var mission := MissionState.new(run_state, combat_state)

	mission.extract()

	assert_true(run_state.roster.has(carrier_matrix))
	assert_true(run_state.roster.has(picked_up))


func test_complete_objective_only_tracks_known_ids_once() -> void:
	var run_state := RunState.new()
	var combat_state := CombatState.new(Grid.new(5, 5))
	var mission := MissionState.new(run_state, combat_state)
	mission.objectives = [&"gather_minerals"]

	mission.complete_objective(&"gather_minerals")
	mission.complete_objective(&"gather_minerals")  # idempotent
	mission.complete_objective(&"unknown_objective")  # not in this mission's list

	assert_eq(mission.completed_objectives, [&"gather_minerals"])
