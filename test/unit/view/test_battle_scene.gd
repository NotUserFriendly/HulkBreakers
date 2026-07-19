extends GutTest

## Phase 12.1 acceptance (PLAN.md): a seeded battle draws, and every unit's
## visible geometry matches its `volume` boxes exactly. Phase 12.2:
## TacticsController is wired against the real camera/board, end to end.
##
## taskblock-15 Pass A: BattleScene now only builds the world (board,
## camera, unit_views, file_sink) and hosts a swappable overlay —
## everything TacticsController-shaped (`tactics`, `action_bar`,
## `turn_controls_column`, `new_battle_button`, `log_sink`, ...) moved into
## `SquadControlOverlay`, `_ready()`'s own default overlay. `_overlay()`
## below is the one place every test below reaches through it.


func _overlay(scene: BattleScene) -> SquadControlOverlay:
	return scene.overlay as SquadControlOverlay


## taskblock-17 Pass A: the exact regression, pinned directly against the
## constant that caused it — `GRID_WIDTH`/`GRID_HEIGHT` used to be 12x10,
## well under `MapGen.MIN_LEAF_SIZE * 2` (24) on both axes, so
## `_split_and_carve` could never split it: every real battle was
## silently one room, no hallways, from the moment taskblock-16 raised
## `MIN_ROOM_SIZE` without this file's own size ever being revisited. If
## a future `MIN_ROOM_SIZE` change raises the threshold again, this fails
## immediately instead of silently shipping a one-room board.
func test_grid_size_clears_the_map_gen_split_threshold() -> void:
	assert_true(
		BattleScene.GRID_WIDTH >= MapGen.MIN_LEAF_SIZE * 2,
		"GRID_WIDTH must clear MapGen.MIN_LEAF_SIZE * 2 or the board never splits into rooms"
	)
	assert_true(
		BattleScene.GRID_HEIGHT >= MapGen.MIN_LEAF_SIZE * 2,
		"GRID_HEIGHT must clear MapGen.MIN_LEAF_SIZE * 2 or the board never splits into rooms"
	)


func test_new_battle_spawns_a_board_and_one_unit_view_per_unit() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_not_null(scene.combat_state)
	assert_eq(scene.unit_views.size(), scene.combat_state.units.size())
	for view: HitVolumeView in scene.unit_views:
		assert_true(view.get_child_count() > 0, "every seeded unit must render at least one box")


## taskblock-19 Pass I2: "something on turn advance is blocking the main
## thread" — a full HitVolumeView.refresh() (tear down + rebuild every
## child mesh) for EVERY unit on EVERY turn, even the ones a turn never
## touched, was real, unnecessary work. Passing a specific id set must
## rebuild ONLY those views — proven by reading the real child nodes
## back: an untouched view's own children must be the SAME instances
## before and after, never freed and recreated.
func test_refresh_unit_views_with_ids_only_rebuilds_those_views() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var touched_id: int = scene.combat_state.units[0].id
	var untouched_view: HitVolumeView = scene.unit_views[1]
	var touched_view: HitVolumeView = scene.unit_views[0]
	var untouched_children_before: Array[Node] = untouched_view.get_children()
	var touched_children_before: Array[Node] = touched_view.get_children()

	scene.refresh_unit_views([touched_id])

	assert_eq(
		untouched_view.get_children(),
		untouched_children_before,
		"an untouched view's own children must not be rebuilt"
	)
	assert_ne(
		touched_view.get_children(), touched_children_before, "the named view must actually rebuild"
	)


func test_refresh_unit_views_with_null_still_rebuilds_every_view() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var children_before: Array = []
	for view: HitVolumeView in scene.unit_views:
		children_before.append(view.get_children())

	scene.refresh_unit_views()

	for i in range(scene.unit_views.size()):
		assert_ne(
			scene.unit_views[i].get_children(),
			children_before[i],
			"the default (null) must still rebuild everyone, unchanged from before this pass"
		)


## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." battle_scene.gd used to register only a UISink; a human
## session showed a log on screen and wrote nothing to disk.
func test_new_battle_wires_both_a_ui_sink_and_a_file_sink() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_not_null(_overlay(scene).log_sink)
	assert_not_null(scene.file_sink)
	assert_true(FileAccess.file_exists(scene.file_sink.path), "the log must actually hit disk")
	scene.file_sink.close()


## docs/09 taskblock03 Pass B2: a session must be replayable from its own
## log file — the seed has to actually be in it, not just known to the
## process that generated it.
func test_new_battle_logs_the_seed_at_session_start_to_both_sinks() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var log_sink: UISink = _overlay(scene).log_sink

	assert_true(log_sink.lines.size() > 0)
	assert_true(
		log_sink.lines[0].contains("session_start"),
		"the very first line must be the session header"
	)
	assert_true(log_sink.lines[0].contains(str(BattleScene.DEFAULT_SEED)))

	var file := FileAccess.open(scene.file_sink.path, FileAccess.READ)
	var first_line: String = file.get_line()
	file.close()
	scene.file_sink.close()

	assert_true(first_line.contains("session_start"))
	assert_true(first_line.contains(str(BattleScene.DEFAULT_SEED)))
	assert_eq(first_line, log_sink.lines[0], "the same event, not two independently-built ones")


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
	# world_environment + directional_light + camera_rig + board_view +
	# the overlay Node (SquadControlOverlay itself, everything ELSE it
	# owns lives under that one child) + one HitVolumeView per unit.
	assert_eq(scene.get_child_count(), 5 + scene.combat_state.units.size())
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
			var part: Part = placements[j].part
			# taskblock-10 Pass A: a part rendered as a whole-part primitive
			# (no mesh_scene, render_primitive != BOX — e.g. `goo_barrel`'s
			# own CYLINDER; taskblock-17 Pass E retired the plate that used
			# to be this file's own example, `cylinder_plate_segment`, in
			# favor of real multi-box geometry) draws at the part's own
			# composed transform SCALED by render_scale, never the box-local
			# center offset a literal hitbox box uses (docs/09: "the mesh
			# must never affect resolution" — the two are allowed to
			# diverge).
			var expected: Transform3D
			if part.mesh_scene == null and part.render_primitive != &"BOX":
				expected = placements[j].transform.scaled_local(part.render_scale)
			else:
				expected = placements[j].transform.translated_local(placements[j].box.center)
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
	var tactics: TacticsController = _overlay(scene).tactics

	assert_eq(tactics.selection.state, scene.combat_state)
	assert_eq(tactics.board_view, scene.board_view)
	assert_eq(tactics.camera, scene.camera_rig.camera())
	assert_not_null(tactics.camera, "camera_rig must have already built its Camera3D")


func test_clicking_and_ending_a_turn_through_the_real_scene_moves_the_unit_and_redraws_it() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var tactics: TacticsController = _overlay(scene).tactics

	var current: Unit = scene.combat_state.current_unit()
	var start_cell: Vector2i = current.cell
	tactics.click_cell(start_cell)
	assert_eq(tactics.selection.selected_unit, current)

	var reachable: Array[Vector2i] = tactics.selection.reachable_cells()
	var target_cell: Vector2i = start_cell
	for cell: Vector2i in reachable:
		if cell != start_cell:
			target_cell = cell
			break
	assert_ne(target_cell, start_cell, "the seeded unit must have somewhere to move")

	tactics.click_cell(target_cell)
	tactics.end_turn()

	assert_eq(current.cell, target_cell, "resolution must have actually moved the real unit")

	var view: HitVolumeView = scene.unit_views[scene.combat_state.units.find(current)]
	var expected: Array[BoxPlacement] = UnitGeometry.placements(current)
	# +2: team marker (docs/10) at child 0, facing wedge (F3) at child 1.
	assert_eq(
		view.get_child_count(), expected.size() + 2, "the view must have redrawn at the new cell"
	)
	for i in range(expected.size()):
		var mesh_instance: MeshInstance3D = view.get_child(i + 2)
		var part: Part = expected[i].part
		# Same primitive-vs-box distinction as
		# test_every_rendered_mesh_matches_a_living_boxs_placement_exactly.
		var expected_transform: Transform3D
		if part.mesh_scene == null and part.render_primitive != &"BOX":
			expected_transform = expected[i].transform.scaled_local(part.render_scale)
		else:
			expected_transform = expected[i].transform.translated_local(expected[i].box.center)
		assert_eq(mesh_instance.transform, expected_transform)


## taskblock-08 E1/TESTS: "New Battle is not among the turn controls" —
## E3's whole point, checked directly against the real built scene rather
## than just trusting the layout code reads that way.
func test_new_battle_is_not_among_the_turn_controls() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var overlay: SquadControlOverlay = _overlay(scene)

	for child: Node in overlay.turn_controls_column.get_children():
		if child is Button:
			assert_ne((child as Button).text, "New Battle")
	assert_not_null(overlay.new_battle_button, "it must still exist somewhere — just not there")


## taskblock-08 E1: "action bar on the LEFT... AP and MP pips render on
## TOP of the action bar" — the pip rows sit above the action bar's own
## row, both inside the one left-hand column, never mixed into the
## turn-control column.
func test_the_action_bars_own_row_is_the_last_child_of_the_action_column() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var action_column: VBoxContainer = _overlay(scene).action_column

	assert_eq(action_column.get_child_count(), 2, "pips above, the action row below")
	var last: Node = action_column.get_child(action_column.get_child_count() - 1)
	assert_eq(
		(last as Container).get_child_count(),
		ActionBar.SLOT_COUNT,
		"the LAST child must be the 10-box action row, the pips sit above it"
	)


func test_the_turn_control_buttons_are_sized_to_their_own_text_not_stretched() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var turn_controls_column: VBoxContainer = _overlay(scene).turn_controls_column

	for child: Node in turn_controls_column.get_children():
		var button := child as Button
		assert_not_null(button)
		assert_eq(button.size_flags_horizontal, Control.SIZE_SHRINK_END)
