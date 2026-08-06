extends GutTest

## **A cell can hold a column, and every editor verb addressed the cell.** taskblock-59 follow-up.
##
## > *"Clicking the side of a stacked ship_floor part places a ship_floor back at zero. Also means
## > clicking the bottom item in the stack instead deletes the top item."*
## > *"Cover items also don't land atop a set of stacked ship floors."*
## > *"Selecting the floor under a wall selects the wall. Scale does this as well."*
##
## Four symptoms, one cause. The author clicks a **thing**; the editor resolved that to a **cell**
## and then picked whichever of its contents a given verb happened to reach for — the whole stack's
## span for a placement, the last-authored for a delete, the topmost for the gizmo, the *first*
## walkable for a blocker's drawn height. The struck point is what tells them apart, and it comes
## from the same pick the struck normal already did.

const LOW := 0.0
const HIGH := 2.5


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


## Two floors in one cell: one on the deck, one at 2.5.
func _stacked(overlay: ControlOverlay) -> EditorModule:
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(8, 8)
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, LOW)
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, HIGH)
	editor.refresh()
	return editor


# ---------------------------------------------------------------- which one was struck


## **The model's own answer**, tested with no scene: a point inside the upper floor resolves to the
## upper floor.
func test_a_point_resolves_to_the_placement_containing_it() -> void:
	var editor := EditorController.new()
	editor.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, LOW)
	editor.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, HIGH)

	assert_almost_eq(
		editor.placement_at(Vector2i(2, 2), HIGH - 0.1).height, HIGH, 0.001, "the upper floor"
	)
	assert_almost_eq(
		editor.placement_at(Vector2i(2, 2), LOW - 0.1).height, LOW, 0.001, "the lower floor"
	)


# ---------------------------------------------------------------- placing


## *"Clicking the side of a stacked ship_floor places a ship_floor back at zero."* The span was the
## whole cell's, so the upper floor's side reported the bottom of the stack.
func test_the_side_of_the_upper_floor_places_level_with_the_upper_floor() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _stacked(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"ship_floor"
	editor.struck_normal = Vector3.RIGHT
	editor.struck_point = Vector3(2.0, HIGH - 0.1, 2.0)

	var target: Dictionary = editor.placement_target(Vector2i(2, 2))

	gut.p("target cell %s h %.2f" % [target["cell"], target["height"]])
	assert_eq(target["cell"], Vector2i(3, 2))
	assert_almost_eq(float(target["height"]), HIGH, 0.01, "it went back to the bottom of the stack")


## And the lower floor's side still answers the lower floor.
func test_the_side_of_the_lower_floor_places_level_with_the_lower_floor() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _stacked(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"ship_floor"
	editor.struck_normal = Vector3.RIGHT
	editor.struck_point = Vector3(2.0, LOW - 0.1, 2.0)

	var target: Dictionary = editor.placement_target(Vector2i(2, 2))

	assert_almost_eq(float(target["height"]), LOW, 0.01, "the lower floor was not what answered")


# ---------------------------------------------------------------- deleting


## *"Clicking the bottom item in the stack instead deletes the top item."* `remove_top` removes the
## last **authored**, which is the top of the column whatever the author clicked.
func test_deleting_removes_the_one_that_was_clicked() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _stacked(overlay)
	editor.active_tool = &"delete"
	editor.struck_point = Vector3(2.0, LOW - 0.1, 2.0)

	editor.apply_tool_at(Vector2i(2, 2))

	var left: Array[MapPlacement] = editor.controller.placements_at(Vector2i(2, 2))
	var heights: Array[float] = []
	for placement: MapPlacement in left:
		heights.append(placement.height)
	gut.p("left standing: %s" % str(heights))
	assert_eq(left.size(), 1, "one of the two should be gone")
	assert_almost_eq(left[0].height, HIGH, 0.001, "it deleted the top instead of the clicked one")


## With no struck point — a click that resolved off the ground plane — it still removes the top,
## which is the behaviour every caller had before.
func test_deleting_with_no_struck_point_still_removes_the_top() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _stacked(overlay)
	editor.active_tool = &"delete"
	editor.struck_point = null

	editor.apply_tool_at(Vector2i(2, 2))

	var left: Array[MapPlacement] = editor.controller.placements_at(Vector2i(2, 2))
	assert_eq(left.size(), 1)
	assert_almost_eq(left[0].height, LOW, 0.001, "the fallback should take the last authored")


# ---------------------------------------------------------------- selecting


## *"Selecting the floor under a wall selects the wall. Scale does this as well."*
func test_selecting_the_floor_under_a_wall_selects_the_floor() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(8, 8)
	editor.controller.place(Vector2i(2, 2), &"ship_floor")
	editor.controller.place(Vector2i(2, 2), &"wall", MapPlacement.KIND_BLOCKER)
	editor.refresh()
	var handles: GizmoModule = overlay.module(&"gizmo") as GizmoModule
	editor.active_tool = &"select"

	editor.struck_normal = Vector3.UP
	editor.struck_point = Vector3(2.0, -0.1, 2.0)
	editor.apply_tool_at(Vector2i(2, 2))
	editor.struck_point = null

	assert_not_null(handles.gizmo.focused_placement, "nothing was focused at all")
	gut.p("focused %s" % handles.gizmo.focused_placement.part_id)
	assert_eq(
		handles.gizmo.focused_placement.part_id, &"ship_floor", "it grabbed the wall over the floor"
	)


# ---------------------------------------------------------------- cover on a stack


## *"Cover items also don't land atop a set of stacked ship floors."* `BoardView` draws a blocker at
## `true_height_for_cell`, which is `Surface.first_walkable` — the **first authored**, so on a
## column that is the lowest. `MapPlacement.offset` carries the difference so no grid rule moves.
func test_cover_placed_on_the_upper_deck_is_offset_up_to_it() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _stacked(overlay)
	editor.active_tool = &"place_terrain"
	editor.selected_part = &"pillar"
	editor.struck_normal = Vector3.UP
	editor.struck_point = Vector3(2.0, HIGH - 0.1, 2.0)

	editor.apply_tool_at(Vector2i(2, 2))
	editor.struck_point = null

	var pillar: MapPlacement = null
	for placement: MapPlacement in editor.controller.placements_at(Vector2i(2, 2)):
		if placement.part_id == &"pillar":
			pillar = placement
	assert_not_null(pillar, "the pillar was not placed")
	var drawn: float = UnitGeometry.true_height_for_cell(
		Vector2i(2, 2), overlay.battle.board_view.grid
	)
	gut.p("grid draws the cell at %.2f, pillar offset %s" % [drawn, pillar.offset])
	assert_almost_eq(
		drawn + pillar.offset.y,
		HIGH,
		0.01,
		"the pillar does not stand on the deck that was clicked"
	)


## **And `first_walkable` is untouched**, which is what makes the offset the right lever: it is a
## documented grid rule the pathfinder reads, not something to change for an editor gesture.
func test_the_grid_rule_is_not_what_moved() -> void:
	var overlay: ControlOverlay = _overlay()
	_stacked(overlay)

	assert_almost_eq(
		UnitGeometry.true_height_for_cell(Vector2i(2, 2), overlay.battle.board_view.grid),
		LOW,
		0.001,
		"first_walkable stopped meaning the first authored surface"
	)
