extends GutTest

## **Two reports that turned out to be one unit, and a preview that lands a floor's thickness low.**
##
## > *"Something is causing a cutout or culling sphere on wall parts in the editor... UPDATE: this
## > goes away after placing more walls or just more items."*
## > *"A random unit stuck around in the editor from the prior map, a squad 0 unit 0 looks like.
## > UPDATE: this also vanished at the same time as the above culling issue."*
##
## `BoardSwap.swap_board` seats every living unit on **the first free walkable cell**, so the
## author's very first floor tile gets a bout unit standing on it — visible, and feeding the
## wall-cutout shader a hole to punch. taskblock-59 Pass B covered only the units the board could
## *not* seat; the seated one was never covered, which is why it came and went with whatever the
## author had placed.
##
## **The editor draws no bout units at all.** It authors a board; it does not play one.


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


## A board with real floor on it — which is exactly the state that seats a unit.
func _floored(overlay: ControlOverlay) -> EditorModule:
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(6, 6)
	for y: int in range(3):
		for x: int in range(3):
			editor.controller.place(Vector2i(x, y), &"ship_floor")
	editor.controller.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	editor.refresh()
	return editor


# ---------------------------------------------------------------- no unit in the editor


## **The reported state, made deterministic.** A board that CAN seat a unit still shows none.
func test_a_board_that_can_seat_a_unit_still_draws_none() -> void:
	var overlay: ControlOverlay = _overlay()
	assert_gt(overlay.battle.combat_state.units.size(), 0, "sanity: a bout came in with units")
	_floored(overlay)

	var seated: Array[int] = []
	for view: HitVolumeView in overlay.battle.unit_views:
		if view.unit != null and view.visible:
			seated.append(view.unit.id)
	gut.p("units drawn on the authored board: %s" % str(seated))
	assert_eq(seated, [] as Array[int], "a bout unit is standing on the authored board")


## And none of them feeds the wall cutout, which is the half that was actually reported.
func test_no_unit_cuts_a_hole_in_the_editor_s_walls() -> void:
	var overlay: ControlOverlay = _overlay()
	_floored(overlay)

	for unit: Unit in overlay.battle.combat_state.units:
		assert_true(
			overlay.battle.board_view.is_excluded_from_occlusion(unit.id),
			"unit %d is still cutting a porthole in the editor's walls" % unit.id
		)


## **It must not depend on what has been placed**, which is what made the report read as
## intermittent: before any floor the unit was stranded and hidden, and the first floor seated it.
func test_it_holds_at_every_stage_of_authoring() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(6, 6)

	for step: int in range(4):
		editor.controller.place(Vector2i(step, 0), &"ship_floor")
		editor.refresh()
		for view: HitVolumeView in overlay.battle.unit_views:
			assert_false(view.visible, "a unit appeared after %d floor tile(s)" % (step + 1))


## Launching a test bout is what brings them back — the editor is a surface over a board, and
## running one is leaving that surface.
func test_running_a_test_bout_puts_the_units_back_on_screen() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _floored(overlay)

	assert_eq(editor.run_test_bout()["error"], "", "the board launched")

	var drawn := 0
	for view: HitVolumeView in overlay.battle.unit_views:
		if view.unit != null and view.visible:
			drawn += 1
	gut.p("%d of %d unit views drawn after launching" % [drawn, overlay.battle.unit_views.size()])
	assert_gt(drawn, 0, "the bout launched and nobody is on the board")


# ---------------------------------------------------------------- the ghost matches the board


## *"Things are getting placed 0.2 lower than they should be when clicking a side face... but we
## needed to make the ghost match the logic, not make the logic match the ghost."*
##
## **The first attempt at this changed `FacePlacement` — the shared answer the click uses — and so
## moved where things were authored. That was backwards and is reverted.** The real divergence is
## that `BoardView` draws a blocker at the cell's **true walkable height**, ignoring the placement's
## authored height (which is correct: `MapPlacement.height` is surfaces-only), while the ghost drew
## at the target height. So the logic was right and the preview was lying.
##
## Asserted by reading the ghost's own mesh back against the board's own mesh, rather than against
## either formula.
func test_the_ghost_of_a_blocker_sits_where_the_board_puts_it() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var ghost: PlacementGhostModule = overlay.module(&"placement_ghost") as PlacementGhostModule
	var picking: BoardInspectModule = overlay.module(&"board_inspect") as BoardInspectModule
	editor.controller.set_size(6, 6)
	editor.controller.place(Vector2i(2, 2), &"ship_floor")
	editor.controller.place(Vector2i(3, 2), &"ship_floor")
	editor.controller.place(Vector2i(2, 2), &"wall", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"wall"

	# Hover the east face of the wall: the placement lands in (3,2).
	picking.hovered_pick.emit(
		{"unit": null, "part": null, "cell": Vector2i(2, 2), "t": 1.0, "normal": Vector3.RIGHT}
	)
	assert_true(ghost.is_showing(), "sanity: something was previewed")
	var previewed: Array[Transform3D] = ghost.ghost_transforms()

	# Now actually place it and read the board's own mesh back.
	editor.struck_normal = Vector3.RIGHT
	editor.apply_tool_at(Vector2i(2, 2))
	editor.struck_normal = null
	var drawn: Array[MeshInstance3D] = overlay.battle.board_view.ghosting.meshes_at(Vector2i(3, 2))

	assert_false(drawn.is_empty(), "sanity: the wall really landed at (3,2)")
	gut.p(
		(
			"ghost y %.3f, board y %.3f"
			% [previewed[0].origin.y, (drawn[0] as MeshInstance3D).transform.origin.y]
		)
	)
	assert_almost_eq(
		previewed[0].origin.y,
		(drawn[0] as MeshInstance3D).transform.origin.y,
		0.001,
		"the ghost showed a height the board does not use"
	)


## **The logic is untouched**, which is the half the supervisor called out. A side face still
## resolves to the struck geometry's own bottom — that is what the click authors, and this pins that
## the preview fix did not move it.
func test_the_side_face_target_is_unchanged() -> void:
	var placements: Array[MapPlacement] = [
		MapPlacement.new(Vector2i(2, 2), MapPlacement.KIND_SURFACE, &"ship_floor", 0.0),
		MapPlacement.new(Vector2i(2, 2), MapPlacement.KIND_BLOCKER, &"wall", 0.0),
	]

	var target: Dictionary = FacePlacement.target_from(
		placements, Vector2i(2, 2), Vector3.RIGHT, 0.0
	)

	gut.p("side target -> cell %s h %.2f" % [target["cell"], target["height"]])
	assert_eq(target["cell"], Vector2i(3, 2))
	assert_almost_eq(
		float(target["height"]),
		-0.2,
		0.001,
		"the shared target moved; only the ghost was supposed to change"
	)
