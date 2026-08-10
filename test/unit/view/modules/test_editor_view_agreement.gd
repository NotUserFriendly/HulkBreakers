extends GutTest

## taskblock-59 Pass A — **the editor's model and its view never disagree about what exists.**
##
## Two reports arrived as separate defects and are one:
##
## > *"Clicking a support pillar on top of another support pillar makes an invisible pillar. Other
## > items trigger it too. After that, everything placed was invisible."*
##
## > *"`Delete` removes logically but not visually."*
##
## **A failed placement poisoning every later one is state corruption, not a rendering fault**, and
## the corruption had one site: `EditorModule._refresh_board` gave up silently whenever
## `MapSerializer.to_grid` refused the model. The model went on accepting edits and the view stayed
## frozen at the last board that built — so every later placement was invisible, and so was every
## later delete. `pillar` is a `KIND_BLOCKER` and `Grid.blockers` holds one part per cell, which is
## why a second one is the easy way to reach it.
##
## **The assertions read the view back rather than re-deriving it.** `BoardView.grid` is the board
## the view was *actually built from* and its `_static` child count is what it *actually drew*; a
## test that asked the controller twice would agree with itself and with nothing on screen.

const SAVED_MAP := "user://test_editor_view_agreement.tres"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()
	if FileAccess.file_exists(SAVED_MAP):
		DirAccess.remove_absolute(SAVED_MAP)


func _editor() -> EditorModule:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.editor())
	battle.set_overlay(overlay)
	return overlay.module(&"editor") as EditorModule


func _board_view(editor: EditorModule) -> BoardView:
	return editor.context.battle.board_view


## What the view is currently drawing at `cell`, as a sortable list of ids. Read off
## `BoardView.grid` — the grid `build()` was handed — never off the controller.
func _drawn_at(editor: EditorModule, cell: Vector2i) -> Array[StringName]:
	var grid: Grid = _board_view(editor).grid
	var found: Array[StringName] = []
	if grid == null:
		return found
	for surface: Surface in grid.surfaces_at(cell):
		found.append(surface.part.id)
	if grid.blockers.has(cell):
		found.append((grid.blocker_part_at(cell) as Part).id)
	for item: Variant in grid.field_items.get(cell, []):
		found.append((item as Part).id)
	found.sort()
	return found


## The same list, off the authoring model. The two must match, cell for cell.
func _modelled_at(editor: EditorModule, cell: Vector2i) -> Array[StringName]:
	var found: Array[StringName] = []
	for placement: MapPlacement in editor.controller.placements_at(cell):
		found.append(placement.part_id)
	found.sort()
	return found


func _place(editor: EditorModule, cell: Vector2i, part: StringName) -> bool:
	editor.active_tool = &"place_terrain"
	editor.selected_part = part
	return editor.apply_tool_at(cell)


# ---------------------------------------------------------------- the corruption


## **The reported gesture, and the assertion is on the placement AFTER it.**
##
## The pillar-on-a-pillar is only the trigger; what made the editor untrustworthy is that every
## later placement went into the model and never reached the screen. So the second pillar is allowed
## to resolve either way — what is not allowed is for it to cost the next click.
func test_a_refused_placement_does_not_cost_the_next_one() -> void:
	var editor: EditorModule = _editor()
	_place(editor, Vector2i(1, 1), &"ship_floor")
	assert_true(_place(editor, Vector2i(1, 1), &"pillar"), "sanity: the first pillar went down")

	_place(editor, Vector2i(1, 1), &"pillar")

	assert_true(_place(editor, Vector2i(3, 3), &"ship_floor"), "the next placement was refused")
	assert_has(
		_drawn_at(editor, Vector2i(3, 3)),
		&"ship_floor",
		"the placement after a rejected one never reached the board — the view is frozen"
	)


## The same claim stated as the invariant rather than as the symptom: whichever way a duplicate
## resolves, the model and the view agree about that cell afterwards.
func test_a_second_blocker_leaves_the_model_and_the_view_agreeing() -> void:
	var editor: EditorModule = _editor()
	_place(editor, Vector2i(1, 1), &"ship_floor")
	_place(editor, Vector2i(1, 1), &"pillar")

	_place(editor, Vector2i(1, 1), &"pillar")

	assert_eq(
		_modelled_at(editor, Vector2i(1, 1)),
		_drawn_at(editor, Vector2i(1, 1)),
		"the model holds something the board is not drawing"
	)


## **And the author is told.** A refusal the editor performs silently is a click that looks broken;
## `EditorLog.WARNING` is where every other authoring complaint already goes.
func test_a_refused_placement_says_so_in_the_combat_log() -> void:
	var editor: EditorModule = _editor()
	var state: CombatState = editor.context.battle.combat_state
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	_place(editor, Vector2i(1, 1), &"ship_floor")
	_place(editor, Vector2i(1, 1), &"pillar")

	_place(editor, Vector2i(1, 1), &"pillar")

	var told: Array[String] = []
	for event: LogEvent in sink.events:
		if event.kind == EditorLog.WARNING:
			told.append(event.text)
	gut.p("logged: %s" % ", ".join(told))
	assert_true(
		"".join(told).contains("blocker"), "the author gets no account of why the click did nothing"
	)


## **Every later placement, not just the next one.** The poisoning was permanent, so one recovered
## click is not evidence the state is clean.
func test_the_editor_keeps_working_for_the_rest_of_the_session() -> void:
	var editor: EditorModule = _editor()
	_place(editor, Vector2i(1, 1), &"ship_floor")
	_place(editor, Vector2i(1, 1), &"pillar")
	_place(editor, Vector2i(1, 1), &"pillar")

	for x: int in range(2, 6):
		_place(editor, Vector2i(x, 4), &"ship_floor")

	for x: int in range(2, 6):
		assert_eq(
			_modelled_at(editor, Vector2i(x, 4)),
			_drawn_at(editor, Vector2i(x, 4)),
			"cell %d,4 disagrees" % x
		)


# ---------------------------------------------------------------- delete


## *"`Delete` removes logically but not visually."* The other side of one disagreement — asserted
## against the real node count, because "the record is gone" is what was already true.
func test_deleting_removes_the_node_as_well_as_the_record() -> void:
	var editor: EditorModule = _editor()
	_place(editor, Vector2i(2, 2), &"ship_floor")
	_place(editor, Vector2i(2, 2), &"pillar")
	var drawn_before: int = _board_view(editor).get_child(0).get_child_count()

	editor.active_tool = &"delete"
	assert_true(editor.apply_tool_at(Vector2i(2, 2)), "delete reported nothing removed")

	assert_does_not_have(_modelled_at(editor, Vector2i(2, 2)), &"pillar", "the record survived")
	assert_does_not_have(_drawn_at(editor, Vector2i(2, 2)), &"pillar", "the board still draws it")
	assert_lt(
		_board_view(editor).get_child(0).get_child_count(),
		drawn_before,
		"nothing left the scene — the mesh is still standing where the pillar was"
	)


## Delete after a refusal, which is the sequence the report describes: an author who cannot see
## what they placed reaches for delete next.
func test_deleting_works_after_a_refused_placement() -> void:
	var editor: EditorModule = _editor()
	_place(editor, Vector2i(2, 2), &"ship_floor")
	_place(editor, Vector2i(2, 2), &"pillar")
	_place(editor, Vector2i(2, 2), &"pillar")

	editor.active_tool = &"delete"
	editor.apply_tool_at(Vector2i(2, 2))

	assert_eq(
		_modelled_at(editor, Vector2i(2, 2)),
		_drawn_at(editor, Vector2i(2, 2)),
		"the model and the board disagree after a delete that followed a refusal"
	)
	assert_does_not_have(_drawn_at(editor, Vector2i(2, 2)), &"pillar", "the pillar is still drawn")


# ---------------------------------------------------------------- the round trip


## A placement authored, saved, and reopened draws the same thing. The disagreement has one more
## direction to fail in — a board that is right on screen and wrong on disk.
func test_a_placement_round_trips_to_a_saved_map_with_the_same_visible_result() -> void:
	var editor: EditorModule = _editor()
	editor.controller.set_size(4, 4)
	_place(editor, Vector2i(1, 1), &"ship_floor")
	_place(editor, Vector2i(2, 1), &"ship_floor")
	_place(editor, Vector2i(2, 1), &"pillar")
	editor.panel.name_field.text = SAVED_MAP
	assert_eq(editor.save_as_map()["error"], "", "it wrote")

	var reopened: EditorModule = _editor()
	assert_eq(reopened.open(SAVED_MAP)["error"], "")

	for cell: Vector2i in [Vector2i(1, 1), Vector2i(2, 1)]:
		assert_eq(
			_drawn_at(reopened, cell),
			_drawn_at(editor, cell),
			"%s came back looking different" % cell
		)
		assert_eq(_modelled_at(reopened, cell), _drawn_at(reopened, cell), "%s disagrees" % cell)


# ---------------------------------------------------------------- the general case


## **The freeze had a class, not an instance.** A board resized smaller keeps its out-of-bounds
## placements on purpose (`EditorController.set_size`), and that is a second way to hand the
## serializer a model it refuses. The view must still show everything that CAN be drawn.
func test_a_placement_outside_the_board_does_not_stop_the_rest_being_drawn() -> void:
	var editor: EditorModule = _editor()
	_place(editor, Vector2i(1, 1), &"ship_floor")
	_place(editor, Vector2i(9, 9), &"ship_floor")

	editor.controller.set_size(4, 4)
	editor.refresh()

	assert_has(
		_drawn_at(editor, Vector2i(1, 1)),
		&"ship_floor",
		"one out-of-bounds placement took the whole board off the screen"
	)
	var warnings: String = "".join(editor.controller.warnings())
	gut.p("warnings: %s" % warnings)
	assert_true(warnings.contains("outside"), "and the one that was dropped is named")
