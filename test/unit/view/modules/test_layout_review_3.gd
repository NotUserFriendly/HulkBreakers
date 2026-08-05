extends GutTest

## **The supervisor's third review pass over the layout, as tests.**
##
## The first two passes live in `test_layout_review.gd`; this is a second file rather than a longer
## one because that file reached the linter's own cap on how many cases belong in one script, and
## "which review pass raised it" is the only axis these split cleanly on.
##
## Same discipline as its sibling: **each test names what was seen**, and every assertion reads a
## real node rather than the flag or the formatter behind it.

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


## **THE REVIEW POINT**: *"Still two 'Inspect' keys... Wait there are THREE inspect related buttons.
## One of which always does something, the other two flaky."* Plus *"Two debug options as well."*
##
## The cluster swept every collapsible module into a toggle, including the two that already had a
## control of their own — producing a second `INS` that collapsed the panel instead of opening it,
## and a `DP` beside the `DBG`.
func test_no_module_has_two_controls_in_the_cluster() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule

	var labels: Array[String] = []
	for child: Node in buttons.row.get_children():
		labels.append((child as UiButton).text)
	if overlay.inspect().button != null:
		labels.append(overlay.inspect().button.text)
	gut.p("cluster: %s" % ", ".join(labels))

	var seen: Dictionary = {}
	for label: String in labels:
		assert_false(seen.has(label), "two controls in the cluster are both labelled '%s'" % label)
		seen[label] = true


## The rule behind it, asserted at the module level so a third module that grows its own button is
## covered the day it does.
func test_a_module_with_its_own_button_is_not_swept_into_a_second_one() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule

	for id: StringName in overlay.module_context.modules:
		var module: ViewModule = overlay.module_context.modules[id]
		if module.provides_own_button():
			assert_false(
				buttons.toggles.has(id), "%s builds its own control and was given a second one" % id
			)


## **THE REVIEW POINT**: *"Buttons which have something open should be highlighted with a border.
## Button 'on', button is highlighted and module is visible. Button 'off', button is un-highlighted
## and module is disabled/hidden."*
func test_a_buttons_border_follows_whether_its_module_is_up() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var button: UiButton = buttons.toggles[&"action_bar"]

	assert_true(button.active, "the bar is up, so its button must be lit")
	assert_not_null(button.get_theme_stylebox("normal"), "and lit means a real border")

	button.pressed.emit()
	assert_false(bar.backing.visible, "sanity: it dismissed the bar")
	# **The border is re-read on the next tick, not set by the press.** That is the point of the
	# follow-up review's *"the highlight should only appear if the window is visible, even if it's
	# launched some other way"* — the button reports the module rather than remembering its own
	# click, so the test has to let a frame's worth of reading happen.
	buttons.tick(0.0)
	assert_false(button.active, "a dismissed module must leave its button unlit")


## **THE REVIEW POINT**: *"When the action bar is dismissed by the UI Button, the UI BUTTONS
## shouldn't float in the middle, they should pin downward to the bottom edge of the screen. The
## UNIT RESOURCES should do the same."*
func test_dismissing_the_bar_drops_its_satellites_to_the_bottom_edge() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var resources: UnitResourcesModule = overlay.module(&"unit_resources") as UnitResourcesModule
	var before: float = buttons.row.get_global_rect().end.y

	(buttons.toggles[&"action_bar"] as UiButton).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	var after: float = buttons.row.get_global_rect().end.y
	gut.p("UI buttons bottom %.1f -> %.1f" % [before, after])
	assert_gt(after, before, "the buttons stayed where the bar had been holding them up")
	assert_almost_eq(
		after,
		resources.column.get_global_rect().end.y,
		TOLERANCE,
		"and the unit resources must drop with them"
	)


## **THE REVIEW POINT**: *"Debug button missing in editor mode."*
func test_the_editor_has_a_debug_button() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.editor())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	if overlay.debug_panel_module() == null or overlay.debug_panel_module().panel == null:
		pass_test("release build: there is no debug menu to reach")
		return
	assert_not_null(buttons.debug_button, "the editor cannot reach the debug menu")


## **THE REVIEW POINT**: *"Keybindings pop up should have a panel with a background that appears in
## the center of the screen, along with a [x] at the top right to dismiss it."*
func test_the_keybindings_sheet_is_a_centred_panel_with_a_way_out() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var legend: ControlsLegendModule = overlay.module(&"controls_legend") as ControlsLegendModule

	assert_not_null(legend.panel, "the legend is still a bare label")
	assert_not_null(legend.panel.get_theme_stylebox("panel"), "with no background")
	assert_not_null(legend.close_button, "and no way to dismiss it")
	assert_eq(legend.close_button.text, "[x]")
	assert_false(legend.panel.visible, "reference, not chrome -- it starts closed")

	legend.toggle()
	await get_tree().process_frame
	assert_true(legend.panel.visible)
	assert_true(legend.keybindings_button.active, "and its button lights while it is up")
	var centre: Vector2 = legend.panel.get_global_rect().get_center()
	gut.p("sheet centred at %v against %v" % [centre, SCREEN * 0.5])
	assert_almost_eq(centre.x, SCREEN.x * 0.5, TOLERANCE + 2.0, "it is not centred")

	legend.close_button.pressed.emit()
	assert_false(legend.panel.visible, "the [x] did not dismiss it")
	assert_false(legend.keybindings_button.active)


## The H key and the button still flip **one** piece of state, which is the property tb31 built and
## the review did not change.
func test_the_key_and_the_button_still_share_one_state() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var legend: ControlsLegendModule = overlay.module(&"controls_legend") as ControlsLegendModule

	legend.toggle()
	assert_true(
		legend.controls_overlay.is_open(), "the overlay reads the same state the button set"
	)
	var pressed := InputEventKey.new()
	pressed.keycode = ControlBindings.TOGGLE_KEY
	pressed.pressed = true
	legend.controls_overlay._unhandled_input(pressed)
	assert_false(legend.controls_overlay.is_open(), "the key must flip what the button flipped")


## **THE REVIEW POINT**: *"Watch should go above the other buttons, with an approximately button
## height gap between it and the actual turn related buttons."*
func test_watch_sits_above_the_turn_verbs_with_a_gap() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var toggle: ControlToggleModule = overlay.module(&"control_toggle") as ControlToggleModule
	var turns: TurnControlsModule = overlay.module(&"turn_controls") as TurnControlsModule
	await get_tree().process_frame

	var watch: Rect2 = toggle.button.get_global_rect()
	var end_turn: Rect2 = turns.end_turn_button.get_global_rect()
	gut.p("watch ends at %.1f, end turn starts at %.1f" % [watch.end.y, end_turn.position.y])
	assert_lt(watch.end.y, end_turn.position.y, "Watch must be above the turn verbs")
	assert_gt(
		end_turn.position.y - watch.end.y,
		UiLayout.scaled(ControlToggleModule.GAP_HEIGHT) * 0.5,
		"and separated from them by about a button's height"
	)


## **THE REVIEW POINT**: *"Assume Control should move to the TURN ORDER MANAGEMENT section. Inject
## is obsolete, and can be removed."* With Watch moved and Inject gone the cluster was empty, so it
## is retired rather than left as a container of nothing.
func test_the_spectator_carries_assume_control_in_its_turn_column() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.spectator())
	var toggle: ControlToggleModule = overlay.module(&"control_toggle") as ControlToggleModule

	assert_not_null(toggle, "the spectator carries the control toggle in its turn-order column")
	assert_eq(toggle.button.text, "Assume Control")
	# **And still no unit input**, which is the contract folding this into `turn_controls` broke.
	assert_false(
		ViewModes.spectator().has_unit_input(), "a spectator cannot mutate through the view"
	)
	assert_null(overlay.module(&"turn_controls"), "so it declares no turn verbs at all")
	assert_null(overlay.module(&"top_left_controls"), "and the cluster is retired outright")


## The retirement is real: nothing in the catalog builds it and no mode names it.
func test_nothing_declares_the_retired_cluster_any_more() -> void:
	assert_false(ModuleCatalog.IDS.has(&"top_left_controls"))
	assert_null(ModuleCatalog.build(&"top_left_controls"))
	for mode: ViewMode in ViewModes.all():
		assert_false(mode.modules.has(&"top_left_controls"), "%s still declares it" % mode.id)


## **THE REVIEW POINTS** on padding: *"INSPECT in Player view — No padding on any of the elements.
## Also the panel itself is not padded off the corner."*
func test_inspect_is_padded_off_its_corner_and_inside_itself() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var pad: float = UiLayout.scaled(BattleLayout.PADDING)

	var rect: Rect2 = BattleLayout.inspect_rect(SCREEN)
	gut.p("inspect at %s on a %s screen" % [str(rect), str(SCREEN)])
	assert_almost_eq(SCREEN.x - rect.end.x, pad, 0.001, "flush into the physical corner")
	assert_almost_eq(rect.position.y, pad, 0.001)

	var style: StyleBox = overlay.inspect().panel.get_theme_stylebox("panel")
	assert_gt(style.content_margin_left, 0.0, "its rows run into its own border")
	assert_gt(style.content_margin_top, 0.0)


## **THE REVIEW POINT**: *"INSPECT VIEWER in Player view — Just a loose window, it needs a border of
## some sort, likely embedded in a panel so it can be padded."*
func test_the_inspect_viewer_sits_in_a_padded_frame() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var module: InspectViewerModule = overlay.module(&"inspect_viewer") as InspectViewerModule

	assert_not_null(module.frame, "the viewer is still a bare subview")
	assert_true(module.frame.is_ancestor_of(module.viewer))
	var style: StyleBoxFlat = module.frame.get_theme_stylebox("panel") as StyleBoxFlat
	# **The padding IS the border**, which is the review's own correction: *"I mean the panel needs
	# to be oversized AS a border, not add a border. You can remove the thin gray line."* So the
	# frame is a filled panel larger than the view it holds, and there is deliberately no stroke.
	assert_gt(style.content_margin_left, 0.0, "nothing oversizes the panel around the view")
	assert_gt(style.bg_color.a, 0.0, "and the band showing around it must actually be drawn")
	assert_eq(style.border_width_left, 0, "the thin line was asked to go")


## **THE REVIEW POINT**: *"EDIT INSPECT VIEWER — Panel needs some padding all around it."*
func test_the_editors_details_panel_is_padded_all_round() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.editor())
	var editor: EditorModule = overlay.module(&"editor") as EditorModule
	var style: StyleBox = editor.panel.get_theme_stylebox("panel")

	for side: float in [
		style.content_margin_left,
		style.content_margin_right,
		style.content_margin_top,
		style.content_margin_bottom
	]:
		assert_gt(side, 0.0, "the details panel has an unpadded edge")


# ================================================================ fifth review pass


## **THE REVIEW POINT**: *"Can the Action/spectator/edit bar toggle button be the farthest to the
## right, and ~70% the size of the other UI buttons?"*
func test_the_bars_own_toggle_is_last_in_the_row_and_smaller() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var buttons: UiButtonsModule = overlay.module(&"ui_buttons") as UiButtonsModule
	var bar: UiButton = buttons.toggles[&"action_bar"]
	var children: Array[Node] = buttons.row.get_children()

	gut.p("row: %s" % ", ".join(children.map(func(c: Node) -> String: return (c as Button).text)))
	assert_eq(children[children.size() - 1], bar, "the bar's toggle is not the farthest right")
	for child: Node in children:
		if child == bar:
			continue
		assert_lt(
			bar.custom_minimum_size.x,
			(child as Control).custom_minimum_size.x,
			"the bar's toggle must be smaller than '%s'" % (child as Button).text
		)


## **THE REVIEW POINT**: *"Highlight border is too aggressive of a color, can it be replaced with a
## 50% gray?"* The alert yellow is the game's own tier for an armed action and a live announcement;
## chrome saying "these are open" should not compete with it.
func test_the_active_border_is_a_neutral_grey_not_the_alert_tier() -> void:
	assert_ne(UiButton.ACTIVE_BORDER_COLOR, HulkTheme.HIGHLIGHT, "still the alert colour")
	assert_almost_eq(UiButton.ACTIVE_BORDER_COLOR.r, 0.5, 0.01)
	assert_almost_eq(UiButton.ACTIVE_BORDER_COLOR.g, 0.5, 0.01)
	assert_almost_eq(UiButton.ACTIVE_BORDER_COLOR.b, 0.5, 0.01)


## **THE REVIEW POINTS** on the test-suite box: *"Can this be shaped like the inspect panel and put
## on the right?... It should draw OVER the inspect panel if both are active."*
func test_the_suite_box_takes_inspects_rect_and_draws_over_it() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.spectator())
	var replay: ReplayModule = overlay.module(&"replay") as ReplayModule
	if replay.suite_run_panel == null:
		pass_test("release build: the run panels are not constructed")
		return

	var expected: Rect2 = BattleLayout.inspect_rect(SCREEN)
	gut.p(
		"suite box at %s, inspect rect %s" % [str(replay.suite_run_panel.position), str(expected)]
	)
	assert_almost_eq(replay.suite_run_panel.position.x, expected.position.x, TOLERANCE)
	assert_almost_eq(replay.suite_run_panel.position.y, expected.position.y, TOLERANCE)

	# **Draw order is child order**, so "over" means "a later sibling" — and that is set by the
	# mode's own module declaration rather than by a z-index nobody would find.
	var inspect_at: int = overlay.inspect().panel.get_index()
	assert_gt(
		replay.suite_run_panel.get_index(),
		inspect_at,
		"the suite box is behind Inspect; `replay` must be declared after `inspect`"
	)


## *"There is floating white text in the spectator menu... that needs to be rolled into the Test
## Suite Module."* It was the watched run's table, anchored centre-right on its own.
func test_the_watched_run_table_lives_inside_the_suite_box() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.spectator())
	var replay: ReplayModule = overlay.module(&"replay") as ReplayModule
	if replay.suite_run_panel == null:
		pass_test("release build: the run panels are not constructed")
		return
	assert_true(
		replay.suite_run_panel.is_ancestor_of(replay.watched_run_panel),
		"the run table is still a loose panel of its own"
	)


## *"Can the title bar of the test suite be sized and shaped like the combat log's... And give the
## '?' some brackets '[?]' so it matches the other window management elements."*
func test_the_suite_box_has_a_combat_log_shaped_title_bar() -> void:
	var panel := SuiteRunPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame

	assert_eq(panel.criteria_button.text, "[?]")
	assert_eq(panel.close_button.text, "[x]")
	var bar: Control = panel.criteria_button.get_parent().get_parent() as Control
	assert_almost_eq(
		bar.custom_minimum_size.y,
		CombatLogPanel.TITLE_BAR_HEIGHT,
		0.001,
		"the title bar is not the shape the combat log's is"
	)


## **THE REVIEW POINT**: *"COMBAT LOG needs a touch of padding from the side of the screen."*
func test_the_combat_log_is_padded_off_the_screen_edge() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.player())
	var logs: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule
	var drawn: Rect2 = logs.panel.get_global_rect()

	gut.p("log at %s" % str(drawn))
	assert_gt(drawn.position.x, UiLayout.scaled(BattleLayout.PADDING) - TOLERANCE, "flush left")


## **THE REVIEW POINT**: *"Editor and Spectate: Both these modes need the Keybinds popup."*
func test_every_mode_with_a_ui_cluster_can_open_the_keybindings() -> void:
	for mode: ViewMode in ViewModes.all():
		if not mode.modules.has(&"ui_buttons"):
			continue
		assert_true(
			mode.modules.has(&"controls_legend"),
			"%s has a UI-buttons cluster and no keybindings sheet to open" % mode.id
		)


## **THE REVIEW POINT**: *"Spectate: Inspect menu looks to be the old one, and not split into
## two."* It was — the mode had no viewer module, so `InspectPanel` built its own docked one.
func test_the_spectator_gets_the_split_inspector() -> void:
	var overlay: ControlOverlay = await _overlay(ViewModes.spectator())
	var viewer: InspectViewerModule = overlay.module(&"inspect_viewer") as InspectViewerModule

	assert_not_null(viewer, "the spectator declares no inspect viewer")
	assert_eq(
		overlay.inspect().panel.viewer,
		viewer.viewer,
		"the panel must drive the slotted viewer, not one of its own"
	)


## **THE REPORTED BUG**: *"Lighting in the inspect viewer is very dark."* The viewer shares the
## battle's world so it can point at the real unit, which means it withdraws its own light — so the
## fill has to come from the one thing that cannot leak, its camera's own environment override.
func test_the_preview_camera_gets_more_ambient_than_the_board() -> void:
	assert_gt(
		WorldPalette.PREVIEW_AMBIENT_ENERGY,
		WorldPalette.AMBIENT_ENERGY,
		"a withdrawn-light preview needs more fill than the board it borrows"
	)
	var board: Environment = WorldPalette.environment()
	assert_almost_eq(
		board.ambient_light_energy,
		WorldPalette.AMBIENT_ENERGY,
		0.001,
		"the default must stay the board's, or raising the preview raised the battle"
	)
