extends GutTest

## taskblock-57 Pass H — **the gizmo on a real surface, and the block's own acceptance.**
##
## *"A height is authored by dragging an arrow to 0.3."*
##
## `test_gizmo.gd` proves the arithmetic and the state machine with no scene at all; this proves the
## two things only a view can answer, and the one thing neither can answer alone:
##
## - the handles are pickable **against the live camera**, and `axis_on_screen` comes off a real
##   projection rather than a second copy of one;
## - a press that grabs a handle is **consumed**, so it does not also author on the cell underneath;
## - a drag really reaches `EditorController` and really changes the authored board.
##
## **Read the real nodes back.** The drag is driven with real `InputEvent`s through the real host
## routing, and the result is read off the controller — not off the gizmo's own idea of the value.


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


func _gizmo(overlay: ControlOverlay) -> GizmoModule:
	return overlay.module(&"gizmo") as GizmoModule


## A board with something on it, and the gizmo tool armed.
func _authored(overlay: ControlOverlay) -> EditorModule:
	var editor: EditorModule = _editor(overlay)
	editor.selected_part = &"ship_floor"
	editor.selected_kind = MapPlacement.KIND_SURFACE
	editor.active_tool = &"place_terrain"
	for y: int in range(3):
		for x: int in range(3):
			editor.apply_tool_at(Vector2i(x, y))
	editor.active_tool = GizmoModule.TOOL
	return editor


## A press or release at `at`, routed the way the engine routes one.
func _press(overlay: ControlOverlay, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	overlay._unhandled_input(event)


func _move(overlay: ControlOverlay, to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	overlay._unhandled_input(event)


# ---------------------------------------------------------------- armed by a tool, not by a click


## **The gizmo is a tool over a click the one router already resolved.** With any other tool active
## a board click authors as it always did and the gizmo never hears about it — which is the concrete
## meaning of *"do not let this become a second selection system"*.
func test_a_click_with_another_tool_active_does_not_focus_the_gizmo() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	editor.active_tool = &"delete"

	editor.apply_tool_at(Vector2i(1, 1))

	assert_false(_gizmo(overlay).gizmo.has_subject(), "an authoring click focused the gizmo")


func test_the_gizmo_tool_focuses_the_placement_that_was_clicked() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)

	assert_true(editor.apply_tool_at(Vector2i(1, 1)), "the router must answer the gizmo tool")

	var gizmo: Gizmo = _gizmo(overlay).gizmo
	assert_eq(gizmo.subject, Gizmo.SUBJECT_PLACEMENT)
	assert_eq(gizmo.cell, Vector2i(1, 1))
	assert_eq(_gizmo(overlay).meshes.size(), 3, "three arrows are drawn")


## *"A click elsewhere deselects."* A cell with nothing on it clears the gizmo and takes its handles
## with it.
func test_clicking_a_cell_with_nothing_on_it_clears_the_gizmo() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	editor.apply_tool_at(Vector2i(1, 1))
	assert_true(_gizmo(overlay).gizmo.has_subject(), "sanity: something is focused")

	editor.apply_tool_at(Vector2i(9, 9))

	assert_false(_gizmo(overlay).gizmo.has_subject())
	assert_eq(_gizmo(overlay).meshes.size(), 0, "the handles must go with the subject")


## A claim under the click wins over the placement beneath it — it is the volume drawn over that
## point and the thing an author is pointing at.
func test_a_claim_over_the_cell_is_what_gets_focused() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	editor.controller.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3(1, 1, 1), Vector3.ONE))

	editor.apply_tool_at(Vector2i(1, 1))

	var gizmo: Gizmo = _gizmo(overlay).gizmo
	assert_eq(gizmo.subject, Gizmo.SUBJECT_CLAIM)
	assert_eq(gizmo.claim_index, 0)
	assert_eq(gizmo.handles, Gizmo.Handles.TRANSLATE)


## **The two handle sets, end to end, and which one you get is which tool you armed.**
##
## taskblock-58 Pass D: this used to assert that a *second click on the same claim* swapped the
## sets. That is what changed — arming `Select` or `Scale` says which handles you want up front,
## because they are different intentions and a mode you enter by clicking twice is one you leave by
## accident. **Clicking again with the same tool armed now leaves the handles alone**, which is the
## half worth pinning: the swap is gone rather than merely relocated.
func test_which_handles_are_drawn_is_which_tool_is_armed() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	editor.controller.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3(1, 1, 1), Vector3.ONE))

	editor.apply_tool_at(Vector2i(1, 1))
	assert_eq(_gizmo(overlay).gizmo.handles, Gizmo.Handles.TRANSLATE)
	assert_eq(_gizmo(overlay).meshes.size(), 3, "translate arrows under Select")

	editor.apply_tool_at(Vector2i(1, 1))
	assert_eq(
		_gizmo(overlay).gizmo.handles,
		Gizmo.Handles.TRANSLATE,
		"a second click with the same tool armed must not swap the set underneath the author"
	)

	editor.active_tool = GizmoModule.TOOL_SCALE
	editor.apply_tool_at(Vector2i(1, 1))

	assert_eq(_gizmo(overlay).gizmo.handles, Gizmo.Handles.RESIZE)
	assert_eq(_gizmo(overlay).meshes.size(), 6, "one handle per face under Scale")


# ---------------------------------------------------------------- the drag, against a real camera


## **THE ACCEPTANCE**: *"a height is authored by dragging an arrow to 0.3."*
##
## Driven through the real host input routing, the real camera's projection and the real
## `EditorController` — the value is read back off the authored placement, not off the gizmo.
##
## The pointer movement is computed from `axis_on_screen`, which is what the module reads off the
## camera; **that is the point rather than a shortcut.** A test that hard-coded a pixel count would
## be asserting against whatever the camera happened to be doing that day, and would pass or fail on
## the framing rather than on the drag.
func test_dragging_the_up_arrow_authors_a_height_of_zero_point_three() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	await get_tree().process_frame
	editor.apply_tool_at(Vector2i(1, 1))
	var handles: GizmoModule = _gizmo(overlay)

	var up: Vector2 = handles.axis_on_screen(Gizmo.AXIS_Y)
	gut.p("one world unit up covers %v on screen" % up)
	assert_gt(up.length(), 1.0, "sanity: the up axis is not edge-on to the camera")

	# Where the Y arm actually is on screen, so the press really strikes it.
	var camera: Camera3D = overlay.battle.camera_rig.camera()
	var grab: Vector2 = camera.unproject_position(
		handles.gizmo_origin() + Vector3.UP * (Gizmo.ARM_LENGTH * 0.5)
	)

	_press(overlay, grab, true)
	assert_true(handles.gizmo.is_dragging(), "the press did not grab the up arrow")
	_move(overlay, grab + up * 0.3)
	_press(overlay, grab + up * 0.3, false)

	var placed: Array[MapPlacement] = editor.controller.placements_at(Vector2i(1, 1))
	gut.p("authored height: %.4f" % placed[0].height)
	assert_almost_eq(placed[0].height, 0.3, 0.0001, "the drag did not author 0.3")
	assert_eq(handles.readout.text, "0.3", "and the readout must say what was authored")


## **A press that grabs a handle is consumed.** Otherwise the same press reaches the board picker
## and authors on the cell under the arrow, which is a placement nobody asked for every time the
## gizmo is used.
func test_grabbing_a_handle_consumes_the_press() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	await get_tree().process_frame
	editor.apply_tool_at(Vector2i(1, 1))
	var handles: GizmoModule = _gizmo(overlay)
	var camera: Camera3D = overlay.battle.camera_rig.camera()
	var grab: Vector2 = camera.unproject_position(
		handles.gizmo_origin() + Vector3.UP * (Gizmo.ARM_LENGTH * 0.5)
	)

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = grab

	assert_true(handles.handle_input(event), "a grab must consume the press")
	assert_false(
		(overlay.module(&"board_inspect") as BoardInspectModule).handle_input(event),
		"and the board picker must never claim exclusivity, so ordering is what decides"
	)


## **A press that misses every handle is not consumed**, so an ordinary authoring click still gets
## through. Consuming defensively is how a surface becomes unclickable in a way that reads as the
## board being broken.
func test_a_press_that_misses_every_handle_falls_through() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	await get_tree().process_frame
	editor.apply_tool_at(Vector2i(1, 1))

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(4.0, 4.0)

	assert_false(_gizmo(overlay).handle_input(event), "a miss must not swallow the click")


## And a gizmo with nothing focused never consumes anything at all.
func test_an_unfocused_gizmo_consumes_nothing() -> void:
	var overlay: ControlOverlay = _overlay()
	_authored(overlay)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(500.0, 500.0)

	assert_false(_gizmo(overlay).handle_input(event))


## **THE STATED TEST**: *"the gizmo never changes what is selected."* A whole drag runs, the height
## changes, and nothing about *what is chosen* moves — same cell focused, same claim count, same
## number of placements, same tool.
func test_a_drag_changes_a_value_and_nothing_about_what_is_chosen() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	await get_tree().process_frame
	editor.apply_tool_at(Vector2i(1, 1))
	var handles: GizmoModule = _gizmo(overlay)
	var before_placements: int = editor.controller.placements.size()
	var camera: Camera3D = overlay.battle.camera_rig.camera()
	var grab: Vector2 = camera.unproject_position(
		handles.gizmo_origin() + Vector3.UP * (Gizmo.ARM_LENGTH * 0.5)
	)

	_press(overlay, grab, true)
	_move(overlay, grab + handles.axis_on_screen(Gizmo.AXIS_Y) * 0.5)
	_press(overlay, grab + handles.axis_on_screen(Gizmo.AXIS_Y) * 0.5, false)

	assert_eq(handles.gizmo.cell, Vector2i(1, 1), "the drag moved what was focused")
	assert_eq(editor.controller.placements.size(), before_placements, "it added or removed one")
	assert_eq(editor.last_cell, Vector2i(1, 1), "it changed the editor's own idea of the cell")
	assert_eq(editor.active_tool, GizmoModule.TOOL, "it changed the tool")


## **Resizing a claim through the real handles, and the refusal.** A drag that would collapse the
## volume leaves the claim exactly as it was rather than clamping it to a sliver.
func test_a_resize_that_would_collapse_the_claim_leaves_it_untouched() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _authored(overlay)
	editor.controller.add_claim(SectionClaim.KIND_INTERIOR, Box.new(Vector3(1, 1, 1), Vector3.ONE))
	# Two clicks: focus, then swap to the resize handles.
	editor.apply_tool_at(Vector2i(1, 1))
	editor.apply_tool_at(Vector2i(1, 1))
	await get_tree().process_frame
	var handles: GizmoModule = _gizmo(overlay)
	var before: Vector3 = editor.controller.claims[0].box.size

	# Grab the top face and drag it far below the bottom one.
	handles.gizmo.begin_drag(Gizmo.AXIS_Y, 1.0, before.y, Vector2(500.0, 500.0))
	var up: Vector2 = handles.axis_on_screen(Gizmo.AXIS_Y)
	handles._drag_to(Vector2(500.0, 500.0) - up * 5.0)

	gut.p("claim size %v -> %v" % [before, editor.controller.claims[0].box.size])
	assert_eq(
		editor.controller.claims[0].box.size,
		before,
		"an impossible resize must be refused, not clamped to something small"
	)
