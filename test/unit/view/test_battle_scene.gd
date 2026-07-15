extends GutTest

## Phase 12.1 acceptance (PLAN.md): a seeded battle draws, and every unit's
## visible geometry matches its `volume` boxes exactly.


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
	# world_environment + camera_rig + board_view + ui CanvasLayer + one UnitView per unit.
	assert_eq(scene.get_child_count(), 4 + scene.combat_state.units.size())
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
