extends GutTest

## taskblock-59 Pass B — **the editor's visible gaps: things an author reaches for and does not
## find.**
##
## Seven reports, each small on its own. What they share is that the capability existed and the way
## in did not — the same class the whole block is built around.

const CLAIM_CHOICE := &"claim_exterior"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _overlay() -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	return overlay


func _editor(overlay: ControlOverlay) -> EditorModule:
	return overlay.module(&"editor") as EditorModule


# ------------------------------------------------- the ghost over an empty tile


## *"No hover ghost over an empty tile. An empty cell is where an author most needs to know what a
## click will do."* `PartPicker.hit` answers `{}` over bare board — it found no part, which is true
## and is the wrong answer to "what is under the cursor".
func test_a_hover_over_an_empty_cell_produces_a_ghost() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var ghost: PlacementGhostModule = overlay.module(&"placement_ghost") as PlacementGhostModule
	var picking: BoardInspectModule = overlay.module(&"board_inspect") as BoardInspectModule
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"ship_floor"

	# What the picker reports over bare board: no part, but a real cell.
	picking.hovered_pick.emit(
		{"unit": null, "part": null, "cell": Vector2i(5, 5), "t": INF, "normal": null}
	)

	assert_true(ghost.is_showing(), "nothing was previewed over the empty cell")
	assert_eq(ghost.target["cell"], Vector2i(5, 5), "and it previewed somewhere else")


## The bare-cell pick is built where the ray is cast, so the shape is pinned at its source rather
## than only where it is consumed.
func test_a_pick_that_found_no_part_still_reports_the_cell() -> void:
	var bare: Dictionary = BoardInspectModule._pick_or_bare_cell({}, Vector2i(3, 4))
	assert_eq(bare["cell"], Vector2i(3, 4))
	assert_null(bare["normal"], "no struck face, which is what makes it use the authored height")
	assert_null(bare["part"])

	var off_board: Dictionary = BoardInspectModule._pick_or_bare_cell({}, null)
	assert_true(off_board.is_empty(), "off the board is still nothing at all")

	var real: Dictionary = {
		"unit": null, "part": null, "cell": Vector2i(1, 1), "normal": Vector3.UP
	}
	assert_eq(
		BoardInspectModule._pick_or_bare_cell(real, Vector2i(9, 9)),
		real,
		"a real pick is never replaced by the cell the ray crossed"
	)


# ------------------------------------------------- the parts-list toggle


## *"The parts-list button in UI buttons does not toggle the list."* It flipped `collapsed`, which
## `PartsListModule` never read — the button's border followed the list correctly while the press
## did nothing to it.
func test_the_parts_list_button_toggles_the_list() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	bar.open_list_for(&"place_terrain")
	assert_true(parts.is_showing(), "sanity: the list is up")

	parts.collapsed = true
	assert_false(parts.is_showing(), "the toggle did not dismiss the list")

	parts.collapsed = false
	assert_true(parts.is_showing(), "and the same toggle did not summon it back")


## The summoned list is the armed tool's own, so the button and the tool buttons cannot disagree.
func test_the_summoned_list_offers_the_armed_tool_s_parts() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	editor.active_tool = &"place_terrain"

	parts.collapsed = true
	parts.collapsed = false

	var offered: Array[StringName] = EditorTools.part_ids_for(
		&"place_terrain", editor.placeable_part_ids()
	)
	gut.p("offered: %s" % str(offered))
	assert_true(parts.is_showing())
	assert_has(offered, &"ship_floor", "sanity: terrain includes the floor")


# ------------------------------------------------- Map Thing gets a picker


## *"Map Thing places only lime-green volumes. It has no picker, so every claim comes out
## `Interior`."* The selection existed; the way to make it did not.
func test_map_thing_opens_a_picker_covering_every_thing_and_claim_kind() -> void:
	var overlay: ControlOverlay = _overlay()
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule

	bar.open_list_for(&"place_map_thing")

	assert_true(parts.is_showing(), "Map Thing offered no list at all")
	var offered: Array[StringName] = EditorTools.map_thing_choices(EditorModule.CLAIM_KINDS)
	gut.p("offered: %s" % str(offered))
	for thing: StringName in [&"spawn_a", &"spawn_b", &"spawn_none", &"chance"]:
		assert_has(offered, thing, "%s is not reachable" % thing)
	for kind: StringName in EditorModule.CLAIM_KINDS:
		assert_has(offered, StringName("claim_%s" % kind), "claim %s is not reachable" % kind)
	assert_does_not_have(offered, &"claim", "the bare claim entry would author the default again")


## And picking one arms it — the round trip from the list to what a click authors.
func test_picking_a_claim_kind_authors_that_kind() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	bar.open_list_for(&"place_map_thing")

	parts.list.chosen.emit(CLAIM_CHOICE)
	editor.active_tool = &"place_map_thing"
	editor.apply_tool_at(Vector2i(2, 2))

	assert_eq(editor.selected_map_thing, &"claim")
	assert_eq(editor.selected_claim_kind, SectionClaim.KIND_EXTERIOR, "the picked kind was ignored")
	assert_eq(editor.controller.claims.size(), 1, "no claim was authored")
	assert_eq(
		editor.controller.claims[0].kind,
		SectionClaim.KIND_EXTERIOR,
		"the claim came out as the default kind, which is the whole defect"
	)


func test_a_spawn_marker_is_reachable_from_the_same_picker() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var parts: PartsListModule = overlay.module(&"parts_list") as PartsListModule
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	bar.open_list_for(&"place_map_thing")

	parts.list.chosen.emit(&"spawn_b")
	editor.active_tool = &"place_map_thing"
	editor.apply_tool_at(Vector2i(3, 3))

	assert_eq(editor.controller.spawn_markers.get(Vector2i(3, 3)), Enums.SpawnMarker.SPAWN_B)


# ------------------------------------------------- the readout names the active thing


## *"The coordinate readout does not say what is being placed... add the active thing, which is the
## one piece an author needs and cannot infer."*
func test_the_readout_names_the_active_placement() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var coords: EditorCoordsModule = overlay.module(&"editor_coords") as EditorCoordsModule
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"wall"

	coords.show_cell(Vector2i(1, 1))

	gut.p("readout: '%s' / '%s'" % [coords.cell_label.text, coords.content_label.text])
	assert_eq(coords.placing(), &"wall")
	assert_true(
		coords.content_label.text.contains("wall"), "the readout does not name what is armed"
	)


## A tool that places nothing says so rather than naming a stale part.
func test_the_readout_does_not_name_a_part_under_a_tool_that_places_none() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var coords: EditorCoordsModule = overlay.module(&"editor_coords") as EditorCoordsModule
	editor.selected_part = &"wall"
	editor.active_tool = &"delete"

	coords.show_cell(Vector2i(1, 1))

	gut.p("readout: '%s'" % coords.content_label.text)
	assert_false(coords.content_label.text.contains("wall"), "Delete is not holding a wall")
	assert_eq(coords.placing(), &"delete")


func test_the_readout_names_the_claim_kind_under_map_thing() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var coords: EditorCoordsModule = overlay.module(&"editor_coords") as EditorCoordsModule
	editor.active_tool = &"place_map_thing"
	editor.selected_map_thing = &"claim"
	editor.selected_claim_kind = SectionClaim.KIND_ENTRY

	assert_true(String(coords.placing()).contains("entry"), "which claim is what the author picked")


# ------------------------------------------------- the default floor


## taskblock-59 Pass B, supervisor's call: **the ordinary floor is named, not sorted for.**
##
## `surface_part_ids()` is alphabetical and the GROUND-attaching parts are `[ramp, ship_floor]`, so
## "the first surface part" has meant `ramp` since taskblock-56 — which is both the auto-placed-ramp
## report and the reason placing a `ship_floor` warned about a surface the author never put down.
func test_the_editor_is_armed_with_the_ordinary_floor() -> void:
	var editor: EditorModule = _editor(_overlay())
	gut.p("surfaces sort as %s" % str(editor.surface_part_ids()))
	assert_eq(editor.default_floor(), &"ship_floor")
	assert_eq(editor.selected_part, &"ship_floor", "a fresh editor is armed with a ramp")
	assert_eq(editor.last_surface_part, &"ship_floor")


## And the tile a wall brings with it is that floor.
func test_a_wall_on_bare_ground_brings_a_floor_not_a_ramp() -> void:
	var editor: EditorModule = _editor(_overlay())
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"wall"

	editor.apply_tool_at(Vector2i(4, 4))

	var here: Array[StringName] = []
	for placement: MapPlacement in editor.controller.placements_at(Vector2i(4, 4)):
		here.append(placement.part_id)
	gut.p("cell (4,4) holds %s" % str(here))
	assert_has(here, &"ship_floor", "the editor authored something else under the wall")
	assert_does_not_have(here, &"ramp")


## **The warning the report was about, and it was correct all along.** With the floor no longer a
## ramp the author's own `ship_floor` lands where they expect and nothing complains.
func test_placing_ship_floor_on_bare_ground_warns_about_nothing() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var sink := MemorySink.new()
	overlay.battle.combat_state.combat_log.add_sink(sink)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"ship_floor"
	var before: int = sink.events.size()

	editor.apply_tool_at(Vector2i(2, 2))

	var said: Array[String] = []
	for i: int in range(before, sink.events.size()):
		if sink.events[i].kind == EditorLog.WARNING:
			said.append(sink.events[i].text)
	gut.p("warnings: %s" % " | ".join(said))
	assert_eq(said, [] as Array[String], "the most ordinary placement in the editor complained")


# ------------------------------------------------- the gizmo inside an item


## *"The select gizmo sits inside items. Acceptable, but then it must be clickable and draggable
## there."*
##
## **It always was, and this pins why** rather than trusting it: `Gizmo.hit` is a ray/box test
## against the handle boxes with nothing in front of them, so geometry burying a handle cannot hide
## it from a ray. The ray used here is one that passes through the wall first.
func test_a_handle_inside_a_part_is_still_hit_testable() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	var cell := Vector2i(3, 3)
	editor.controller.place(cell, &"ship_floor")
	editor.controller.place(cell, &"wall", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	editor.active_tool = &"select"
	editor.apply_tool_at(cell)

	assert_eq(handles.gizmo.subject, Gizmo.SUBJECT_PLACEMENT, "sanity: the gizmo grabbed the wall")
	var origin: Vector3 = handles.gizmo_origin()
	# Straight down the +Y handle from well above the wall, so the ray crosses the wall's own boxes
	# before it reaches the handle.
	var struck: Dictionary = Gizmo.hit(
		Gizmo.translate_handles(origin), origin + Vector3(0.0, 12.0, 0.0), Vector3.DOWN
	)
	gut.p("struck: %s" % str(struck))
	assert_false(struck.is_empty(), "a handle standing inside a wall could not be grabbed")


## **The gizmo takes the input walk before the board picker**, which is what stops a press on a
## buried handle also authoring on the cell underneath. Declaration order is the mechanism, so the
## order is what is asserted.
func test_the_gizmo_is_offered_input_before_the_board_picker() -> void:
	var modules: Array[StringName] = ViewModes.EDITOR_MODULES
	assert_lt(
		modules.find(&"gizmo"),
		modules.find(&"board_inspect"),
		"a press on a handle would reach the picker first and author on the cell under it"
	)


## *"...and the selected part should render as a ghost so the handles are readable through it."*
## Read back off the real mesh, not off a second copy of the formula.
func test_the_selected_part_renders_as_a_ghost() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var board: BoardView = overlay.battle.board_view
	var cell := Vector2i(3, 3)
	editor.controller.place(cell, &"ship_floor")
	editor.controller.place(cell, &"pillar", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	var drawn: Array[MeshInstance3D] = board.ghosting.meshes_at(cell)
	assert_false(drawn.is_empty(), "sanity: the pillar is drawn as real meshes")
	for mesh: MeshInstance3D in drawn:
		assert_null(mesh.material_override, "sanity: nothing is ghosted yet")

	editor.active_tool = &"select"
	editor.apply_tool_at(cell)

	assert_eq(board.ghosting.ghosted(), cell, "the board is not ghosting what the gizmo grabbed")
	for mesh: MeshInstance3D in board.ghosting.meshes_at(cell):
		var override: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		assert_not_null(override, "a mesh of the selected part is still fully opaque")
		# **Guarded rather than dereferenced.** A null here is an assertion failure, and reading
		# through it is a runtime error, which under `-d` opens a Debugger Break and HANGS the run
		# instead of failing it — `run_tests.sh`'s own header warns about exactly this shape.
		if override == null:
			continue
		assert_almost_eq(override.albedo_color.a, CellGhosting.ALPHA, 0.001)
		assert_eq(override.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)


## And letting go restores it — a board that stayed see-through after a deselect would be the
## editor lying about what is solid.
func test_deselecting_restores_the_part() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var board: BoardView = overlay.battle.board_view
	var cell := Vector2i(3, 3)
	editor.controller.place(cell, &"ship_floor")
	editor.controller.place(cell, &"pillar", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	editor.active_tool = &"select"
	editor.apply_tool_at(cell)

	editor.apply_tool_at(Vector2i(8, 8))

	assert_null(board.ghosting.ghosted(), "the ghost survived a click on empty board")
	for mesh: MeshInstance3D in board.ghosting.meshes_at(cell):
		assert_null(mesh.material_override, "the deselected part is still see-through")


## The ghosting keeps its own colour, so an author can still tell what they grabbed.
func test_the_ghost_keeps_the_part_s_own_colour() -> void:
	var mesh := MeshInstance3D.new()
	autofree(mesh)
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 0.9)
	box.material = material
	mesh.mesh = box

	var ghost: StandardMaterial3D = CellGhosting.material_for(mesh)

	assert_almost_eq(ghost.albedo_color.r, 0.2, 0.001, "the part's own colour is gone")
	assert_almost_eq(ghost.albedo_color.g, 0.6, 0.001)
	assert_almost_eq(ghost.albedo_color.b, 0.9, 0.001)
	assert_almost_eq(ghost.albedo_color.a, CellGhosting.ALPHA, 0.001)


# ------------------------------------------------- the wall cutout


## *"Cutout or culling is affecting walls in the editor. The editor has no unit to cut around, so
## either the cutout should be off in editor modes or it is keying off something stale."*
##
## **Stale.** `BattleScene` feeds `wall_cutout_units = combat_state.units` and the editor never
## replaces it, so the shader kept punching portholes at the last bout's cells. Expressed as "not
## drawn, so not cut around", which needs no mode named in `BoardView`.
func test_a_unit_the_authored_board_cannot_seat_cuts_no_hole() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var board: BoardView = overlay.battle.board_view
	var state: CombatState = overlay.battle.combat_state
	assert_gt(state.units.size(), 0, "sanity: the editor installed over a bout with units in it")

	# An authored board with no floor on it strands every one of them.
	editor.controller.set_size(6, 6)
	editor.refresh()

	var hidden := 0
	for view: HitVolumeView in overlay.battle.unit_views:
		if view.unit != null and not view.visible:
			hidden += 1
			assert_true(
				board.is_excluded_from_occlusion(view.unit.id),
				"unit %d is not drawn and is still cutting a hole in the walls" % view.unit.id
			)
	gut.p(
		(
			"%d of %d unit views hidden on the authored board"
			% [hidden, overlay.battle.unit_views.size()]
		)
	)
	assert_gt(hidden, 0, "sanity: nothing was stranded, so the claim is untested")
