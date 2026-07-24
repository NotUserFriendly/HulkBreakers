extends GutTest

## docs/10: BoardView is pure presentation — a ground plane sized to the
## grid, plus one box per blocker box, plus a separate TACTICS overlay
## (reachable highlight / ghost paths). It never mutates Grid.


func test_build_spawns_a_ground_plane_and_one_box_per_blocker() -> void:
	var grid := Grid.new(4, 3)
	var rack := Part.new()
	rack.id = &"rack"
	rack.hp = 5
	rack.max_hp = 5
	rack.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.blockers[Vector2i(1, 1)] = rack

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	# +1: the grid-line mesh (docs/10 taskblock02 G3), always present.
	assert_eq(view._static.get_child_count(), 3, "ground plane + grid lines + the one blocker box")


## taskblock-23 Pass E2: the inspect panel's isolate camera needs a real
## board tile under the model instead of it floating in a void — the
## ground plane and grid lines both carry BoardView.FLOOR_LAYER, on top
## of (never instead of) whatever layer they already render on for the
## real board's own main camera.
func test_ground_and_grid_lines_carry_the_floor_layer() -> void:
	var grid := Grid.new(4, 3)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var ground: MeshInstance3D = view._static.get_child(0)
	var grid_lines: MeshInstance3D = view._static.get_child(1)
	assert_true(ground.get_layer_mask_value(BoardView.FLOOR_LAYER))
	assert_true(grid_lines.get_layer_mask_value(BoardView.FLOOR_LAYER))
	assert_true(ground.get_layer_mask_value(1), "still renders on the default layer too")


## taskblock-37 Pass E: an all-level-0 grid must still terrace to a flat,
## world-Y-0 ground — the inertness guard tb36/tb37's own regression
## posture always uses, now proven against the real built mesh's own AABB
## (docs/10 rule 2: read the real node back) instead of trusted by
## construction.
func test_build_terrain_is_flat_when_no_level_is_set() -> void:
	var grid := Grid.new(4, 3)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var ground: MeshInstance3D = view._static.get_child(0)
	var aabb: AABB = ground.mesh.get_aabb()
	assert_almost_eq(aabb.position.y, 0.0, 0.0001)
	assert_almost_eq(aabb.size.y, 0.0, 0.0001, "no cell differs from any other -- no riser at all")


## taskblock-37 Pass E: the ground used to be one flat `PlaneMesh` with no
## way to show a cell's own real elevation at all — a raised cell now
## genuinely raises its own patch of terrain, read back from the built
## mesh's own AABB rather than trusted from the source.
func test_build_terrain_reflects_a_raised_cells_own_height() -> void:
	var grid := Grid.new(4, 3)
	grid.set_level(Vector2i(2, 1), 2)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var ground: MeshInstance3D = view._static.get_child(0)
	var aabb: AABB = ground.mesh.get_aabb()
	assert_almost_eq(aabb.position.y, 0.0, 0.0001, "the rest of the grid stays at ground level")
	assert_almost_eq(
		aabb.end.y,
		2.0 * UnitGeometry.LEVEL_HEIGHT,
		0.0001,
		"the raised cell's own top face must reach its real height"
	)


## A ground overlay marker (extraction tile, wall/void indicator,
## reachable highlight, ghost path, field-item marker — all built through
## `_marker`) must sit on the cell's OWN real ground, not float below (or
## get buried inside) the terraced terrain above.
func test_marker_sits_on_a_raised_cells_own_real_height() -> void:
	var grid := Grid.new(4, 3)
	grid.set_level(Vector2i(2, 1), 3)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table(), {0: [Vector2i(2, 1)]})

	var tile: MeshInstance3D = view._static.get_child(2)
	assert_almost_eq(
		tile.position.y, 3.0 * UnitGeometry.LEVEL_HEIGHT + BoardView.EXTRACTION_TILE_HEIGHT, 0.0001
	)


## A cover blocker on a raised cell must sit on that cell's own real
## ground too (`assembly_placements` defaults to height 0.0 — `_spawn_
## blocker` must pass the cell's own real height explicitly).
func test_spawn_blocker_sits_on_a_raised_cells_own_real_height() -> void:
	var grid := Grid.new(4, 3)
	grid.set_level(Vector2i(2, 1), 2)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 5
	crate.max_hp = 5
	crate.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.blockers[Vector2i(2, 1)] = crate
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, DataLibrary.material_table())

	var box: MeshInstance3D = view._static.get_child(2)
	assert_almost_eq(box.transform.origin.y, 2.0 * UnitGeometry.LEVEL_HEIGHT, 0.0001)


## docs/10 taskblock04 C1: "a dropped arm renders as an actual arm — plate,
## pistol and all — lying on the ground." A field object can be a whole
## part TREE, not just the root's own `volume` — the old
## `for box in part.volume` path would have silently dropped this child.
func test_build_renders_every_box_in_a_blockers_whole_part_tree() -> void:
	var grid := Grid.new(4, 3)
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 1
	pistol.max_hp = 1
	pistol.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.1, 0.3))]
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.9, 0.3))]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	arm.sockets = [grip]
	grid.blockers[Vector2i(1, 1)] = arm

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 4, "ground plane + grid lines + arm box + pistol box")


## docs/10 taskblock04 C1: "blow a shoulder off and the entire subtree...
## drops as one item" — the dropped root can itself be destroyed (hp 0,
## nothing of its own to draw) while a living child still renders. The old
## `if part.hp <= 0: return` guard would have skipped the whole tree.
func test_a_destroyed_root_with_a_living_child_still_renders_the_child() -> void:
	var grid := Grid.new(4, 3)
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.volume = [Box.new(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))]
	var shoulder := Part.new()
	shoulder.id = &"shoulder"
	shoulder.hp = 0
	shoulder.max_hp = 4
	shoulder.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	shoulder.sockets = [wrist]
	grid.blockers[Vector2i(1, 1)] = shoulder

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 3, "ground plane + grid lines + the living hand only")


## docs/10 taskblock04 C1: "lay it on its side" — a field object tagged
## DROPPED (DamageResolver's own marker) must not stand upright the way
## ordinary terrain cover does.
func test_a_dropped_blocker_lies_on_its_side() -> void:
	var grid := Grid.new(4, 3)
	var upright := Part.new()
	upright.id = &"cover"
	upright.hp = 5
	upright.max_hp = 5
	upright.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.blockers[Vector2i(0, 0)] = upright

	var dropped := Part.new()
	dropped.id = &"dropped_arm"
	dropped.hp = 4
	dropped.max_hp = 4
	dropped.tags = [DamageResolver.DROPPED_TAG]
	dropped.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.9, 0.3))]
	grid.blockers[Vector2i(2, 1)] = dropped

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var upright_mesh: MeshInstance3D = view._static.get_child(2)
	var dropped_mesh: MeshInstance3D = view._static.get_child(3)
	assert_almost_eq(upright_mesh.transform.basis.get_euler().x, 0.0, 0.001)
	assert_almost_eq(absf(dropped_mesh.transform.basis.get_euler().x), PI / 2.0, 0.001)


## docs/10 taskblock04 C3: "cover renders from its own part geometry with
## material colours" — a field object's albedo comes from its own
## `material`, the same MaterialTable lookup every other lit mesh uses.
func test_a_blockers_mesh_uses_its_own_material_color() -> void:
	var grid := Grid.new(2, 2)
	var table := DataLibrary.material_table()
	var scrap := DataLibrary.get_part(&"scrap_pile")
	grid.blockers[Vector2i(0, 0)] = scrap

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var mesh: MeshInstance3D = view._static.get_child(2)
	var material: StandardMaterial3D = mesh.mesh.material
	assert_eq(material.albedo_color, table.color_for(scrap.material))


## docs/10 taskblock02 G3 / taskblock03 I: a line per cell boundary on both
## axes, spanning exactly the grid's own footprint (half a cell of margin on
## every edge, same as the ground plane) plus half a line's own width at
## each outer edge — taskblock03 I made these real GRID_LINE_WIDTH-wide
## quads rather than 1px GPU lines, so the outermost lines' own geometry now
## genuinely extends a little past the plain center-line footprint.
func test_build_draws_grid_lines_spanning_the_grids_own_footprint() -> void:
	var grid := Grid.new(4, 3)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var mesh: ImmediateMesh = view._static.get_child(1).mesh
	assert_not_null(mesh, "the grid-line mesh must be the second static child")
	assert_eq(mesh.get_surface_count(), 1)

	var cell_size: float = UnitGeometry.CELL_SIZE
	var half: float = cell_size * 0.5
	var half_width: float = BoardView.GRID_LINE_WIDTH * 0.5
	var aabb: AABB = mesh.get_aabb()
	assert_almost_eq(aabb.position.x, -half - half_width, 0.0001)
	assert_almost_eq(aabb.position.z, -half - half_width, 0.0001)
	assert_almost_eq(aabb.end.x, (grid.width - 1) * cell_size + half + half_width, 0.0001)
	assert_almost_eq(aabb.end.z, (grid.rows - 1) * cell_size + half + half_width, 0.0001)


## taskblock-37 Pass E follow-up (supervisor): grid lines used to be one
## flat mesh at a single world height — a raised cell's own boundary now
## reaches its real top face, the same per-cell treatment `_build_terrain`
## already has, read back from the built mesh's own AABB.
func test_grid_lines_reflect_a_raised_cells_own_height() -> void:
	var grid := Grid.new(4, 3)
	grid.set_level(Vector2i(2, 1), 2)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	var grid_lines: MeshInstance3D = view._static.get_child(1)
	var aabb: AABB = grid_lines.mesh.get_aabb()
	assert_almost_eq(
		aabb.position.y,
		BoardView.GRID_LINE_HEIGHT,
		0.0001,
		"the rest of the grid stays at ground level"
	)
	assert_almost_eq(
		aabb.end.y,
		2.0 * UnitGeometry.LEVEL_HEIGHT + BoardView.GRID_LINE_HEIGHT,
		0.0001,
		"the raised cell's own border must reach its real height"
	)


## docs/10 taskblock03 I: the original color was "nearly the same value" as
## the ground — pushed far enough apart now that this margin is generous,
## not a rounding-error-sized gap.
func test_grid_line_color_is_pushed_well_away_from_the_ground_color() -> void:
	var line: Color = BoardView.GRID_LINE_COLOR
	var ground: Color = WorldPalette.GROUND
	var delta: float = absf(line.r - ground.r) + absf(line.g - ground.g) + absf(line.b - ground.b)
	assert_gt(delta, 0.3, "the two colors must read as clearly distinct values")


func test_build_clears_previous_children_on_rebuild() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, DataLibrary.material_table())
	var first_count: int = view._static.get_child_count()
	view.build(grid, DataLibrary.material_table())

	assert_eq(
		view._static.get_child_count(), first_count, "rebuilding must not accumulate children"
	)


func test_a_destroyed_blocker_spawns_no_mesh() -> void:
	var grid := Grid.new(2, 2)
	var dead := Part.new()
	dead.id = &"dead"
	dead.hp = 0
	dead.max_hp = 5
	dead.volume = [Box.new(Vector3.ZERO, Vector3(1, 1, 1))]
	grid.blockers[Vector2i(0, 0)] = dead

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(
		view._static.get_child_count(),
		2,
		"ground plane + grid lines; a dead blocker contributes nothing"
	)


## taskblock-30 follow-up (supervisor report): `Grid.field_items` (loose
## dropped Parts/Matrices) had zero visual representation anywhere — a
## real, pre-existing `Grid` concept nothing ever drew, in debug tooling
## OR real gameplay. A loose Part reuses `_spawn_blocker`'s own geometry —
## proven by an EXACT box count, not just "something got added" — the
## same "render is hitbox" contract a blocker already gets, just never
## registered as a movement/LoS obstruction (nothing about `Grid.
## field_items` feeds `Pathfinder`/`ShotPlane` — this test only proves the
## VISUAL side, `test_bout_injector_spawn_object.gd` already proves the
## mechanical side separately).
func test_build_renders_a_loose_part_field_item_the_same_as_a_blocker() -> void:
	var grid := Grid.new(4, 3)
	var dropped_arm := Part.new()
	dropped_arm.id = &"dropped_arm"
	dropped_arm.hp = 5
	dropped_arm.max_hp = 5
	dropped_arm.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.field_items[Vector2i(1, 1)] = [dropped_arm]

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(
		view._static.get_child_count(), 3, "ground plane + grid lines + the one loose item's box"
	)


## A `Matrix` field item has no `volume` to draw real geometry from — a
## flat placeholder marker instead, still a real child of `_static`.
func test_build_renders_a_loose_matrix_field_item_as_a_flat_marker() -> void:
	var grid := Grid.new(4, 3)
	var link := Matrix.new()
	link.id = &"ejected_link"
	grid.field_items[Vector2i(1, 1)] = [link]

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 3, "ground plane + grid lines + the marker")


func test_build_renders_every_item_in_a_multi_item_pile() -> void:
	var grid := Grid.new(4, 3)
	var dropped_arm := Part.new()
	dropped_arm.id = &"dropped_arm"
	dropped_arm.hp = 5
	dropped_arm.max_hp = 5
	dropped_arm.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	var link := Matrix.new()
	link.id = &"ejected_link"
	grid.field_items[Vector2i(1, 1)] = [dropped_arm, link]

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 4, "ground plane + grid lines + box + marker")


func test_build_rebuild_picks_up_a_field_item_removed_since_the_last_call() -> void:
	var grid := Grid.new(2, 2)
	var link := Matrix.new()
	link.id = &"ejected_link"
	grid.field_items[Vector2i(0, 0)] = [link]
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	var with_item_count: int = view._static.get_child_count()

	grid.field_items.erase(Vector2i(0, 0))
	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), with_item_count - 1)


## runNotes.md: "If a tile isn't navigable, it needs something to show
## that. Color it Dark Gray and draw a cross through it." WALL cells are
## permanent map geometry, so they belong in `_static`, not an overlay.
func test_build_adds_a_marker_and_a_cross_per_wall_cell() -> void:
	var grid := Grid.new(3, 2)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.WALL)
	grid.set_terrain(Vector2i(2, 1), Enums.TerrainType.WALL)

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(
		view._static.get_child_count(),
		6,
		"ground plane + grid lines + (marker + cross) per wall cell, 2 wall cells"
	)


func test_a_grid_with_no_walls_adds_no_wall_indicators() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 2, "ground plane + grid lines, nothing else")


## tb31 Pass C: "make void tiles black with a dark gray border so they
## read as void" — same "marker per non-navigable cell" convention the
## wall indicator test above already locks in, just border+fill (2
## markers) instead of marker+cross.
func test_build_adds_a_border_and_fill_marker_per_void_cell() -> void:
	var grid := Grid.new(3, 2)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.VOID)
	grid.set_terrain(Vector2i(2, 1), Enums.TerrainType.VOID)

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())

	assert_eq(
		view._static.get_child_count(),
		6,
		"ground plane + grid lines + (border + fill) per void cell, 2 void cells"
	)


func test_a_grid_with_no_void_adds_no_void_indicators() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 2, "ground plane + grid lines, nothing else")


## taskblock-22 Pass A3: "team-coded extraction tiles, drawn in their
## team's color." `team_extraction_cells` is optional (defaults to `{}`)
## — every existing caller/test above this one draws none, unchanged.
func test_build_adds_one_marker_per_extraction_tile() -> void:
	var grid := Grid.new(3, 3)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(
		grid,
		DataLibrary.material_table(),
		{0: [Vector2i(0, 0), Vector2i(1, 1)], 1: [Vector2i(2, 2)]}
	)

	assert_eq(
		view._static.get_child_count(), 5, "ground plane + grid lines + 3 extraction tile markers"
	)


func test_extraction_tiles_render_in_their_own_teams_color() -> void:
	var grid := Grid.new(3, 3)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, DataLibrary.material_table(), {0: [Vector2i(0, 0)], 1: [Vector2i(2, 2)]})

	# ground plane (0) + grid lines (1) precede the two tile markers.
	var blue_mesh: MeshInstance3D = view._static.get_child(2)
	var red_mesh: MeshInstance3D = view._static.get_child(3)
	var blue_material: StandardMaterial3D = blue_mesh.mesh.material
	var red_material: StandardMaterial3D = red_mesh.mesh.material
	assert_eq(blue_material.albedo_color, WorldPalette.team_color(0))
	assert_eq(red_material.albedo_color, WorldPalette.team_color(1))


func test_no_team_extraction_cells_adds_no_tile_markers() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)

	view.build(grid, DataLibrary.material_table())

	assert_eq(view._static.get_child_count(), 2, "ground plane + grid lines, nothing else")


func test_show_reachable_spawns_one_marker_per_cell_and_replaces_the_last_call() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	assert_eq(view._reachable_overlay.get_child_count(), 3)

	view.show_reachable([Vector2i(0, 0)])
	assert_eq(
		view._reachable_overlay.get_child_count(), 1, "a new call must replace the old overlay"
	)


## docs/10 taskblock03 D2: each leg is a marker per cell, plus its own
## polyline, plus one numbered waypoint label at its destination.
func test_show_ghost_paths_spawns_a_marker_line_and_label_per_leg() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0)]])
	assert_eq(
		view._ghost_overlay.get_child_count(),
		8,
		"(2 cell markers + 1 line + 1 label) per leg, 2 legs",
	)


func test_show_ghost_paths_numbers_waypoints_and_shows_the_running_total() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_ghost_paths(
		[[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]],
		[1.0, 2.0]
	)

	var labels: Array[Label3D] = []
	for child: Node in view._ghost_overlay.get_children():
		if child is Label3D:
			labels.append(child)
	assert_eq(labels.size(), 2)
	assert_true(labels[0].text.begins_with("1:"), "the first leg is waypoint 1")
	assert_true(labels[1].text.begins_with("2:"), "the second leg is waypoint 2")
	assert_true(labels[1].text.contains("3.0"), "the running total across both legs is 1+2")


func test_reachable_and_ghost_overlays_coexist() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])

	assert_eq(view._reachable_overlay.get_child_count(), 2, "ghosts must not clobber reachable")
	assert_eq(view._ghost_overlay.get_child_count(), 4, "2 cell markers + 1 line + 1 label")


func test_clear_overlays_removes_everything() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])
	view.show_unit_ghost(_torso_unit(Vector2i(0, 0)))
	view.show_overwatch_arc([Vector2i(2, 2)])
	view.clear_overlays()
	assert_eq(view._reachable_overlay.get_child_count(), 0)
	assert_eq(view._ghost_overlay.get_child_count(), 0)
	assert_eq(view._unit_ghost_overlay.get_child_count(), 0)
	assert_eq(view._overwatch_overlay.get_child_count(), 0)


## taskblock-19 Pass D: "a transparent pie slice... the slice shows
## exactly the cells that would trigger" — one translucent marker per
## cell in `Overwatch.arc_cells`' own output, the same per-cell-marker
## convention `show_reachable` already uses.
func test_show_overwatch_arc_spawns_one_translucent_marker_per_cell_and_replaces_the_last_call(
) -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_overwatch_arc([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	assert_eq(view._overwatch_overlay.get_child_count(), 3)
	var instance: MeshInstance3D = view._overwatch_overlay.get_child(0)
	var material: StandardMaterial3D = instance.mesh.material
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_lt(material.albedo_color.a, 1.0, "must actually be translucent, not just alpha-capable")

	view.show_overwatch_arc([Vector2i(0, 0)])
	assert_eq(
		view._overwatch_overlay.get_child_count(), 1, "a new call must replace the old overlay"
	)


func _torso_unit(cell: Vector2i, squad: int = 0) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3.ZERO, Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## docs/10 taskblock03 F1: "a translucent ghost of the unit where it will
## end up... at its final facing."
func test_show_unit_ghost_spawns_one_translucent_mesh_per_living_box() -> void:
	var view := BoardView.new()
	add_child_autofree(view)

	view.show_unit_ghost(_torso_unit(Vector2i(3, 4)))

	assert_eq(view._unit_ghost_overlay.get_child_count(), 1)
	var instance: MeshInstance3D = view._unit_ghost_overlay.get_child(0)
	var material: StandardMaterial3D = instance.mesh.material
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_lt(material.albedo_color.a, 1.0, "must actually be translucent, not just alpha-capable")
	assert_almost_eq(instance.transform.origin.x, 3.0, 0.0001)
	assert_almost_eq(instance.transform.origin.z, 4.0, 0.0001)


func test_show_unit_ghost_with_null_clears_it_and_does_not_crash() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	view.show_unit_ghost(_torso_unit(Vector2i(0, 0)))

	view.show_unit_ghost(null)

	assert_eq(view._unit_ghost_overlay.get_child_count(), 0)


func test_show_unit_ghost_never_touches_the_waypoint_ghost_overlay() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	view.show_ghost_paths([[Vector2i(0, 0), Vector2i(1, 0)]])

	view.show_unit_ghost(_torso_unit(Vector2i(5, 5)))

	assert_eq(view._ghost_overlay.get_child_count(), 4, "2 cell markers + 1 line + 1 label")
	assert_eq(view._unit_ghost_overlay.get_child_count(), 1)


func test_overlays_never_touch_the_static_board() -> void:
	var grid := Grid.new(2, 2)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	var static_count: int = view._static.get_child_count()

	view.show_reachable([Vector2i(0, 0), Vector2i(1, 0)])

	assert_eq(
		view._static.get_child_count(), static_count, "the overlay must not rebuild the board"
	)
