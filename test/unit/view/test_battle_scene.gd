extends GutTest

## Phase 12.1 acceptance (PLAN.md): a seeded battle draws, and every unit's
## visible geometry matches its `volume` boxes exactly. Phase 12.2:
## TacticsController is wired against the real camera/board, end to end.


func test_new_battle_spawns_a_board_and_one_unit_view_per_unit() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_not_null(scene.combat_state)
	assert_eq(scene.unit_views.size(), scene.combat_state.units.size())
	for view: UnitView in scene.unit_views:
		assert_true(view.get_child_count() > 0, "every seeded unit must render at least one box")


func test_new_battle_is_deterministic_from_the_same_seed() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	scene.new_battle(42)
	var ids_a: Array[StringName] = []
	for unit: Unit in scene.combat_state.units:
		for part: Part in unit.frame.all_parts():
			ids_a.append(part.id)

	scene.new_battle(42)
	var ids_b: Array[StringName] = []
	for unit: Unit in scene.combat_state.units:
		for part: Part in unit.frame.all_parts():
			ids_b.append(part.id)

	assert_eq(ids_a, ids_b)


func test_calling_new_battle_again_does_not_leak_the_previous_units_views() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	var unit_count: int = scene.combat_state.units.size()
	scene.new_battle(999)

	assert_eq(scene.unit_views.size(), scene.combat_state.units.size())
	# world_environment + camera_rig + board_view + tactics + ui CanvasLayer +
	# aim_view + resolution_player + one UnitView per unit.
	assert_eq(scene.get_child_count(), 7 + scene.combat_state.units.size())
	assert_eq(scene.combat_state.units.size(), unit_count, "the seeded roster size is stable")


func test_every_rendered_mesh_matches_a_living_boxs_placement_exactly() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	for i in range(scene.combat_state.units.size()):
		var unit: Unit = scene.combat_state.units[i]
		var view: UnitView = scene.unit_views[i]
		var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

		assert_eq(view.get_child_count(), placements.size())
		for j in range(placements.size()):
			var mesh_instance: MeshInstance3D = view.get_child(j)
			var expected: Transform3D = placements[j].transform.translated_local(
				placements[j].box.center
			)
			assert_eq(mesh_instance.transform, expected)


func test_tactics_is_wired_to_the_real_camera_and_board() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_eq(scene.tactics.selection.state, scene.combat_state)
	assert_eq(scene.tactics.board_view, scene.board_view)
	assert_eq(scene.tactics.camera, scene.camera_rig.camera())
	assert_not_null(scene.tactics.camera, "camera_rig must have already built its Camera3D")


func test_clicking_and_ending_a_turn_through_the_real_scene_moves_the_unit_and_redraws_it() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	var current: Unit = scene.combat_state.current_unit()
	var start_cell: Vector2i = current.cell
	scene.tactics.click_cell(start_cell)
	assert_eq(scene.tactics.selection.selected_unit, current)

	var reachable: Array[Vector2i] = scene.tactics.selection.reachable_cells()
	var target_cell: Vector2i = start_cell
	for cell: Vector2i in reachable:
		if cell != start_cell:
			target_cell = cell
			break
	assert_ne(target_cell, start_cell, "the seeded unit must have somewhere to move")

	scene.tactics.click_cell(target_cell)
	scene.tactics.end_turn()

	assert_eq(current.cell, target_cell, "resolution must have actually moved the real unit")

	var view: UnitView = scene.unit_views[scene.combat_state.units.find(current)]
	var expected: Array[BoxPlacement] = UnitGeometry.placements(current)
	assert_eq(view.get_child_count(), expected.size(), "the view must have redrawn at the new cell")
	for i in range(expected.size()):
		var mesh_instance: MeshInstance3D = view.get_child(i)
		assert_eq(mesh_instance.transform, expected[i].transform.translated_local(expected[i].box.center))
