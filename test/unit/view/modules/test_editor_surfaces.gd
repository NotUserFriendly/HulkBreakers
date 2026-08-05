extends GutTest

## taskblock-57 Pass G2 — **the editor's own surfaces.**
##
## The taskblock's four, and how each is asserted:
##
## - **a coordinate readout replaces Unit Resources, same slot** — it declares the slot
##   `unit_resources` declares, and the editor mode has one and not the other.
## - **it tracks the cursor's cell and height** — driven through the real hover signal, read off the
##   real labels.
## - **section details where the Inspect viewer sits, with a toggle in UI buttons** — the panel
##   is in that slot and the toggle really folds it.
## - **validation warnings reach the log, the significant ones the announcement position** — one
##   authored pit, both surfaces, one emit.
## - **current tool on the cursor or the bar's own highlight** — the bar's highlight, and it follows
##   a tool set from anywhere.
##
## **Read the real nodes back.** The readout's text is asserted from the label the module built, not
## from a second call to the formatter; the fold is read off `panel.visible`, not off the flag.


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


func _coords(overlay: ControlOverlay) -> EditorCoordsModule:
	return overlay.module(&"editor_coords") as EditorCoordsModule


func _bar(overlay: ControlOverlay) -> EditorBarModule:
	return overlay.module(&"editor_bar") as EditorBarModule


# ---------------------------------------------------------------- same slot, different module


## **THE ACCEPTANCE for G2's first line.** *"A coordinate readout replaces Unit Resources in editor
## mode — same slot, different module."* Both halves: it wants the same slot, and the editor
## declares exactly one of the two.
func test_the_coordinate_readout_takes_the_slot_the_unit_resources_use() -> void:
	var coords := EditorCoordsModule.new()
	var resources := UnitResourcesModule.new()
	add_child_autofree(coords)
	add_child_autofree(resources)

	assert_eq(
		coords.preferred_slot(),
		resources.preferred_slot(),
		"they must want the same slot, or 'same slot, different module' is not what happened"
	)
	assert_true(ViewModes.editor().modules.has(&"editor_coords"), "the editor declares the readout")
	assert_false(
		ViewModes.editor().modules.has(&"unit_resources"),
		"the editor declares both -- two modules would be fighting for one slot"
	)
	assert_true(ViewModes.player().modules.has(&"unit_resources"), "and the player keeps the pips")
	assert_false(ViewModes.player().modules.has(&"editor_coords"))


## And it really lands there, in the bar's own published slot rather than anywhere sensible-looking.
func test_the_readout_mounts_into_the_editor_bars_published_slot() -> void:
	var overlay: ControlOverlay = _overlay()
	var bar: EditorBarModule = _bar(overlay)
	assert_true(
		bar.top_left_slot.is_ancestor_of(_coords(overlay).column),
		"the readout is not above the bar's left edge, so it would not move with the bar"
	)


# ---------------------------------------------------------------- it tracks the cursor


## **THE STATED TEST**: *"the coordinate readout tracks the cursor's cell and height."* Driven
## through the real `hovered_cell` signal — the one the board module emits from the ray it already
## casts — rather than by calling the readout's own setter, so the wiring is under test too.
func test_the_readout_tracks_the_cell_and_height_under_the_cursor() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var coords: EditorCoordsModule = _coords(overlay)
	editor.selected_part = &"ship_floor"
	editor.selected_kind = MapPlacement.KIND_SURFACE
	editor.active_tool = &"place"
	editor.controller.place(Vector2i(3, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 0.6)
	editor.refresh()

	var picking: BoardInspectModule = overlay.module(&"board_inspect") as BoardInspectModule
	picking.hovered_cell.emit(Vector2i(3, 2))

	gut.p("readout: '%s' / '%s'" % [coords.cell_label.text, coords.content_label.text])
	assert_true(coords.cell_label.text.contains("(3,2)"), "the cell is not what the cursor is over")
	assert_true(coords.cell_label.text.contains("0.6"), "the height is not the authored one")
	assert_eq(coords.content_label.text, "ship_floor", "it must name what is there")


## Off the board is blank, not the last cell it saw — a readout that keeps showing where the cursor
## used to be reads as a stuck cursor.
func test_leaving_the_board_blanks_the_readout_rather_than_freezing_it() -> void:
	var overlay: ControlOverlay = _overlay()
	var coords: EditorCoordsModule = _coords(overlay)
	var picking: BoardInspectModule = overlay.module(&"board_inspect") as BoardInspectModule

	picking.hovered_cell.emit(Vector2i(1, 1))
	assert_true(coords.cell_label.text.contains("(1,1)"), "sanity: it tracked the cell")
	picking.hovered_cell.emit(null)

	assert_eq(coords.cell_label.text, EditorCoordsModule.OFF_BOARD)
	assert_eq(coords.content_label.text, "")


## A bare cell is an answer, not a missing one. Same rule the AP/MP rows follow.
func test_an_empty_cell_reads_as_empty_rather_than_blank() -> void:
	var overlay: ControlOverlay = _overlay()
	var coords: EditorCoordsModule = _coords(overlay)
	(overlay.module(&"board_inspect") as BoardInspectModule).hovered_cell.emit(Vector2i(9, 9))
	assert_eq(coords.content_label.text, "empty")


## *"Detail is the inspector's job."* A long id is cut rather than pushing the bar's other surfaces
## sideways.
func test_a_long_part_name_is_truncated() -> void:
	var long_id := &"a_part_with_a_really_very_long_identifier"
	var shown: String = EditorCoordsModule.truncated(long_id)
	gut.p("'%s' -> '%s'" % [long_id, shown])
	assert_lt(shown.length(), String(long_id).length(), "it was not cut")
	assert_true(shown.ends_with("…"), "a cut name must say it was cut")
	assert_eq(EditorCoordsModule.truncated(&"barrel"), "barrel", "a short one is left alone")


# ---------------------------------------------------------------- section details, and its toggle


## **THE ACCEPTANCE for G2's second line.** *"Section details go where the Inspect Viewer sits,
## with a toggle in UI buttons."* The slot, and then the toggle — which cost a `preferred_slot()`
## and no code in `UiButtonsModule`, because the collapse rule derives the affordance from the slot.
func test_the_section_details_sit_in_the_viewer_slot_and_fold_from_the_ui_buttons() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var slot: Control = overlay.module_context.slots.get(ModuleSlots.INSPECT_VIEWER)

	assert_eq(editor.preferred_slot(), ModuleSlots.INSPECT_VIEWER)
	assert_not_null(slot, "the editor mode publishes an inspect-viewer slot")
	assert_true(slot.is_ancestor_of(editor.panel), "the details panel is somewhere else entirely")

	assert_true(buttons.toggles.has(&"editor"), "the details panel has no toggle to fold it")
	var toggle: CheckButton = buttons.toggles[&"editor"]
	assert_true(editor.panel.visible, "nothing is folded by default")
	toggle.button_pressed = false
	assert_false(editor.panel.visible, "the toggle did not actually hide it")
	toggle.button_pressed = true
	assert_true(editor.panel.visible, "and it comes back")


## **Folding the details must not disarm the editor.** The verbs are on the bar, so an author who
## folds the panel to see the board keeps authoring — which is the whole reason a details panel is
## the collapsible thing rather than the editor.
func test_folding_the_details_leaves_the_authoring_verbs_working() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	editor.collapsed = true

	editor.selected_part = &"ship_floor"
	editor.active_tool = &"place"

	assert_true(editor.apply_tool_at(Vector2i(1, 1)), "a folded panel stopped the board authoring")
	assert_eq(editor.controller.placements_at(Vector2i(1, 1)).size(), 1)


# ---------------------------------------------------------------- warnings, warned


## **THE STATED TEST**: *"a validation warning reaches the log and a significant one reaches the
## announcement position."* One authored pit produces both, from one emit — which is Pass E's own
## rule and the reason nothing here calls an announcement API.
func test_a_navigability_warning_reaches_the_log_and_the_announcement_position() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var announcements: AnnouncementsModule = overlay.module(&"announcements") as AnnouncementsModule
	var sink := MemorySink.new()
	overlay.battle.combat_state.combat_log.add_sink(sink)

	# A plateau with a hole in it: something can be walked into and not back out of.
	#
	# **The spawn marker is load-bearing, not decoration.** `navigability_warnings` floods from a
	# spawn, and says so in its own header: with no spawn there is nowhere to flood from and the
	# board reports nothing at all. The first version of this test omitted it and got an empty log,
	# which read as "the warnings never reach the log" rather than as "there was no warning".
	editor.controller.set_size(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			editor.controller.place(Vector2i(x, y), &"ship_floor", MapPlacement.KIND_SURFACE, 3.0)
	editor.controller.clear_cell(Vector2i(2, 2))
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 1.0)
	editor.controller.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	editor.refresh()

	var warnings: Array[LogEvent] = []
	for event: LogEvent in sink.events:
		if event.kind == EditorLog.WARNING:
			warnings.append(event)
	gut.p("logged: %s" % ", ".join(warnings.map(func(e: LogEvent) -> String: return e.text)))
	assert_false(warnings.is_empty(), "the author is not told anything in the log")

	var announced: Array[LogEvent] = warnings.filter(Announcement.tagged)
	# Returned rather than indexed past a failed assertion: reaching for `[0]` of an empty array
	# raises a Debugger Break, which ends the whole run and reports a mystery instead of the miss.
	if announced.is_empty():
		fail_test("a navigability warning must reach the announcement position")
		return
	assert_eq(Announcement.priority_of(announced[0]), Announcement.ALERT)
	assert_false(announcements.feed.active().is_empty(), "and the position is actually showing it")


## **Said once, not once per click.** `refresh()` runs after every edit against a list recomputed
## whole, so the same warning would otherwise land in the log on every placement.
##
## **A warning has to be introduced here, not assumed.** The empty board's own warnings are reported
## by the very first `refresh()`, which runs inside `_mount` — before any test can attach a sink.
## The first version of this counted zero and read that as "the log is never written to", when it
## was the dedup working on warnings said before anyone was listening.
func test_a_standing_warning_is_reported_once_rather_than_on_every_edit() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var sink := MemorySink.new()
	overlay.battle.combat_state.combat_log.add_sink(sink)

	# A pit, which is a warning this board did not have a moment ago.
	editor.controller.set_size(4, 4)
	for y: int in range(4):
		for x: int in range(4):
			editor.controller.place(Vector2i(x, y), &"ship_floor", MapPlacement.KIND_SURFACE, 3.0)
	editor.controller.clear_cell(Vector2i(2, 2))
	editor.controller.place(Vector2i(2, 2), &"ship_floor", MapPlacement.KIND_SURFACE, 1.0)
	editor.controller.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)

	editor.refresh()
	var after_first: int = _warning_count(sink)
	editor.refresh()
	editor.refresh()

	gut.p("warnings after one refresh: %d, after three: %d" % [after_first, _warning_count(sink)])
	assert_gt(after_first, 0, "sanity: the pit is a warning nobody had reported yet")
	assert_eq(_warning_count(sink), after_first, "the same warning was repeated on a redraw")


## And a warning that is fixed and reintroduced is new information the second time.
func test_a_warning_that_clears_and_returns_is_reported_again() -> void:
	var previous: Array[String] = ["no spawn markers"]
	assert_eq(EditorLog.arrived(previous, ["no spawn markers"]), [] as Array[String])
	assert_eq(EditorLog.arrived(previous, [] as Array[String]), [] as Array[String])
	assert_eq(
		EditorLog.arrived([] as Array[String], ["no spawn markers"]),
		["no spawn markers"] as Array[String],
		"a warning that came back is worth saying again"
	)


## *"Warn, never block"* is unchanged by the warnings being louder — F4's rule survives G2.
func test_warning_louder_still_does_not_gate_anything() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var bar: EditorBarModule = _bar(overlay)
	editor.refresh()
	assert_false(
		(bar.file_buttons["Run Test Bout"] as Button).disabled, "a warned board must still launch"
	)


func _warning_count(sink: MemorySink) -> int:
	var count: int = 0
	for event: LogEvent in sink.events:
		if event.kind == EditorLog.WARNING:
			count += 1
	return count


# ---------------------------------------------------------------- the current tool, shown


## **THE ACCEPTANCE for G2's last line.** *"Current tool shows on the cursor... or is carried by
## the action bar's own highlight. Either is fine; neither is not."* The bar's highlight is the
## option taken, so exactly one tool button is lit at a time.
func test_the_bar_highlights_the_current_tool() -> void:
	var overlay: ControlOverlay = _overlay()
	var editor: EditorModule = _editor(overlay)
	var bar: EditorBarModule = _bar(overlay)

	editor.active_tool = &"height"

	assert_eq((bar.tool_buttons[&"height"] as Button).modulate, HulkTheme.HIGHLIGHT)
	assert_ne(
		(bar.tool_buttons[&"remove"] as Button).modulate,
		HulkTheme.HIGHLIGHT,
		"two tools are lit at once -- the highlight says nothing"
	)


## **The `place` tool lights its own kind's button.** There is no "Place" button on this bar — the
## three kind buttons are what `place` is — so the lit one must be the kind the next click makes.
func test_placing_lights_the_kind_button_that_says_what_will_be_placed() -> void:
	var overlay: ControlOverlay = _overlay()
	var bar: EditorBarModule = _bar(overlay)

	(bar.kind_buttons[MapPlacement.KIND_SURFACE] as Button).pressed.emit()
	bar.list.chosen.emit(&"ship_floor")

	assert_eq((bar.kind_buttons[MapPlacement.KIND_SURFACE] as Button).modulate, HulkTheme.HIGHLIGHT)
	assert_ne((bar.kind_buttons[MapPlacement.KIND_BLOCKER] as Button).modulate, HulkTheme.HIGHLIGHT)

	# **Switching kind while the tool stays `place`** — the case the setter alone cannot catch,
	# because `active_tool` does not change and therefore emits nothing.
	(bar.kind_buttons[MapPlacement.KIND_BLOCKER] as Button).pressed.emit()
	bar.list.chosen.emit(&"ship_floor")

	assert_eq((bar.kind_buttons[MapPlacement.KIND_BLOCKER] as Button).modulate, HulkTheme.HIGHLIGHT)
	assert_ne(
		(bar.kind_buttons[MapPlacement.KIND_SURFACE] as Button).modulate,
		HulkTheme.HIGHLIGHT,
		"the highlight stayed on the previous kind -- it says what will NOT be placed"
	)


## The highlight is right the moment the bar exists, not only after the first press.
func test_the_default_tool_is_already_highlighted_before_anything_is_pressed() -> void:
	var overlay: ControlOverlay = _overlay()
	var bar: EditorBarModule = _bar(overlay)
	var editor: EditorModule = _editor(overlay)
	assert_eq(editor.active_tool, &"place", "sanity: a fresh editor places")
	assert_eq(
		(bar.kind_buttons[editor.selected_kind] as Button).modulate,
		HulkTheme.HIGHLIGHT,
		"nothing is lit until the author presses something"
	)
