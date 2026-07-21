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


## taskblock-30: `bout_injector` is owned by `BattleScene` itself now (not
## whichever overlay happens to be installed), so it survives a spectator
## <-> player overlay swap — rebuilt against whatever `combat_state`
## `load_battle()` most recently installed, same lifecycle `file_sink`
## already has.
func test_load_battle_constructs_a_bout_injector_against_the_live_state() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)

	assert_not_null(scene.bout_injector)
	assert_eq(scene.bout_injector.state, scene.combat_state)


func test_reloading_the_battle_rebuilds_the_bout_injector_against_the_new_state() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var first_injector: BoutInjector = scene.bout_injector

	scene.new_battle(999)

	assert_ne(
		scene.bout_injector, first_injector, "must rebuild, not keep pointing at a stale state"
	)
	assert_eq(scene.bout_injector.state, scene.combat_state)


## taskblock-22 Pass A3: "team-coded extraction tiles, drawn in their
## team's color" — load_battle must actually thread mission.
## team_extraction_cells through to board_view.build(), not just build
## the ground/blockers/grid-lines it already did before this pass.
func test_load_battle_draws_the_missions_own_extraction_tiles() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var before_count: int = scene.board_view._static.get_child_count()
	var mission := MissionState.new(RunState.new(), scene.combat_state)
	mission.objectives = []
	mission.team_extraction_cells = {0: [Vector2i(0, 0)], 1: [Vector2i(1, 1)]}

	scene.load_battle(scene.combat_state, mission)

	assert_eq(scene.board_view._static.get_child_count(), before_count + 2)


## taskblock-22 Pass E3: the action-bar task's own real, end-to-end path —
## a welder-equipped unit, real scrap gathered, the button pressed and a
## part chosen through the real popup handler, resolved through the
## normal queue (never a debug-style direct mutation).
func test_repair_button_queues_and_resolves_a_real_repair() -> void:
	var target := Part.new()
	target.id = &"leg"
	target.material = &"steel"
	target.hp = 5
	target.max_hp = 10

	var repair_battery := Part.new()
	repair_battery.id = &"tool_battery"
	repair_battery.hp = 3
	repair_battery.max_hp = 3
	repair_battery.battery_capacity = 6.0
	repair_battery.battery_power_out = 3.0
	repair_battery.battery_charge = 6.0
	repair_battery.tags = [&"POWER_SOURCE", &"BATTERY", &"TOOL_BATTERY"]

	var welder := Part.new()
	welder.id = &"welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.tags = [&"WELDER"]
	var battery_socket := Socket.new(&"TOOL_BATTERY")
	battery_socket.occupant = repair_battery
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

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(10, 10), [unit])
	state.assign_all_to_human()  # tb31 Pass B: no silent default to rely on
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.gather_resource(&"steel", 5)

	var scene := BattleScene.new()
	add_child_autofree(scene)
	scene.load_battle(state, mission)
	var overlay: SquadControlOverlay = _overlay(scene)
	overlay.tactics.selection.select(unit)

	overlay._on_repair_pressed()
	overlay._on_repair_menu_id_pressed(0, [target], RepairResolver.find_operable_welder(unit))
	state.resolve_turn(overlay.tactics.selection.current_queue())

	assert_eq(target.hp, 8, "5 hp + 3 (capped heal), resolved for real")
	assert_eq(mission.gathered_resources.get(&"steel", 0), 2, "5 scrap - 3 spent")


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


## taskblock-27 Pass D2: "no clear indication of whose turn it is." Must be
## correct from `load_battle()` itself, not just after the first
## `refresh_unit_views()` call post-turn.
func test_load_battle_marks_the_current_units_own_view_as_active() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var current: Unit = scene.combat_state.current_unit()

	for view: HitVolumeView in scene.unit_views:
		assert_eq(
			view._is_active_turn,
			view.unit == current,
			"exactly the current unit's own view must read active"
		)


## `refresh_unit_views()` must move the highlight as the turn advances,
## even for a view `affected_unit_ids` didn't otherwise touch.
func test_refresh_unit_views_moves_the_active_turn_highlight_as_the_turn_advances() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var first: Unit = scene.combat_state.current_unit()
	scene.combat_state.advance_turn()
	var second: Unit = scene.combat_state.current_unit()
	assert_ne(first, second, "sanity: advancing the turn actually changed who's current")

	scene.refresh_unit_views([])  # an empty touched-list -- no view's mesh needs rebuilding

	for view: HitVolumeView in scene.unit_views:
		assert_eq(view._is_active_turn, view.unit == second)


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


## taskblock-30 follow-up (supervisor report): "spawn unit doesn't create a
## visual model, even though inspect shows it." Root cause — `unit_views`
## is only ever built once, in `load_battle()`'s own loop; a unit added
## afterward (`BoutInjector.spawn_unit`, straight into `combat_state.
## units`) never gets a view at all. `sync_unit_views()` closes that gap.
func test_sync_unit_views_builds_a_view_for_a_unit_added_after_load_battle() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var before_count: int = scene.unit_views.size()
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var spawned := Unit.new(Matrix.new(), Shell.new(root), Vector2i(2, 2), 0)
	scene.combat_state.add_unit(spawned)
	assert_null(scene.find_unit_view(spawned.id), "sanity: no view exists yet for the new unit")

	scene.sync_unit_views()

	assert_eq(scene.unit_views.size(), before_count + 1)
	var view: HitVolumeView = scene.find_unit_view(spawned.id)
	assert_not_null(view)
	assert_true(view.get_child_count() > 0, "the new unit must actually render something")


func test_sync_unit_views_is_a_noop_when_every_unit_already_has_a_view() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var views_before: Array[HitVolumeView] = scene.unit_views.duplicate()

	scene.sync_unit_views()

	assert_eq(scene.unit_views, views_before, "must never rebuild or duplicate an existing view")


## taskblock-30 follow-up (supervisor report): "removing a unit doesn't
## visually do anything" — this was the ORIGINAL bug pinned against
## `kill` (renamed from `remove_unit` in a later follow-up; see
## test_bout_injector_kill.gd for its own matrix-ejection coverage).
## Closes the loop end to end: ejecting the matrix must actually flip what
## `HitVolumeView.is_downed()` reads, the one thing `refresh()` checks to
## pick the DOWN pose.
func test_killing_a_unit_through_the_debug_injector_flips_its_view_to_downed() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var target: Unit = scene.combat_state.units[0]
	var view: HitVolumeView = scene.find_unit_view(target.id)
	assert_false(view.is_downed(), "sanity: a fresh seeded unit is not downed")

	scene.bout_injector.kill(target)
	scene.refresh_unit_views()

	assert_true(view.is_downed())


## taskblock-30 follow-up (supervisor): "remove can be generalized to
## objects, covers, and things on tiles. Fully vanishing it." Distinct
## from `kill` above — this destroys the unit's own view ENTIRELY, no
## downed corpse left behind.
func test_remove_unit_view_destroys_the_view_and_drops_it_from_unit_views() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var target: Unit = scene.combat_state.units[0]
	var view: HitVolumeView = scene.find_unit_view(target.id)
	var before_count: int = scene.unit_views.size()

	scene.remove_unit_view(target)

	assert_eq(scene.unit_views.size(), before_count - 1)
	assert_false(view in scene.unit_views)
	assert_null(scene.find_unit_view(target.id))


## The whole point: a unit deliberately removed must never come back just
## because some LATER, unrelated debug verb's own `sync_unit_views()` pass
## runs — `CombatState.kill_unit` never deletes from `state.units` (by
## design), so without tracking, the very next sync would resurrect it.
func test_sync_unit_views_never_resurrects_a_deliberately_removed_unit() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var target: Unit = scene.combat_state.units[0]
	scene.remove_unit_view(target)
	assert_null(scene.find_unit_view(target.id), "sanity: removed")

	scene.sync_unit_views()

	assert_null(scene.find_unit_view(target.id), "sync must not bring it back")


## A fresh bout must never inherit a previous bout's own removed-unit ids
## (unit ids can repeat across separately-seeded CombatStates) — read the
## private tracking dict directly, the same convention this file's own
## `_is_active_turn` checks already use for private view/scene state.
func test_load_battle_resets_the_removed_unit_tracking() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	scene.remove_unit_view(scene.combat_state.units[0])
	assert_false(scene._removed_unit_ids.is_empty(), "sanity: something is tracked as removed")

	scene.new_battle(999)

	assert_true(scene._removed_unit_ids.is_empty(), "a fresh bout must not inherit stale removals")


## taskblock-30 follow-up (supervisor report): `board_view.build()` was
## only ever called once, at `load_battle()` — the exact same
## data-changed-but-nothing-redraws gap `sync_unit_views()` closed for
## units, unnoticed for `Grid.blockers`/`field_items`.
func test_sync_board_view_picks_up_a_blocker_placed_after_load_battle() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var before_count: int = scene.board_view._static.get_child_count()
	var scrap := Part.new()
	scrap.id = &"scrap_pile"
	scrap.hp = 4
	scrap.max_hp = 4
	scrap.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 0.5, 0.5))]
	scene.combat_state.grid.blockers[Vector2i(3, 3)] = scrap

	scene.sync_board_view()

	assert_gt(scene.board_view._static.get_child_count(), before_count)


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
	var log_sink: HierarchicalUiSink = _overlay(scene).log_sink

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


## taskblock-21 Pass C: "toggle assume-control of blue team <-> watch...
## no new control system — the overlay swap tb15 built, exposed as a
## toggle." Squad 0 is "blue"; squad 1 ("red") must never be touched by
## either direction of the toggle.
func test_toggle_blue_control_flips_squad_zero_and_swaps_the_overlay() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	scene.combat_state.set_squad_controller(1, Enums.SquadController.AI)
	var before: Enums.SquadController = scene.combat_state.controller_for(0)

	scene.toggle_blue_control()

	var after: Enums.SquadController = scene.combat_state.controller_for(0)
	assert_ne(after, before, "squad 0's own controller must flip")
	assert_eq(
		scene.combat_state.controller_for(1), Enums.SquadController.AI, "red is never touched"
	)
	if after == Enums.SquadController.HUMAN:
		assert_true(scene.overlay is SquadControlOverlay)
	else:
		assert_true(scene.overlay is SpectatorOverlay)


func test_toggle_blue_control_round_trips() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	var original: Enums.SquadController = scene.combat_state.controller_for(0)

	scene.toggle_blue_control()
	scene.toggle_blue_control()

	assert_eq(scene.combat_state.controller_for(0), original)


## The bout menu's own checkbox: unchecked keeps today's behavior
## (SpectatorOverlay, both squads AI); checked lands directly on
## SquadControlOverlay with squad 0 flipped to HUMAN, squad 1 left AI.
func test_generate_bout_overlay_assume_control_checkbox_lands_on_squad_control() -> void:
	var scene := BattleScene.new()
	add_child_autofree(scene)
	scene.set_overlay(GenerateBoutOverlay.new())
	var menu: GenerateBoutOverlay = scene.overlay as GenerateBoutOverlay
	menu._assume_control_checkbox.button_pressed = true

	menu._on_start_bout_pressed()

	assert_true(scene.overlay is SquadControlOverlay)
	assert_eq(scene.combat_state.controller_for(0), Enums.SquadController.HUMAN)
	assert_eq(scene.combat_state.controller_for(1), Enums.SquadController.AI)
