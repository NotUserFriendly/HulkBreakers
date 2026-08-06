extends GutTest

## **Four reports against the editor's gizmo, three of which are one defect.**
##
## > *"Moving a pillar moves the floor beneath. This may be intentional, so check first."*
## > *"Sometimes the move gizmo becomes detached from the part it is moving."*
## > *"The horizontal drags for the move gizmo should move the item."*
##
## **It was not intentional.** The gizmo addressed a **cell**, and every operation resolved that
## cell to a different placement: the handles were drawn from the topmost placement (the pillar)
## and `set_height` wrote to the topmost *surface* (the floor under it). The detachment follows —
## after a drag the handles and the thing that moved disagree — and the horizontal drag could not
## work at all until the addressing was fixed.
##
## The fourth is its own thing: **arming a different tool must let go of the subject.**


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


## A pillar standing on a floor at (3,3), with Select armed on it.
func _pillar_on_a_floor(overlay: ControlOverlay) -> EditorModule:
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(8, 8)
	editor.controller.place(Vector2i(3, 3), &"ship_floor")
	editor.controller.place(Vector2i(3, 3), &"pillar", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	editor.active_tool = &"select"
	editor.apply_tool_at(Vector2i(3, 3))
	return editor


func _at(editor: EditorModule, cell: Vector2i, part: StringName) -> MapPlacement:
	for placement: MapPlacement in editor.controller.placements_at(cell):
		if placement.part_id == part:
			return placement
	return null


# ---------------------------------------------------------------- the floor stays put


## **The reported defect.** Dragging the pillar's arrow moved the floor.
func test_moving_a_pillar_leaves_the_floor_where_it_was() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	var floor_before: float = _at(editor, Vector2i(3, 3), &"ship_floor").height

	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles._drag_to(Vector2(400.0, 340.0))

	var floor_after: float = _at(editor, Vector2i(3, 3), &"ship_floor").height
	var pillar: MapPlacement = _at(editor, Vector2i(3, 3), &"pillar")
	gut.p("floor %.2f -> %.2f, pillar offset %s" % [floor_before, floor_after, pillar.offset])
	assert_almost_eq(floor_after, floor_before, 0.001, "the floor moved instead of the pillar")
	assert_ne(pillar.offset.y, 0.0, "and the pillar did not move at all")


## A floor's own drag still writes its height, because that is what a surface's height means.
func test_moving_a_floor_still_writes_its_height() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(8, 8)
	editor.controller.place(Vector2i(3, 3), &"ship_floor")
	editor.refresh()
	editor.active_tool = &"select"
	editor.apply_tool_at(Vector2i(3, 3))
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule

	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles._drag_to(Vector2(400.0, 340.0))

	gut.p("floor height %.2f" % _at(editor, Vector2i(3, 3), &"ship_floor").height)
	assert_ne(_at(editor, Vector2i(3, 3), &"ship_floor").height, 0.0, "the floor did not move")


# ---------------------------------------------------------------- horizontal moves


## *"The horizontal drags for the move gizmo should move the item... snap by cell."*
##
## **How far it moves is asserted as a property, not a count.** `amount_at` converts pixels to world
## units through the live camera's projection, so the number of cells a 60 px drag covers is a fact
## about the camera rather than about the tool.
func test_a_horizontal_drag_moves_the_placement_by_whole_cells() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule

	handles.begin_drag(Gizmo.AXIS_X, 1.0, Vector2(400.0, 400.0))
	handles._drag_to(Vector2(460.0, 400.0))

	var moved: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements:
		if placement.part_id == &"pillar":
			moved = placement
	gut.p("pillar is now at %s" % moved.cell)
	assert_ne(moved.cell, Vector2i(3, 3), "the pillar did not move at all")
	assert_eq(moved.cell.y, 3, "an X drag moved it along Z as well")
	assert_null(_at(editor, Vector2i(3, 3), &"pillar"), "and it is still in the old cell too")
	assert_not_null(_at(editor, Vector2i(3, 3), &"ship_floor"), "the floor came with it")


## **The gizmo follows what it moved**, which is the detachment report. Asserted as *the handles are
## on the placement*, which is the claim — not on a particular cell, which is the camera's business.
func test_the_gizmo_follows_the_placement_it_moved() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule

	handles.begin_drag(Gizmo.AXIS_X, 1.0, Vector2(400.0, 400.0))
	handles._drag_to(Vector2(460.0, 400.0))

	var moved: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements:
		if placement.part_id == &"pillar":
			moved = placement
	gut.p("pillar at %s, gizmo at %s" % [moved.cell, handles.gizmo.cell])
	assert_ne(moved.cell, Vector2i(3, 3), "sanity: it moved")
	assert_eq(handles.gizmo.cell, moved.cell, "the handles stayed behind on the empty cell")


## The whole-cell snap: a drag shorter than a cell moves nothing at all.
func test_a_drag_shorter_than_a_cell_moves_nothing() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule

	handles.begin_drag(Gizmo.AXIS_X, 1.0, Vector2(400.0, 400.0))
	handles._drag_to(Vector2(408.0, 400.0))

	assert_not_null(_at(editor, Vector2i(3, 3), &"pillar"), "a nudge moved it a whole cell")


# ---------------------------------------------------------------- letting go


## *"Clicking to a different tool needs to clean up gizmos attached to other parts."*
func test_arming_a_place_tool_lets_go_of_the_gizmo() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	assert_eq(handles.gizmo.subject, Gizmo.SUBJECT_PLACEMENT, "sanity: it grabbed the pillar")

	editor.active_tool = &"place_terrain"

	assert_eq(handles.gizmo.subject, Gizmo.SUBJECT_NONE, "the handles are still on the pillar")
	assert_true(handles.meshes.is_empty(), "and still drawn")
	assert_null(
		overlay.battle.board_view.ghosting.ghosted(), "the selected part is still see-through"
	)


## **Swapping between Select and Scale keeps it**, because those are the gizmo's own two tools.
func test_swapping_between_select_and_scale_keeps_the_subject() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule

	editor.active_tool = &"scale"

	assert_eq(handles.gizmo.subject, Gizmo.SUBJECT_PLACEMENT, "swapping handle sets let go")


# ---------------------------------------------------------------- the readout


## *"The hovering size indicator... should attach to the control being dragged, or the mouse
## cursor."* The cursor, which is already the argument every drag handler receives.
func test_the_readout_follows_the_pointer() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _pillar_on_a_floor(overlay)
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))

	handles._drag_to(Vector2(400.0, 340.0))
	var near_first: Vector2 = handles.readout.position
	handles._drag_to(Vector2(900.0, 200.0))

	gut.p("readout at %s then %s" % [near_first, handles.readout.position])
	assert_true(handles.readout.visible)
	assert_ne(handles.readout.position, near_first, "the readout did not follow the pointer")
	assert_gt(handles.readout.position.x, near_first.x, "and it went the wrong way")


# ---------------------------------------------------------------- floors on floors


## *"I can't tell for sure, but it looks like floors can be placed in a tile with a floor already
## there."* **They can, and it is warned rather than refused — deliberately.**
##
## Blocking it was tried and reverted. Two co-planar floors are something the format can express —
## `Grid` holds an ordered surface stack per cell and `MapSerializer` adds both — so refusing them
## is a *legality opinion*, which is the line taskblock-59 Pass A drew and stayed behind: the editor
## refuses only what the board has nowhere to put. It also directly contradicts `EditorController`'s
## own *"warn, never block"* rule and the named test that asserts it
## (`test_an_illegal_placement_is_still_placed_and_only_warned_about`), which is a taskblock-56 F4
## acceptance.
##
## So this pins the current, deliberate behaviour: it lands, and the author is told.
func test_a_second_floor_at_the_same_level_lands_and_is_warned_about() -> void:
	var editor := EditorController.new()
	editor.set_size(3, 3)
	editor.place(Vector2i(1, 1), &"ship_floor", MapPlacement.KIND_SURFACE, 0.0)

	assert_not_null(
		editor.place(Vector2i(1, 1), &"ship_floor", MapPlacement.KIND_SURFACE, 0.0),
		"refusing it would be a legality opinion, which this editor does not hold"
	)

	var said: String = "\n".join(editor.warnings())
	gut.p("warnings: %s" % said)
	assert_true(said.contains("already has a surface"), "and the author is not told")
