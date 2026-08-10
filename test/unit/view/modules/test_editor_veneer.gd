extends GutTest

## taskblock-59 Pass D — **the ledge veneer is placeable from a click.**
##
## `LedgeVeneer` computed the span, `ledge_veneer` was an authored part tagged terrain, and the hp
## followed volume — all landed in taskblock-58 Pass F. **Nothing called it from a click**, so a
## veneer could not be put on a board without hand-authoring a `.tres`. Same class as the rest of
## this block: the capability existed and the reach did not.

const VENEER := &"ledge_veneer"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _editor() -> EditorModule:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.controller.set_size(8, 8)
	return editor


## Clicks `cell` with the veneer armed and `normal` as the struck face.
func _place_veneer(editor: EditorModule, cell: Vector2i, normal: Variant) -> MapPlacement:
	editor.active_tool = &"place_terrain"
	editor.selected_part = VENEER
	editor.struck_normal = normal
	editor.apply_tool_at(cell)
	editor.struck_normal = null
	for placement: MapPlacement in editor.controller.placements:
		if placement.part_id == VENEER:
			return placement
	return null


# ---------------------------------------------------------------- growing down


## *"Click a ledge's side and it grows down; it snaps to what it meets."* A raised tile at 2.5 with
## a deck at 0.0 under the landing cell gives a veneer that spans exactly between them.
func test_a_click_on_a_ledge_side_snaps_down_to_what_it_meets() -> void:
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(3, 3), &"ship_floor", MapPlacement.KIND_SURFACE, 2.5)
	editor.controller.place(Vector2i(3, 4), &"ship_floor", MapPlacement.KIND_SURFACE, 0.0)
	editor.refresh()

	var veneer: MapPlacement = _place_veneer(editor, Vector2i(3, 3), Vector3.BACK)

	assert_not_null(veneer, "the click authored no veneer at all")
	gut.p("veneer at %s h=%.2f size=%s" % [veneer.cell, veneer.height, veneer.size])
	assert_eq(veneer.cell, Vector2i(3, 4), "a side face lands in the cell the normal points into")
	assert_almost_eq(veneer.height, 0.0, 0.001, "it should have snapped down to the deck")
	assert_almost_eq(veneer.size.y, 2.5, 0.001, "and spanned the whole rise")


## *"Between two floors it snaps to both."* Which is not a third case — it is what growing down does
## when it finds something, and this pins that it really does.
func test_a_veneer_between_two_floors_spans_exactly_between_them() -> void:
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 3.0)
	editor.controller.place(Vector2i(2, 3), &"ship_floor", MapPlacement.KIND_SURFACE, 1.0)
	editor.refresh()

	var veneer: MapPlacement = _place_veneer(editor, Vector2i(2, 2), Vector3.BACK)

	gut.p("veneer h=%.2f size.y=%.2f" % [veneer.height, veneer.size.y])
	assert_almost_eq(veneer.height, 1.0, 0.001, "the bottom is the lower deck")
	assert_almost_eq(veneer.size.y, 2.0, 0.001, "and the rise is the gap between them")


## *"On the side of a tile with nothing under it, match the picked floor tile's own height."*
func test_a_veneer_with_nothing_under_it_falls_to_the_deck() -> void:
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(5, 5), &"ship_floor", MapPlacement.KIND_SURFACE, 1.8)
	editor.refresh()

	var veneer: MapPlacement = _place_veneer(editor, Vector2i(5, 5), Vector3.BACK)

	gut.p("veneer h=%.2f size.y=%.2f" % [veneer.height, veneer.size.y])
	assert_almost_eq(veneer.height, LedgeVeneer.DECK_HEIGHT, 0.001)
	assert_almost_eq(veneer.size.y, 1.8, 0.001, "its height is the tile's own")


# ---------------------------------------------------------------- growing up


## *"Growing up from an edge, 0.8 — deliberately odd so it reads as a default rather than as
## intent."* A top face is what says grow up.
func test_a_top_face_with_nothing_above_takes_the_odd_default() -> void:
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(4, 4), &"ship_floor", MapPlacement.KIND_SURFACE, 0.0)
	editor.refresh()

	var veneer: MapPlacement = _place_veneer(editor, Vector2i(4, 4), Vector3.UP)

	gut.p("veneer h=%.2f size.y=%.2f" % [veneer.height, veneer.size.y])
	assert_almost_eq(veneer.size.y, LedgeVeneer.UNANCHORED_RISE, 0.001)
	assert_eq(veneer.cell, Vector2i(4, 4), "a top face stays on the cell it was struck on")


## **A finding, pinned rather than papered over: growing up can never snap to anything.**
##
## `LedgeVeneer.span_up` handles an anchor above and taskblock-58 tested it — but *through a click*
## it is unreachable. A top-face pick strikes the top of whatever is at that cell **by definition**,
## and the placement lands on that same cell, so "the nearest surface strictly above the face you
## just struck" is empty every time. Growing up therefore always takes `UNANCHORED_RISE`.
##
## **That is the gesture's limit, not the rule's**, and it is the honest reading of *"it grows both
## ways and snaps to what it meets"*: growing **down** meets things (the deck under the landing
## cell) and does snap — the tests above show it spanning 2.5 and 2.0 exactly. Growing up has
## nothing between the top of a stack and the sky.
##
## Left as it is rather than invented around: reaching the anchored-up case wants a pick that
## reports *which* surface of a stack was struck rather than the stack's own top, and that is a
## picking change with its own consequences.
func test_growing_up_always_takes_the_default_because_nothing_is_ever_above() -> void:
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(4, 4), &"ship_floor", MapPlacement.KIND_SURFACE, 0.0)
	editor.controller.place(Vector2i(4, 4), &"ship_floor", MapPlacement.KIND_SURFACE, 2.2)
	editor.refresh()

	var veneer: MapPlacement = _place_veneer(editor, Vector2i(4, 4), Vector3.UP)

	gut.p("veneer h=%.2f size.y=%.2f" % [veneer.height, veneer.size.y])
	assert_almost_eq(veneer.height, 2.2, 0.001, "it grew from the top of the stack, as a pick does")
	assert_almost_eq(
		veneer.size.y,
		LedgeVeneer.UNANCHORED_RISE,
		0.001,
		"nothing can be above the face a top-face pick struck"
	)


## And the rule itself does snap up — which is what makes the case above a limit of the gesture
## rather than a hole in the logic.
func test_the_rule_snaps_up_when_it_is_given_something_above() -> void:
	var span: Dictionary = LedgeVeneer.span_among([0.0, 2.2] as Array[float], 0.0, true)
	gut.p("span %s" % span)
	assert_almost_eq(span["height"], 2.2, 0.001, "the rule can snap up; only the click cannot")


# ---------------------------------------------------------------- what follows from it


## The hp follows the rise, through the resolver that already owned it — a tall deck face is
## genuinely tougher than a low kerb without either being authored.
func test_a_taller_veneer_is_tougher_on_the_board_that_gets_built() -> void:
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(1, 1), &"ship_floor", MapPlacement.KIND_SURFACE, 3.0)
	editor.controller.place(Vector2i(6, 6), &"ship_floor", MapPlacement.KIND_SURFACE, 1.0)
	editor.refresh()
	_place_veneer(editor, Vector2i(1, 1), Vector3.BACK)
	_place_veneer(editor, Vector2i(6, 6), Vector3.BACK)
	editor.refresh()

	var grid: Grid = editor.context.battle.board_view.grid
	var tall: int = (grid.blocker_part_at(Vector2i(1, 2)) as Part).max_hp
	var short: int = (grid.blocker_part_at(Vector2i(6, 7)) as Part).max_hp
	gut.p("a 3.0 veneer has %d hp, a 1.0 veneer %d" % [tall, short])
	assert_gt(tall, short, "the rise did not reach the hp")


## And it round-trips, because the rise is carried as an ordinary `MapPlacement.size`.
func test_the_grown_veneer_survives_a_save_and_load() -> void:
	var path := "user://test_editor_veneer.tres"
	var editor: EditorModule = _editor()
	editor.controller.place(Vector2i(3, 3), &"ship_floor", MapPlacement.KIND_SURFACE, 2.5)
	editor.refresh()
	_place_veneer(editor, Vector2i(3, 3), Vector3.BACK)
	editor.panel.name_field.text = path
	assert_eq(editor.save_as_map()["error"], "", "it wrote")

	var reopened: EditorModule = _editor()
	assert_eq(reopened.open(path)["error"], "")

	var loaded: MapPlacement = null
	for placement: MapPlacement in reopened.controller.placements:
		if placement.part_id == VENEER:
			loaded = placement
	assert_not_null(loaded, "the veneer did not come back")
	assert_almost_eq(loaded.size.y, 2.5, 0.001, "and it came back a different height")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## The direction is the struck normal's, which is the one thing the click decides.
func test_the_struck_face_is_what_chooses_the_direction() -> void:
	assert_true(LedgeVeneer.grows_up(Vector3.UP), "a top face grows up")
	assert_false(LedgeVeneer.grows_up(Vector3.BACK), "a side face grows down")
	assert_false(LedgeVeneer.grows_up(Vector3.DOWN))
	assert_true(LedgeVeneer.grows_up(null), "no face at all takes the gesture that has a default")
