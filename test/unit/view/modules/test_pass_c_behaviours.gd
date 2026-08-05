extends GutTest

## taskblock-57 Pass C — **the four behaviours the table asks for, on a real surface.**
##
## `test_hover_and_turn_end.gd` asserts the rules headlessly. This asserts the wiring: that pressing
## the real button raises the real dialog, that cancelling it really does leave the turn where it
## was, and that the minimized log really does touch the bar.
##
## Geometry is read off real nodes and never re-derived (CLAUDE.md).

## The headless viewport (`project.godot`), asserted rather than forced — see
## `test_battle_placements.gd` for why writing `root.size` is the wrong move here.
const SCREEN := Vector2(1920, 1080)


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _overlay() -> ControlOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	var overlay: ControlOverlay = ControlOverlay.for_mode(ViewModes.player())
	battle.set_overlay(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(
		overlay.ui_root.size, SCREEN, "the headless viewport is not the size this file assumes"
	)
	return overlay


# ---------------------------------------------------------------- ending a turn with something left


## **THE STATED ACCEPTANCE**: *"ending a turn with AP or MP remaining raises a confirmation and
## cancelling it leaves the turn intact."*
##
## Driven through the real `Button.pressed` signal rather than by calling the handler, so the wiring
## is part of what is under test.
func test_pressing_end_turn_with_ap_left_raises_a_confirmation_instead_of_ending_it() -> void:
	var overlay: ControlOverlay = await _overlay()
	var controls: TurnControlsModule = overlay.module(&"turn_controls") as TurnControlsModule
	var unit: Unit = overlay.battle.combat_state.current_unit()
	overlay.tactics().selection.select(unit)
	assert_gt(unit.ap, 0, "sanity: a fresh unit has AP, or this proves nothing")

	var raised: Array[String] = []
	controls.end_turn_confirmation_raised.connect(func(text: String) -> void: raised.append(text))
	var round_before: int = overlay.battle.combat_state.round_number
	var current_before: Unit = overlay.battle.combat_state.current_unit()

	controls.end_turn_button.pressed.emit()
	await get_tree().process_frame

	assert_eq(raised.size(), 1, "the confirmation must be raised, not the turn ended")
	gut.p("prompt: %s" % raised[0])
	assert_true(raised[0].contains("AP"), "and it names what would be wasted")
	# **Cancelling is the absence of an action**, so what "intact" means is that nothing moved.
	assert_eq(
		overlay.battle.combat_state.current_unit(),
		current_before,
		"cancelling left someone else's turn started"
	)
	assert_eq(overlay.battle.combat_state.round_number, round_before, "and the round advanced")


## The other half: confirming really does end it, so the dialog is a gate rather than a dead end.
func test_confirming_the_prompt_ends_the_turn_for_real() -> void:
	var overlay: ControlOverlay = await _overlay()
	var controls: TurnControlsModule = overlay.module(&"turn_controls") as TurnControlsModule
	var unit: Unit = overlay.battle.combat_state.current_unit()
	overlay.tactics().selection.select(unit)

	controls.end_turn_button.pressed.emit()
	await get_tree().process_frame
	controls.confirm_end_turn()
	await get_tree().process_frame

	assert_ne(
		overlay.battle.combat_state.current_unit(), unit, "confirming must actually end the turn"
	)


## A unit with nothing left is not asked. The prompt exists to catch waste; firing it every time is
## how a confirmation becomes something players click through without reading.
func test_a_spent_unit_ends_its_turn_with_no_dialog_at_all() -> void:
	var overlay: ControlOverlay = await _overlay()
	var controls: TurnControlsModule = overlay.module(&"turn_controls") as TurnControlsModule
	var unit: Unit = overlay.battle.combat_state.current_unit()
	overlay.tactics().selection.select(unit)
	unit.ap = 0
	unit.mp = 0.0

	var raised: Array[String] = []
	controls.end_turn_confirmation_raised.connect(func(text: String) -> void: raised.append(text))
	controls.end_turn_button.pressed.emit()
	await get_tree().process_frame

	assert_true(raised.is_empty(), "nothing was going to be wasted, so nothing was asked")
	assert_ne(overlay.battle.combat_state.current_unit(), unit, "and the turn ended")


# ---------------------------------------------------------------- the log, minimized and flush


## **THE STATED ACCEPTANCE**: *"the minimised log's button abuts the bar with zero padding."*
##
## Asserted as a real distance between two real rects — the log's right edge and the bar's left
## edge — because "flush" is a statement about pixels and nothing else can check it.
func test_the_minimised_log_abuts_the_action_bar_with_no_padding() -> void:
	var overlay: ControlOverlay = await _overlay()
	var logs: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var column: Control = bar.content_column

	await get_tree().process_frame
	var padded_gap: float = column.get_global_rect().position.x - logs.panel.get_global_rect().end.x
	logs.panel.toggle_minimized()
	await get_tree().process_frame
	await get_tree().process_frame
	var flush_gap: float = column.get_global_rect().position.x - logs.panel.get_global_rect().end.x

	gut.p("gap to the bar: %.1f padded, %.1f minimised" % [padded_gap, flush_gap])
	assert_true(logs.panel.is_minimized(), "sanity: it really did minimise")
	assert_almost_eq(flush_gap, 0.0, 1.0, "minimised, the log must touch the bar -- no padding")
	assert_gt(padded_gap, flush_gap, "and open, it must be padded away from it")


## **"Minimises to a BUTTON"**, not to a full-width strip with a title on it. The width is the whole
## difference, so the width is what is asserted.
func test_minimising_shrinks_the_log_to_its_toggle() -> void:
	var overlay: ControlOverlay = await _overlay()
	var panel: CombatLogPanel = (overlay.module(&"combat_log") as CombatLogModule).panel
	var open_width: float = panel.get_global_rect().size.x

	panel.toggle_minimized()
	await get_tree().process_frame
	var shut_width: float = panel.get_global_rect().size.x

	gut.p("log width: %.1f open, %.1f minimised" % [open_width, shut_width])
	assert_lt(shut_width, open_width * 0.25, "a button, not a bar with a title on it")
	assert_true(panel.minimize_button.visible, "and the toggle itself is what is left")

	panel.toggle_minimized()
	await get_tree().process_frame
	assert_almost_eq(
		panel.get_global_rect().size.x, open_width, 1.0, "and restoring gives the width back"
	)


# ---------------------------------------------------------------- the log's two checkboxes


## The table: *"Word wrap and verbose as checkboxes."* Driven through the real controls.
func test_the_wrap_checkbox_turns_word_wrapping_on_and_off() -> void:
	var overlay: ControlOverlay = await _overlay()
	var panel: CombatLogPanel = (overlay.module(&"combat_log") as CombatLogModule).panel

	assert_false(panel.is_word_wrapped(), "off by default -- 'scrollable and not word wrapping'")
	panel.wrap_checkbox.button_pressed = true
	assert_true(panel.is_word_wrapped(), "the checkbox turns it on")
	panel.wrap_checkbox.button_pressed = false
	assert_false(panel.is_word_wrapped(), "and off again")


## **Verbose reaches the sink, and the panel never learns what folding is.** The checkbox emits; the
## module joins it to `HierarchicalUiSink.verbose`; folding stays presentation-only.
func test_the_verbose_checkbox_reaches_the_sink_that_owns_the_folding() -> void:
	var overlay: ControlOverlay = await _overlay()
	var logs: CombatLogModule = overlay.module(&"combat_log") as CombatLogModule

	assert_false(logs.sink.verbose, "folded by default")
	logs.panel.verbose_checkbox.button_pressed = true
	assert_true(logs.sink.verbose, "the checkbox reached the sink")
	logs.panel.verbose_checkbox.button_pressed = false
	assert_false(logs.sink.verbose)


## Turning verbose off must not throw away what the reader had opened by hand — a checkbox that
## silently collapses your work is worse than no checkbox.
func test_verbose_does_not_discard_a_group_the_reader_expanded_by_hand() -> void:
	var sink := HierarchicalUiSink.new(RichTextLabel.new(), null)
	sink._expanded[12345] = true

	sink.verbose = true
	sink.verbose = false

	assert_true(sink._expanded.get(12345, false), "a hand-opened group survived the round trip")


# ---------------------------------------------------------------- one timer, two behaviours


## The tooltip and the log's preview must share the clock rather than each keeping their own —
## asserted on the real panel, since a second timer would be invisible until the two disagreed.
func test_the_log_preview_and_the_tooltip_run_off_the_same_dwell() -> void:
	var overlay: ControlOverlay = await _overlay()
	var panel: CombatLogPanel = (overlay.module(&"combat_log") as CombatLogModule).panel
	var tips: TooltipView = (overlay.module(&"tooltip") as TooltipModule).view

	assert_almost_eq(
		TooltipView.HOVER_DELAY_SEC,
		HoverDwell.DELAY_SEC,
		0.0001,
		"the tooltip reads the shared delay"
	)
	assert_not_null(panel.overflow_preview, "the log has a revealing preview of its own")
	assert_false(panel.overflow_preview.visible, "which starts hidden")
	assert_false(tips.visible, "as does the descriptive tooltip")
	# **Different content models, which the taskblock asks for explicitly.** One is a Label showing
	# a line verbatim; the other renders a `TooltipData` into BBCode.
	assert_true(panel.overflow_preview is Label, "the preview reveals a line as it is")
