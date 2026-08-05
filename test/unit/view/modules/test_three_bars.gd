extends GutTest

## taskblock-57 Pass G1 — **three action bars, not one with three contents.**
##
## The taskblock's stated test is *"each mode mounts its own action bar module"*, and that sentence
## has two halves that fail independently:
##
## 1. **Three modules.** A single bar branching on the mode would satisfy "the player sees squares
##    and the editor sees buttons" and would be the exact failure the pass title names.
## 2. **One slot.** Three bars that each anchored themselves somewhere would satisfy "three modules"
##    and would mean the placement table has three answers for one row.
##
## So the central test asserts both at once: the three are distinct classes, and all three resolve
## `ACTION_ROW` and publish the same four satellite names.
##
## **Positions are read off real nodes**, never recomputed — CLAUDE.md's rule, and the reason the
## player-bar shape test measures the boxes' own global rects rather than dividing `SLOT_COUNT` by
## `BOX_ROWS` a second time.

## Which module each mode's bar is. The table under test; a mode gaining a bar of its own belongs
## here the day it does.
const BARS: Dictionary = {
	&"player": &"action_bar",
	&"spectator": &"spectator_bar",
	&"editor": &"editor_bar",
}


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _battle() -> BattleScene:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	# `_ready()` installs the player mode; a bare surface neutralises it so nothing drives a turn
	# out from under the mode under test.
	battle.set_overlay(ControlOverlay.new())
	return battle


func _mount(mode: ViewMode) -> ControlOverlay:
	var battle: BattleScene = _battle()
	var overlay: ControlOverlay = ControlOverlay.for_mode(mode)
	battle.set_overlay(overlay)
	return overlay


func _bar_of(overlay: ControlOverlay) -> BarModule:
	for mounted: ViewModule in overlay.modules:
		if mounted is BarModule:
			return mounted as BarModule
	return null


# ---------------------------------------------------------------- the acceptance


## **THE ACCEPTANCE.** Each of the three modes mounts its own bar module, and the three are three
## different classes rather than one class reading which mode it is in.
func test_each_mode_mounts_its_own_bar_module() -> void:
	var classes: Array[String] = []
	for mode_id: StringName in BARS:
		var overlay: ControlOverlay = _mount(ViewModes.by_id(mode_id))
		var bar: ViewModule = overlay.module(BARS[mode_id])
		assert_not_null(bar, "the %s mode declares no bar" % mode_id)
		assert_true(bar is BarModule, "%s is not a bar" % BARS[mode_id])
		classes.append(bar.get_script().resource_path)
	gut.p("bar scripts: %s" % ", ".join(classes))
	assert_eq(
		classes.size(),
		[classes[0], classes[1], classes[2]].size(),
		"sanity: one script recorded per mode"
	)
	for i: int in range(classes.size()):
		for j: int in range(i + 1, classes.size()):
			assert_ne(
				classes[i],
				classes[j],
				"two modes share one bar script -- that is one bar with two contents"
			)


## **One slot, three occupants.** The other half of the claim: they are shaped differently and they
## are in the same place, which is what makes the placement table have one action-bar row.
func test_all_three_bars_occupy_the_one_action_row_slot() -> void:
	for mode_id: StringName in BARS:
		var overlay: ControlOverlay = _mount(ViewModes.by_id(mode_id))
		var bar: BarModule = overlay.module(BARS[mode_id]) as BarModule
		assert_eq(bar.preferred_slot(), ModuleSlots.ACTION_ROW, "%s wants its own place" % mode_id)
		var row: Control = overlay.module_context.slots.get(ModuleSlots.ACTION_ROW)
		assert_not_null(row, "%s publishes no action row for its bar" % mode_id)
		assert_true(row.is_ancestor_of(bar.bar_root), "the %s bar did not mount into it" % mode_id)


## **No mode has two bars.** A mode declaring both the player's and the editor's would publish the
## four satellite slots twice, and whichever mounted last would silently win.
func test_no_mode_declares_more_than_one_bar() -> void:
	for mode: ViewMode in ViewModes.all():
		var bars: Array[StringName] = []
		for id: StringName in mode.modules:
			var built: ViewModule = ModuleCatalog.build(id)
			if built is BarModule:
				bars.append(id)
			if built != null:
				built.free()
		assert_lt(bars.size(), 2, "%s declares %s -- two bars in one slot" % [mode.id, bars])


## Every bar publishes the four satellites, so the combat log sits left of whichever bar the mode
## has rather than left of the player's specifically.
func test_every_bar_publishes_the_four_satellite_slots() -> void:
	for mode_id: StringName in BARS:
		var overlay: ControlOverlay = _mount(ViewModes.by_id(mode_id))
		for slot_name: StringName in ModuleSlots.ACTION_BAR_SLOTS:
			assert_true(
				overlay.module_context.slots.has(slot_name),
				(
					"%s: %s was never published -- a dependant falls back to ui_root"
					% [mode_id, slot_name]
				)
			)


# ---------------------------------------------------------------- the spectator's bar


## **Pass D's last unlanded line.** *"`top_left_controls_module` → the spectator action bar."* It
## had nowhere to go until this bar existed; this is the move, asserted by ancestry rather than by
## a coordinate, because ancestry is what makes the cluster follow the bar.
func test_the_spectators_transport_controls_and_cluster_are_in_its_bar() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.spectator())
	var bar: SpectatorBarModule = overlay.module(&"spectator_bar") as SpectatorBarModule
	var pacing: PlaybackModule = overlay.module(&"playback") as PlaybackModule
	var cluster: TopLeftControlsModule = (
		overlay.module(&"top_left_controls") as TopLeftControlsModule
	)

	assert_true(bar.bar_root.is_ancestor_of(pacing.play_button), "Play is not in the bar")
	assert_true(
		bar.bar_root.is_ancestor_of(cluster.controls), "the shared cluster is not in the bar"
	)
	assert_true(bar.bar_root.is_ancestor_of(pacing.slide_ms_field), "nor are the timing knobs")


## The two modules that moved did not change: they ask for `PACING_ROW` and the bar is simply what
## publishes it now. **That is the module system's own premise** — where a panel sits is the mode's
## decision and touches no panel.
func test_the_pacing_row_is_published_by_the_bar_rather_than_by_a_chrome() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.spectator())
	var bar: SpectatorBarModule = overlay.module(&"spectator_bar") as SpectatorBarModule
	assert_eq(overlay.module_context.slots.get(ModuleSlots.PACING_ROW), bar.pacing_row)
	assert_eq(overlay.module_context.slots.get(ModuleSlots.TUNABLES), bar.tunables_row)


## And the same two names still resolve under the chrome that used to own them, so a mode asking for
## `TOP_LEFT_ROWS` is not broken by the bar existing.
func test_the_old_chrome_still_publishes_the_same_two_names() -> void:
	var mode := ViewMode.new()
	mode.id = &"pacing_under_the_old_chrome"
	mode.chrome = ModeChrome.TOP_LEFT_ROWS
	mode.modules = [&"playback"] as Array[StringName]

	var overlay: ControlOverlay = _mount(mode)

	assert_not_null(overlay.module_context.slots.get(ModuleSlots.PACING_ROW))
	assert_not_null(overlay.module_context.slots.get(ModuleSlots.TUNABLES))


# ---------------------------------------------------------------- the player's bar


## *"Player — square items, left-aligned, two rows, small padding."* **Read off the real boxes**:
## two distinct y values means two rows, and the grid's own column count is not trusted to imply it.
func test_the_players_boxes_are_square_and_sit_on_two_rows() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	await get_tree().process_frame
	await get_tree().process_frame

	var tops: Dictionary = {}
	for box: Node in bar.action_grid.get_children():
		var rect: Rect2 = (box as Control).get_global_rect()
		tops[roundi(rect.position.y)] = true
		assert_almost_eq(rect.size.x, rect.size.y, 1.0, "an action item must be square")
	gut.p("box rows at y = %s" % str(tops.keys()))
	assert_eq(tops.size(), ActionBarModule.BOX_ROWS, "the ten boxes must sit on two rows")
	assert_eq(bar.action_grid.get_child_count(), ActionBar.SLOT_COUNT, "all ten are still there")


## **Left-aligned, and it is what keeps the bar inside its own band.** Ten 108 px boxes on one row
## are 1080 px against a bar the table gives 960; over two rows they are 540 and start at the bar's
## own left edge. Measured against the real rects, not against the constants.
func test_the_player_bars_boxes_start_at_its_left_edge_and_fit_inside_it() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	await get_tree().process_frame
	await get_tree().process_frame

	var grid: Rect2 = bar.action_grid.get_global_rect()
	var band: Rect2 = (
		(overlay.module_context.slots.get(ModuleSlots.ACTION_ROW) as Control).get_global_rect()
	)
	gut.p("boxes %s inside the band %s" % [str(grid), str(band)])
	assert_lt(grid.size.x, band.size.x, "the boxes are wider than the bar they sit in")
	# **The bar's left edge plus its inset**, which the UI review asked for: *"the action bar buttons
	# on the player view need some padding off the top left of the action bar."* Left-aligned still
	# means "from the left", not "flush against it".
	assert_almost_eq(
		grid.position.x,
		(
			bar.content_column.get_global_rect().position.x
			+ UiLayout.scaled(ActionBarModule.BOX_INSET)
		),
		1.0,
		"left-aligned: the boxes start one inset in from the bar's own left edge"
	)


# ---------------------------------------------------------------- the editor's bar


func _editor_overlay() -> ControlOverlay:
	return _mount(ViewModes.editor())


## *"Labelled buttons, not squares."* Every verb in the tool vocabulary is reachable, which is the
## coverage half — the editor could author nine things before this pass and must still author nine.
func test_the_editor_bar_offers_a_labelled_button_for_every_tool() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule

	for tool: StringName in EditorModule.TOOLS:
		if tool == &"place":
			# `place` is the per-kind buttons; asserted below rather than skipped silently.
			continue
		assert_true(bar.tool_buttons.has(tool), "no button reaches the %s tool" % tool)
		assert_ne((bar.tool_buttons[tool] as Button).text, "", "%s's button has no label" % tool)
	for kind: StringName in EditorModule.PLACEMENT_KINDS:
		assert_true(bar.kind_buttons.has(kind), "no button places a %s" % kind)
	assert_eq((bar.kind_buttons[MapPlacement.KIND_SURFACE] as Button).text, "Tiles")
	assert_eq((bar.kind_buttons[MapPlacement.KIND_FIELD_ITEM] as Button).text, "Place Items")


func test_pressing_a_tool_button_arms_that_tool() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var editor: EditorModule = overlay.module(&"editor") as EditorModule

	(bar.tool_buttons[&"remove"] as Button).pressed.emit()
	assert_eq(editor.active_tool, &"remove")
	(bar.tool_buttons[&"claim"] as Button).pressed.emit()
	assert_eq(editor.active_tool, &"claim")


## **THE STATED ACCEPTANCE**: *"the place-items list is searchable and offers every placeable
## part."* Both halves, against the real widget rather than against `SearchFilter` a second time.
func test_the_place_items_list_offers_every_placeable_part_and_searches_it() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var editor: EditorModule = overlay.module(&"editor") as EditorModule

	(bar.kind_buttons[MapPlacement.KIND_FIELD_ITEM] as Button).pressed.emit()

	assert_true(bar.list.visible, "the button opened nothing")
	assert_eq(
		bar.list.shown_ids(),
		editor.placeable_part_ids(),
		"the list must offer every placeable part"
	)
	assert_false(editor.placeable_part_ids().is_empty(), "sanity: there are parts to offer")

	bar.list.apply_filter("ship_floor")
	gut.p("filtered to: %s" % ", ".join(bar.list.shown_ids()))
	assert_true(bar.list.shown_ids().has(&"ship_floor"), "searching lost the thing searched for")
	assert_lt(bar.list.shown_ids().size(), editor.placeable_part_ids().size(), "it did not narrow")


## Picking arms the tool with that part **and** the kind the button carried, which is the whole
## reason there is a button per kind rather than one "Place".
func test_picking_from_the_list_arms_the_place_tool_with_that_part_and_kind() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.active_tool = &"remove"

	(bar.kind_buttons[MapPlacement.KIND_SURFACE] as Button).pressed.emit()
	bar.list.chosen.emit(&"ship_floor")

	assert_eq(editor.active_tool, &"place")
	assert_eq(editor.selected_part, &"ship_floor")
	assert_eq(editor.selected_kind, MapPlacement.KIND_SURFACE)
	# And the arming really authors: a click places what was picked, through the unchanged router.
	assert_true(editor.apply_tool_at(Vector2i(2, 2)))
	assert_eq(editor.controller.placements_at(Vector2i(2, 2))[0].part_id, &"ship_floor")


## Opening the list changes nothing on its own. An author who opens it and closes it again has not
## silently switched tools underneath themselves.
func test_opening_the_list_and_closing_it_leaves_the_tool_alone() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.active_tool = &"height"

	(bar.kind_buttons[MapPlacement.KIND_BLOCKER] as Button).pressed.emit()
	bar.list.close()

	assert_false(bar.list.visible)
	assert_eq(editor.active_tool, &"height", "opening a list must not arm anything")


## **Load is the second caller of the one list.** The taskblock puts save, load, run-a-bout and undo
## on this bar, and load had no affordance at all before this pass — `EditorModule.open` was
## reachable only from a test.
func test_load_offers_the_authored_catalogs_through_the_same_list() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule

	bar.load_button.pressed.emit()

	assert_true(bar.list.visible)
	var offered: Array[StringName] = bar.list.shown_ids()
	gut.p("boards offered: %s" % ", ".join(offered))
	assert_false(offered.is_empty(), "no authored board is reachable from the Load button")
	for name: StringName in MapCatalog.names():
		assert_true(offered.has(name), "the map '%s' is not offered" % name)


func test_picking_a_board_loads_it_into_the_editor() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var names: Array[StringName] = MapCatalog.names()
	if names.is_empty():
		pass_test("no authored maps in this build -- nothing to load")
		return

	bar.load_button.pressed.emit()
	bar.list.chosen.emit(names[0])

	assert_eq(
		editor.controller.board_name, String(names[0]), "the picked board is not the one open"
	)
	assert_gt(editor.controller.placements.size(), 0, "it loaded a board with nothing on it")


## The four file verbs are reachable and each one calls the method `EditorModule` already had —
## this row is where they are reached from, not where they are implemented.
func test_the_file_row_reaches_the_verbs_the_editor_module_already_owned() -> void:
	var overlay: ControlOverlay = _editor_overlay()
	var bar: EditorBarModule = overlay.module(&"editor_bar") as EditorBarModule
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.selected_part = &"ship_floor"
	editor.active_tool = &"place"
	editor.apply_tool_at(Vector2i(1, 1))
	assert_eq(editor.controller.placements.size(), 1, "sanity: something to undo")

	(bar.file_buttons["Undo"] as Button).pressed.emit()

	assert_eq(editor.controller.placements.size(), 0, "the bar's Undo did not reach the controller")
	for entry: Array in EditorBarModule.FILE_BUTTONS:
		assert_true(bar.file_buttons.has(entry[0]), "%s has no button" % entry[0])
		assert_true(
			editor.has_method(entry[1]), "%s names a verb the editor does not have" % entry[0]
		)
