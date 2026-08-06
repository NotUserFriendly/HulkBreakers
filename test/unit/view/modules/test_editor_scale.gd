extends GutTest

## taskblock-59 Pass C — **the Scale tool authors a size, which nothing did.**
##
## `MapPlacement.size` landed in taskblock-58 — tested, serialised, hp following volume, a destroyed
## 3 x 3 x 0.5 wall leaving a designed hole — and **nothing wrote it except a hand-authored
## `.tres`**. The gesture existed too: the Scale tool, the gizmo and face picking all landed. They
## were not connected to the field. This is the connection, end to end.

const SAVED_MAP := "user://test_editor_scale.tres"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()
	if FileAccess.file_exists(SAVED_MAP):
		DirAccess.remove_absolute(SAVED_MAP)


func _overlay() -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	return overlay


func _editor(overlay: ControlOverlay) -> EditorModule:
	return overlay.module(&"editor") as EditorModule


## A wall standing at (3,3) with the Scale tool armed on it.
func _scaled_wall(overlay: ControlOverlay) -> EditorModule:
	var editor: EditorModule = _editor(overlay)
	editor.controller.place(Vector2i(3, 3), &"ship_floor")
	editor.controller.place(Vector2i(3, 3), &"wall", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	editor.active_tool = &"scale"
	editor.struck_normal = Vector3.UP
	editor.apply_tool_at(Vector2i(3, 3))
	return editor


# ------------------------------------------------- the handles exist at all


## **The Scale tool was armed and inert.** A placement asked for resize handles and
## `_current_handles` had only a claim branch, so it silently got the translate set.
func test_the_scale_tool_gives_a_placement_resize_handles() -> void:
	var overlay: ControlOverlay = _overlay()
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	_scaled_wall(overlay)

	assert_eq(handles.gizmo.subject, Gizmo.SUBJECT_PLACEMENT)
	assert_eq(handles.gizmo.handles, Gizmo.Handles.RESIZE, "Scale armed the translate arrows")
	assert_eq(handles.meshes.size(), 6, "six faces, one handle each")


## The handles sit on the faces of what is drawn, not on the part's authored dimensions — so a
## placement already resized once can be grabbed again where the author can see it.
func test_the_handles_follow_the_size_that_is_drawn() -> void:
	var overlay: ControlOverlay = _overlay()
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	var editor: EditorModule = _scaled_wall(overlay)
	var natural: AABB = handles.placement_volume()

	editor.controller.set_placement_size(Vector2i(3, 3), Vector3(3.0, 2.4, 0.5))
	editor.refresh()
	handles.reassert_ghost()

	var resized: AABB = handles.placement_volume()
	gut.p("natural %s -> resized %s" % [natural.size, resized.size])
	assert_almost_eq(resized.size.x, 3.0, 0.001, "the handles are still on the old faces")


# ------------------------------------------------- a drag writes the field


## **The acceptance**: dragging a face changes `MapPlacement.size`, and the readout matches.
func test_dragging_a_face_writes_the_size_and_the_readout_agrees() -> void:
	var overlay: ControlOverlay = _overlay()
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	var editor: EditorModule = _scaled_wall(overlay)
	var before: Vector3 = editor.controller.placements_at(Vector2i(3, 3))[1].size
	assert_eq(before, Vector3.ZERO, "sanity: an unsized placement is the part's own")

	# Grab the top face and drag it up. The struck normal is what makes Y the perpendicular axis.
	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles._drag_placement_size(editor, Vector2(400.0, 340.0), Vector2(0.0, -60.0))

	var placement: MapPlacement = editor.controller.placements_at(Vector2i(3, 3))[1]
	gut.p(
		"size %s offset %s readout '%s'" % [placement.size, placement.offset, handles.readout.text]
	)
	assert_ne(placement.size, Vector3.ZERO, "the drag wrote nothing")
	assert_true(handles.readout.visible, "a drag with no number on it is the tool half-built")
	assert_eq(
		handles.readout.text,
		"%.1f" % placement.size.y,
		"the readout and the authored size are different numbers"
	)


## Only the grabbed face moved, which is what the offset records.
func test_a_top_face_drag_leaves_the_base_where_it_was() -> void:
	var overlay: ControlOverlay = _overlay()
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	var editor: EditorModule = _scaled_wall(overlay)
	var base_before: float = handles.placement_volume().position.y

	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles._drag_placement_size(editor, Vector2(400.0, 340.0), Vector2(0.0, -60.0))

	var after: AABB = handles.placement_volume()
	gut.p("base %.3f -> %.3f, top now %.3f" % [base_before, after.position.y, after.end.y])
	assert_almost_eq(
		after.position.y, base_before, 0.001, "the wall grew downward through its own floor"
	)


# ------------------------------------------------- it survives, and the hp follows


## *"The authored size round-trips and the HP follows it."*
func test_an_authored_size_survives_save_and_load() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	editor.controller.set_size(6, 6)
	editor.controller.place(Vector2i(2, 2), &"ship_floor")
	editor.controller.place(Vector2i(2, 2), &"wall", MapPlacement.KIND_BLOCKER)
	editor.controller.set_placement_size(
		Vector2i(2, 2), Vector3(3.0, 3.0, 0.5), Vector3(0.0, 0.3, 0.0)
	)
	editor.panel.name_field.text = SAVED_MAP
	assert_eq(editor.save_as_map()["error"], "", "it wrote")

	var reopened: EditorModule = _editor(_overlay())
	assert_eq(reopened.open(SAVED_MAP)["error"], "")

	var loaded: MapPlacement = null
	for placement: MapPlacement in reopened.controller.placements_at(Vector2i(2, 2)):
		if placement.part_id == &"wall":
			loaded = placement
	assert_not_null(loaded, "the wall did not come back")
	assert_almost_eq(loaded.size.x, 3.0, 0.0001, "the authored size did not survive the file")
	assert_almost_eq(loaded.size.z, 0.5, 0.0001)
	assert_almost_eq(loaded.offset.y, 0.3, 0.0001, "and neither did the offset")


## HP is proportional to the new volume, through the one resolver that already owned it.
func test_a_resized_wall_s_hp_is_proportional_to_its_volume() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	editor.controller.place(Vector2i(2, 2), &"ship_floor")
	editor.controller.place(Vector2i(2, 2), &"wall", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	var natural_hp: int = overlay.battle.combat_state.grid.blockers[Vector2i(2, 2)].max_hp

	var wall: Part = DataLibrary.get_part(&"wall")
	var doubled: Vector3 = PlacedVolume.natural_size(wall) * Vector3(2.0, 1.0, 1.0)
	editor.controller.set_placement_size(Vector2i(2, 2), doubled)
	editor.refresh()

	var grown_hp: int = overlay.battle.combat_state.grid.blockers[Vector2i(2, 2)].max_hp
	gut.p("hp %d -> %d for twice the wall" % [natural_hp, grown_hp])
	assert_eq(grown_hp, natural_hp * 2, "twice the wall is twice the hp")


## And the board really draws it at the authored size — read off the grid the view was built from.
func test_the_resized_wall_is_what_the_board_is_built_from() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	editor.controller.place(Vector2i(2, 2), &"ship_floor")
	editor.controller.place(Vector2i(2, 2), &"wall", MapPlacement.KIND_BLOCKER)
	editor.controller.set_placement_size(Vector2i(2, 2), Vector3(3.0, 2.4, 0.5))
	editor.refresh()

	var drawn: Part = overlay.battle.board_view.grid.blockers[Vector2i(2, 2)]
	var extent: Vector3 = PlacedVolume.natural_size(drawn)
	gut.p("the board's own wall measures %s" % extent)
	assert_almost_eq(extent.x, 3.0, 0.001, "the board is drawing the part's authored dimensions")


# ------------------------------------------------- refusals


func test_a_size_with_no_volume_in_it_is_refused() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(1, 1), &"wall", MapPlacement.KIND_BLOCKER)

	assert_false(editor.set_placement_size(Vector2i(1, 1), Vector3(1.0, 0.0, 1.0)))
	assert_false(editor.set_placement_size(Vector2i(1, 1), Vector3(-2.0, 1.0, 1.0)))
	assert_eq(editor.placements_at(Vector2i(1, 1))[0].size, Vector3.ZERO, "it wrote anyway")


func test_scaling_an_empty_cell_is_refused_rather_than_crashing() -> void:
	var editor := EditorController.new()
	assert_false(editor.set_placement_size(Vector2i(7, 7), Vector3.ONE))


## The size goes through a verb, so it is undoable exactly as a placement is.
func test_an_authored_size_is_undoable() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(1, 1), &"wall", MapPlacement.KIND_BLOCKER)
	editor.set_placement_size(Vector2i(1, 1), Vector3(3.0, 2.4, 0.5))

	assert_true(editor.undo())

	assert_eq(editor.placements_at(Vector2i(1, 1))[0].size, Vector3.ZERO, "undo did not restore it")
