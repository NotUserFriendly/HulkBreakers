extends GutTest

## **The supervisor's first review pass over the taskblock-57 layout, as tests.**
##
## Each of these is a point raised against the shipped surface rather than against a spec, so each
## one names what was seen. They are gathered in one file because that is what they have in common —
## individually they belong to six different modules, and a reader asking "what did the review
## change" would otherwise have to find six headers.
##
## **Read the real nodes back.** Two of these defects were invisible to tests that read a module's
## own bookkeeping instead of the tree it had built, which is the failure this file is written
## against: the filter test asked the list what it thought it was showing, and the log-resize tests
## measured a `position` in a coordinate space that had stopped meaning what they assumed.

const SCREEN := Vector2(1920, 1080)
const TOLERANCE := 2.0


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()
	UiLayout.scale = 1.0


func _overlay(mode: ViewMode) -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(mode)
	battle.set_overlay(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	return overlay


# ---------------------------------------------------------------- the bar is the centred thing


## **THE REVIEW POINT**: *"Action bar needs to be the centered item, with the combat log to the side
## of it. Currently the combined action bar and combat log space are centered."*
##
## Asserted on the bar's own centre against the safe rect's, read off real global rects — the whole
## defect was that a different node was the one being centred.
func test_the_bar_itself_is_centred_not_the_cluster_around_it() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var logs: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule

	var bar_centre: float = bar.content_column.get_global_rect().get_center().x
	var safe_centre: float = UiLayout.safe_rect(SCREEN).get_center().x
	gut.p("bar centre %.1f against safe centre %.1f" % [bar_centre, safe_centre])
	assert_almost_eq(bar_centre, safe_centre, TOLERANCE, "the bar is not the centred item")

	# And the log really is beside it rather than sharing its centring.
	assert_lt(
		logs.panel.get_global_rect().end.x,
		bar.content_column.get_global_rect().position.x + TOLERANCE,
		"the combat log must sit to the side of the bar, not overlap it"
	)


## The satellites hang off the bar symmetrically, which is what makes the centring hold whatever is
## in them — the wings expand equally rather than the cluster being measured.
func test_the_bar_stays_centred_with_a_wide_surface_on_one_side_only() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var before: float = bar.content_column.get_global_rect().get_center().x

	# A wide passenger on the left slot only — the shape the defect was reported in.
	var passenger := ColorRect.new()
	passenger.custom_minimum_size = Vector2(300, 20)
	bar.left_slot.add_child(passenger)
	await get_tree().process_frame
	await get_tree().process_frame

	var after: float = bar.content_column.get_global_rect().get_center().x
	gut.p("bar centre %.1f -> %.1f after a 300px passenger on the left" % [before, after])
	assert_almost_eq(after, before, TOLERANCE, "widening one side moved the bar off centre")


# ---------------------------------------------------------------- the bar's own size


## **THE REVIEW POINT**: *"Action bar should be ~1/8th of the screen height tall."* Asserted against
## the layout's arithmetic and against the real region, because the rect and the node that uses it
## are different claims.
func test_the_bar_is_about_an_eighth_of_the_screen_tall() -> void:
	var expected: float = UiLayout.safe_rect(SCREEN).size.y / 8.0
	assert_almost_eq(
		BattleLayout.action_bar_rect(SCREEN).size.y,
		expected,
		TOLERANCE,
		"the placement table no longer gives the bar an eighth of the safe height"
	)

	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var region: Control = overlay.module_context.slots.get(ModuleSlots.ACTION_ROW)
	assert_almost_eq(region.get_global_rect().size.y, expected, TOLERANCE)


## **THE REVIEW POINT**: *"Action bar is not a fixed size."* It is now: the boxes are fitted into
## the band rather than the band growing to the boxes, so ten square items occupy the height the
## placement table gives the bar and no more.
func test_the_bars_boxes_are_fitted_into_the_band_rather_than_setting_it() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var band: float = BattleLayout.action_bar_rect(SCREEN).size.y

	var boxes: float = bar.action_grid.get_global_rect().size.y
	gut.p("boxes %.1f tall inside a %.1f band" % [boxes, band])
	assert_lt(boxes, band + TOLERANCE, "the boxes are taller than the bar they sit in")
	# Non-vacuous: they must actually fill most of it rather than passing by being tiny.
	assert_gt(boxes, band * 0.5, "the boxes have collapsed to nothing")


## **THE REVIEW POINT**: *"has no background on any module."* The bar draws one now, and it is a
## real `StyleBox` rather than a modulate on something else.
func test_the_bar_draws_a_background() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var backing: Node = bar.content_column.get_parent()

	assert_true(backing is PanelContainer, "the bar's content has no panel behind it")
	var style: StyleBox = (backing as PanelContainer).get_theme_stylebox("panel")
	assert_true(style is StyleBoxFlat, "the panel is not carrying a background style")
	assert_gt((style as StyleBoxFlat).bg_color.a, 0.0, "the background is fully transparent")


# ---------------------------------------------------------------- unit information, centred


## **THE REVIEW POINT**: *"This is supposed to be centered above the action bar, not left aligned."*
func test_the_unit_resources_are_centred_over_the_bar() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var resources: UnitResourcesModule = overlay.module(&"unit_resources") as UnitResourcesModule

	var pips: float = resources.column.get_global_rect().get_center().x
	var bar_centre: float = bar.content_column.get_global_rect().get_center().x
	gut.p("resources centre %.1f against bar centre %.1f" % [pips, bar_centre])
	assert_almost_eq(pips, bar_centre, TOLERANCE, "the resources are not centred over the bar")


## And the UI buttons stay at the bar's right edge — the other half of the same row, and the half
## that would break if "centred" were applied to the whole row rather than to one slot.
func test_the_ui_buttons_stay_at_the_bars_right_edge() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule

	assert_almost_eq(
		buttons.row.get_global_rect().end.x,
		bar.content_column.get_global_rect().end.x,
		TOLERANCE + 2.0,
		"the UI buttons are not at the bar's right edge"
	)


# ---------------------------------------------------------------- square, abbreviated buttons


## **THE REVIEW POINT**: *"All toggles and descriptive text should be replaced with square BUTTONS
## with an up-to three letter abbreviation on them."*
func test_every_control_in_the_ui_buttons_cluster_is_a_square_abbreviation() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule

	var checked: Array[String] = []
	for child: Node in buttons.row.get_children():
		var button := child as UiButton
		assert_not_null(button, "%s is in the cluster and is not a UiButton" % child.name)
		assert_lt(button.text.length(), 4, "'%s' is longer than three letters" % button.text)
		assert_almost_eq(
			button.custom_minimum_size.x, button.custom_minimum_size.y, 0.001, "not square"
		)
		checked.append(button.text)
	gut.p("cluster: %s" % ", ".join(checked))
	assert_false(checked.is_empty(), "the cluster is empty, so this proved nothing")


## Inspect's own button is in the cluster and obeys the same rule — it is built by `InspectModule`
## rather than by the cluster, which is exactly how a row of controls comes to disagree with itself.
func test_inspects_own_button_matches_the_cluster_it_sits_in() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var button: UiButton = overlay.inspect().button
	assert_not_null(button, "the player mode gives Inspect a button")
	assert_eq(button.text, "INS")
	assert_lt(button.text.length(), 4)


## The abbreviation is derived from the id, so a module added later gets one without an edit.
func test_abbreviations_are_derived_from_the_id() -> void:
	assert_eq(UiButton.abbreviate(&"action_bar"), "AB")
	assert_eq(UiButton.abbreviate(&"inspect_viewer"), "IV")
	assert_eq(UiButton.abbreviate(&"inspect"), "INS")
	assert_eq(UiButton.abbreviate(&"editor"), "EDI")
	assert_lt(
		UiButton.abbreviate(&"a_very_long_module_name_indeed").length(),
		4,
		"a four-word id must still fit in three letters"
	)


## **THE REVIEW POINT**, second half: *"Hovering them for 1.5 seconds should show a description of
## what they do."* The description exists and the dwell is the shared 1.5 s clock, not a new one.
func test_a_cluster_button_describes_itself_after_the_shared_dwell() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var toggle: UiButton = buttons.toggles.values()[0]

	assert_ne(toggle.description, "", "a button with no description explains nothing")
	assert_not_null(toggle.tooltip_view, "the player mode declares a tooltip renderer")
	assert_eq(
		TooltipView.HOVER_DELAY_SEC,
		HoverDwell.DELAY_SEC,
		"the button's wait must be the one shared clock, never a second timer"
	)


## Every mode that has the cluster has the renderer it needs, or the descriptions are dead text.
func test_every_mode_with_ui_buttons_also_declares_a_tooltip() -> void:
	for mode: ViewMode in ViewModes.all():
		if not mode.modules.has(&"ui_buttons"):
			continue
		assert_true(
			mode.modules.has(&"tooltip"),
			"%s has the UI buttons cluster and no tooltip renderer to describe it" % mode.id
		)


# ---------------------------------------------------------------- the searchable list, filtering


## **THE REVIEW POINT**: *"Filtered lists of placeables in editor view aren't filtering."*
##
## **Asserted against the container's real children, not against `shown_ids()`.** The module's own
## `rows` array was correct throughout; `queue_free` is deferred, so the old buttons were still in
## the tree and still drawn while the filtered ones were appended after them. The test that existed
## read the bookkeeping and passed.
func test_filtering_removes_the_rows_it_filtered_out_from_the_tree() -> void:
	var list := SearchableList.new()
	add_child_autofree(list)
	list.open("probe", [&"ship_floor", &"ship_wall", &"barrel", &"crate"] as Array[StringName])
	assert_eq(list.results.get_child_count(), 4, "sanity: it opened unfiltered")

	list.search_field.text = "barrel"
	list.search_field.text_changed.emit("barrel")

	var on_screen: Array[String] = []
	for child: Node in list.results.get_children():
		on_screen.append((child as Button).text)
	gut.p("on screen after typing 'barrel': %s" % ", ".join(on_screen))
	assert_eq(on_screen, ["barrel"] as Array[String], "the filtered-out rows are still drawn")


## Typing through a query and back out again leaves the list whole, rather than accumulating a row
## per keystroke — which is what the deferred free produced.
func test_typing_and_clearing_returns_the_whole_list_exactly_once() -> void:
	var list := SearchableList.new()
	add_child_autofree(list)
	list.open("probe", [&"ship_floor", &"barrel"] as Array[StringName])

	for query: String in ["b", "ba", "bar", "ba", "b", ""]:
		list.search_field.text_changed.emit(query)

	assert_eq(list.results.get_child_count(), 2, "the list grew as it was typed into")


# ---------------------------------------------------------------- verbose, unhooked


## **THE REVIEW POINT**: *"Verbose is currently unfolding elements which is not its purpose.
## Unhook it from that, and leave it open for later."*
##
## The flag, the checkbox and the signal all survive; nothing reads it to decide what is drawn.
func test_verbose_no_longer_unfolds_anything() -> void:
	var label := RichTextLabel.new()
	add_child_autofree(label)
	var sink := HierarchicalUiSink.new(label, null)

	sink.verbose = true
	var while_verbose: String = label.text
	sink.verbose = false

	gut.p("verbose render: %s" % while_verbose.replace("\n", " / "))
	assert_eq(while_verbose, label.text, "turning verbose on changed what was drawn")


## And the affordance is still there to be given a meaning later — the checkbox reaches the flag.
func test_the_verbose_checkbox_still_reaches_the_flag_it_no_longer_drives() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var logs: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule

	logs.panel.verbose_checkbox.button_pressed = true

	assert_true(logs.sink.verbose, "the checkbox must still set the flag it is left wired to")


# ---------------------------------------------------------------- the log's hover highlight


## **THE REVIEW POINT**: *"the highlight needs to have a background slightly bigger than itself to
## make it not tangent other text."*
func test_the_overflow_previews_background_is_bigger_than_its_text() -> void:
	var panel := CombatLogPanel.new()
	add_child_autofree(panel)
	var style: StyleBox = panel.overflow_preview.get_theme_stylebox("normal")

	assert_gt(style.content_margin_top, 0.0, "the preview is tangent to the line above it")
	assert_gt(style.content_margin_bottom, 0.0, "and to the line below it")
	assert_gt(style.content_margin_left, 0.0)


# ---------------------------------------------------------------- the editor's details panel


## **THE REVIEW POINT**: *"it's too wide. Should be roughly half as wide as it is tall, and given a
## slight padding off that corner."*
##
## The slot always was half as wide as tall; the panel in it was not, because a `PanelContainer`
## takes its content's minimum width and a column of labelled spin boxes asks for more. Read off the
## real panel rather than off the rect it was supposed to fill.
func test_the_editors_details_panel_fits_the_slot_it_was_given() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.editor())
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var slot: Rect2 = BattleLayout.inspect_viewer_rect(SCREEN)

	var drawn: Rect2 = editor.panel.get_global_rect()
	gut.p("details panel %s in a slot of %s" % [str(drawn), str(slot)])
	assert_almost_eq(drawn.size.x, slot.size.x, TOLERANCE, "the panel is wider than its slot")
	assert_lt(drawn.size.x, drawn.size.y, "it must be taller than it is wide")


func test_the_inspect_viewer_slot_is_padded_off_the_corner() -> void:
	var rect: Rect2 = BattleLayout.inspect_viewer_rect(SCREEN)
	gut.p("viewer at %s" % str(rect))
	assert_gt(rect.position.x, 0.0, "flush into the physical corner")
	assert_gt(rect.position.y, 0.0)
	assert_almost_eq(
		rect.size.x, rect.size.y * BattleLayout.INSPECT_VIEWER_WIDTH_FRACTION, TOLERANCE
	)


# ---------------------------------------------------------------- BR57.01, stranded units


## **THE REPORTED BUG**: *"Some units spawn in edit mode at the places they were in the last bout."*
##
## A unit the authored board cannot seat is not drawn. Asserted through the real editor refresh,
## with the units really left where the previous bout put them.
func test_a_unit_the_authored_board_cannot_seat_is_not_drawn() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.editor())
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	assert_false(overlay.battle.unit_views.is_empty(), "sanity: the bout put units on the board")

	# An empty authored board — nothing to stand on, so every unit is stranded.
	editor.refresh()

	var visible_views: int = 0
	for view: HitVolumeView in overlay.battle.unit_views:
		if view.visible:
			visible_views += 1
	gut.p(
		(
			"%d of %d unit views drawn on an empty board"
			% [visible_views, overlay.battle.unit_views.size()]
		)
	)
	assert_eq(visible_views, 0, "a unit with nowhere to stand is still being drawn")


## And they come back once the board can seat them, so the fix is not "hide the units".
func test_a_unit_the_board_can_seat_is_drawn_again() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.editor())
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	editor.refresh()

	editor.controller.set_size(6, 6)
	for y: int in range(6):
		for x: int in range(6):
			editor.controller.place(Vector2i(x, y), &"ship_floor")
	editor.refresh()

	var visible_views: int = 0
	for view: HitVolumeView in overlay.battle.unit_views:
		if view.visible:
			visible_views += 1
	assert_gt(visible_views, 0, "the authored floor seats them and they must be drawn again")
