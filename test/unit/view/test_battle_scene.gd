extends GutTest

## Phase 12.1 acceptance (PLAN.md): a seeded battle draws, and every unit's
## visible geometry matches its `volume` boxes exactly. Phase 12.2:
## TacticsController is wired against the real camera/board, end to end.


func test_new_battle_spawns_a_board_and_one_unit_view_per_unit() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_not_null(scene.combat_state)
	assert_eq(scene.unit_views.size(), scene.combat_state.units.size())
	for view: HitVolumeView in scene.unit_views:
		assert_true(view.get_child_count() > 0, "every seeded unit must render at least one box")


## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." battle_scene.gd used to register only a UISink; a human
## session showed a log on screen and wrote nothing to disk.
func test_new_battle_wires_both_a_ui_sink_and_a_file_sink() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_not_null(scene.log_sink)
	assert_not_null(scene.file_sink)
	assert_true(FileAccess.file_exists(scene.file_sink.path), "the log must actually hit disk")
	scene.file_sink.close()


## docs/09 taskblock03 Pass B2: a session must be replayable from its own
## log file — the seed has to actually be in it, not just known to the
## process that generated it.
func test_new_battle_logs_the_seed_at_session_start_to_both_sinks() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_true(scene.log_sink.lines.size() > 0)
	assert_true(
		scene.log_sink.lines[0].contains("session_start"),
		"the very first line must be the session header"
	)
	assert_true(scene.log_sink.lines[0].contains(str(BattleScene.DEFAULT_SEED)))

	var file := FileAccess.open(scene.file_sink.path, FileAccess.READ)
	var first_line: String = file.get_line()
	file.close()
	scene.file_sink.close()

	assert_true(first_line.contains("session_start"))
	assert_true(first_line.contains(str(BattleScene.DEFAULT_SEED)))
	assert_eq(
		first_line, scene.log_sink.lines[0], "the same event, not two independently-built ones"
	)


func test_new_battle_is_deterministic_from_the_same_seed() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	scene.new_battle(42)
	var ids_a: Array[StringName] = []
	for unit: Unit in scene.combat_state.units:
		for part: Part in unit.shell.all_parts():
			ids_a.append(part.id)

	scene.new_battle(42)
	var ids_b: Array[StringName] = []
	for unit: Unit in scene.combat_state.units:
		for part: Part in unit.shell.all_parts():
			ids_b.append(part.id)

	assert_eq(ids_a, ids_b)


func test_calling_new_battle_again_does_not_leak_the_previous_units_views() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	var unit_count: int = scene.combat_state.units.size()
	scene.new_battle(999)

	assert_eq(scene.unit_views.size(), scene.combat_state.units.size())
	# world_environment + directional_light + camera_rig + board_view + tactics +
	# ui CanvasLayer + aim_view + resolution_player + stat_panel + inventory_panel +
	# weapon_panel + combat_readout_panel + queue_panel + action_bar +
	# controls_overlay + one HitVolumeView per unit.
	assert_eq(scene.get_child_count(), 15 + scene.combat_state.units.size())
	assert_eq(scene.combat_state.units.size(), unit_count, "the seeded roster size is stable")


func test_every_rendered_mesh_matches_a_living_boxs_placement_exactly() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	for i in range(scene.combat_state.units.size()):
		var unit: Unit = scene.combat_state.units[i]
		var view: HitVolumeView = scene.unit_views[i]
		var placements: Array[BoxPlacement] = UnitGeometry.placements(unit)

		# +2: HitVolumeView's own team marker (docs/10) at child 0 and facing
		# wedge (docs/10 taskblock02 F3) at child 1, ahead of the part meshes.
		assert_eq(view.get_child_count(), placements.size() + 2)
		for j in range(placements.size()):
			var mesh_instance: MeshInstance3D = view.get_child(j + 2)
			var expected: Transform3D = placements[j].transform.translated_local(
				placements[j].box.center
			)
			assert_eq(mesh_instance.transform, expected)


## runNotes.md: "the red unit may be spawning in a non-navigable space" —
## `_seed_battle` used to hardcode Vector2i(2,2)/(9,7) regardless of what
## MapGen actually carved; it must place both squads on the grid's own
## real SPAWN_A/SPAWN_B cells instead, across many seeds, not just the
## default one.
func test_seeded_units_always_land_on_navigable_terrain_across_many_seeds() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	for seed_value in range(1, 30):
		scene.new_battle(seed_value)
		for unit: Unit in scene.combat_state.units:
			assert_ne(
				scene.combat_state.grid.get_terrain(unit.cell),
				Enums.TerrainType.WALL,
				"seed %d must not spawn a unit on a wall" % seed_value
			)


func test_seeded_units_spawn_on_the_grids_own_spawn_a_and_spawn_b_cells() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	scene.new_battle(7)

	var terrains: Array[int] = []
	for unit: Unit in scene.combat_state.units:
		terrains.append(scene.combat_state.grid.get_terrain(unit.cell))

	assert_true(terrains.has(Enums.TerrainType.SPAWN_A))
	assert_true(terrains.has(Enums.TerrainType.SPAWN_B))


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

	var view: HitVolumeView = scene.unit_views[scene.combat_state.units.find(current)]
	var expected: Array[BoxPlacement] = UnitGeometry.placements(current)
	# +2: team marker (docs/10) at child 0, facing wedge (F3) at child 1.
	assert_eq(
		view.get_child_count(), expected.size() + 2, "the view must have redrawn at the new cell"
	)
	for i in range(expected.size()):
		var mesh_instance: MeshInstance3D = view.get_child(i + 2)
		assert_eq(
			mesh_instance.transform, expected[i].transform.translated_local(expected[i].box.center)
		)
