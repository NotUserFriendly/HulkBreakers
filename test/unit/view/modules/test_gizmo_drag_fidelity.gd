extends GutTest

## **A drag is a pure function of where it started and where the pointer is now.**
##
## `Gizmo.value_at`'s own note states the rule: *"the drag is a pure function of these two and the
## current pointer, never an accumulation of per-frame deltas."* `value_at` obeys it. The two
## callers that apply `amount_at` did not — they added a delta measured **from the drag start** to
## the **current** value, so every mouse-motion event re-applied the whole drag.
##
## Reported as *"the scale handles move independently of the mouse cursor, flying off huge with the
## smallest movement"*, which is what that looks like from the outside. The claim path had the same
## defect and no report against it.
##
## **And a move must redraw the board**, not just the handles.


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


## A wall at (3,3) with `tool` armed on it.
func _armed(overlay: ControlOverlay, tool: StringName) -> EditorModule:
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(8, 8)
	editor.controller.place(Vector2i(3, 3), &"ship_floor")
	editor.controller.place(Vector2i(3, 3), &"wall", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	editor.active_tool = tool
	editor.struck_normal = Vector3.UP
	editor.apply_tool_at(Vector2i(3, 3))
	return editor


func _wall(editor: EditorModule) -> MapPlacement:
	for placement: MapPlacement in editor.controller.placements_at(Vector2i(3, 3)):
		if placement.part_id == &"wall":
			return placement
	return null


# ---------------------------------------------------------------- the drag tracks the pointer


## **The acceptance**: reaching a pointer position in two steps lands where reaching it in one does.
## Anything else means the drag is accumulating.
func test_a_scale_drag_lands_the_same_whether_it_took_one_step_or_two() -> void:
	var one: ControlOverlay = _overlay()
	var editor_one: EditorModule = _armed(one, &"scale")
	var handles_one: GizmoModule = one.module(&"gizmo") as GizmoModule
	handles_one.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles_one._drag_placement_size(editor_one, Vector2(400.0, 340.0), Vector2(0.0, -60.0))
	var in_one_step: Vector3 = _wall(editor_one).size

	var two: ControlOverlay = _overlay()
	var editor_two: EditorModule = _armed(two, &"scale")
	var handles_two: GizmoModule = two.module(&"gizmo") as GizmoModule
	handles_two.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles_two._drag_placement_size(editor_two, Vector2(400.0, 370.0), Vector2(0.0, -60.0))
	handles_two._drag_placement_size(editor_two, Vector2(400.0, 340.0), Vector2(0.0, -60.0))
	var in_two_steps: Vector3 = _wall(editor_two).size

	gut.p("one step %s, two steps %s" % [in_one_step, in_two_steps])
	assert_almost_eq(
		in_two_steps.y,
		in_one_step.y,
		0.0001,
		"the second motion event re-applied the whole drag — the handle has left the cursor"
	)


## And holding still changes nothing, which is the same property at its cheapest.
func test_a_scale_drag_that_does_not_move_does_not_grow() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _armed(overlay, &"scale")
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles._drag_placement_size(editor, Vector2(400.0, 340.0), Vector2(0.0, -60.0))
	var after_one: Vector3 = _wall(editor).size

	for i: int in range(5):
		handles._drag_placement_size(editor, Vector2(400.0, 340.0), Vector2(0.0, -60.0))

	gut.p("after 1 event %s, after 6 at the same point %s" % [after_one, _wall(editor).size])
	assert_almost_eq(
		_wall(editor).size.y, after_one.y, 0.0001, "a stationary pointer grew the placement"
	)


## The claim path had the identical defect and no report against it.
func test_a_claim_drag_lands_the_same_whether_it_took_one_step_or_two() -> void:
	var one: ControlOverlay = _overlay()
	var editor_one: EditorModule = one.module(&"editor") as EditorModule
	editor_one.controller.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3.ZERO, Vector3.ONE))
	var handles_one: GizmoModule = one.module(&"gizmo") as GizmoModule
	handles_one.gizmo.focus_claim(0)
	handles_one.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles_one._drag_claim(editor_one, Vector2(400.0, 340.0), Vector2(0.0, -60.0))
	var in_one_step: float = editor_one.controller.claims[0].box.center.y

	var two: ControlOverlay = _overlay()
	var editor_two: EditorModule = two.module(&"editor") as EditorModule
	editor_two.controller.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3.ZERO, Vector3.ONE))
	var handles_two: GizmoModule = two.module(&"gizmo") as GizmoModule
	handles_two.gizmo.focus_claim(0)
	handles_two.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles_two._drag_claim(editor_two, Vector2(400.0, 370.0), Vector2(0.0, -60.0))
	handles_two._drag_claim(editor_two, Vector2(400.0, 340.0), Vector2(0.0, -60.0))
	var in_two_steps: float = editor_two.controller.claims[0].box.center.y

	gut.p("claim centre: one step %.3f, two steps %.3f" % [in_one_step, in_two_steps])
	assert_almost_eq(in_two_steps, in_one_step, 0.0001, "the claim drag accumulates too")


# ---------------------------------------------------------------- the move redraws the board


## *"Moving an item doesn't update the visual until something else happens."* The translate branch
## wrote the height and redrew the **handles**, never the board — `_drag_claim` refreshes and this
## did not.
func test_moving_a_placement_redraws_the_board_immediately() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _armed(overlay, &"select")
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	var before: float = UnitGeometry.true_height_for_cell(
		Vector2i(3, 3), overlay.battle.board_view.grid
	)

	handles.begin_drag(Gizmo.AXIS_Y, 1.0, Vector2(400.0, 400.0))
	handles._drag_to(Vector2(400.0, 340.0))

	# **The wall, not the floor** — the gizmo focuses the topmost placement, and taskblock-59's
	# follow-up made the drag write to that one instead of to the top surface under it.
	var here: Array[MapPlacement] = editor.controller.placements_at(Vector2i(3, 3))
	var authored: float = here[here.size() - 1].offset.y
	var drawn: Array[MeshInstance3D] = overlay.battle.board_view.ghosting.meshes_at(Vector2i(3, 3))
	gut.p(
		"wall offset %.2f, board meshes %d (floor was at %.2f)" % [authored, drawn.size(), before]
	)
	assert_ne(authored, 0.0, "sanity: the drag moved the wall")
	assert_false(drawn.is_empty(), "sanity: the wall is drawn")
	# The board is rebuilt from the model on every edit, so a mesh that reflects the new offset is
	# the proof the redraw happened — the old code left the previous board standing entirely.
	assert_almost_eq(
		(drawn[0] as MeshInstance3D).transform.origin.y,
		authored + 1.2,
		0.01,
		"the board is still drawing the wall where it used to be"
	)
