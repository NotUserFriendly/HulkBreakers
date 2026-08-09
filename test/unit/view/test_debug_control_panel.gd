extends GutTest

## taskblock-30 follow-up (supervisor report): the panel had no anchor at
## all, so a freshly opened panel sat at the top-left corner, directly on
## top of the existing top-left HUD (`controls`/`tunables` in both
## overlays). CLAUDE.md's own view-math rule applies: build the real node,
## read `position`/`size` back — don't re-derive the centering formula in
## the test.
##
## taskblock-30 follow-up #2 (supervisor): "keep an active thing in
## memory," "move needs the cell coords option AND a move-to-next-cell-
## clicked ability," "generalize move unit to move object," "the verb list
## should scroll, on the left, with the active target above the control
## panel." `FakeInputOwner` below is a minimal stand-in for whichever real
## `board_clicked`/`input_capture_mode` owner (`TacticsController`/
## `BoardInspectModule`) is live — the panel is duck-typed against that
## shape on purpose (its own header comment), so a fake with the same two
## members drives it exactly the same way the real ones do.


## Minimal duck-typed stand-in for `TacticsController`/`BoardInspectModule`'s
## own `board_clicked`/`input_capture_mode` — see this file's own header.
class FakeInputOwner:
	extends RefCounted
	signal board_clicked(hit: Dictionary)
	var input_capture_mode: bool = false


func _make_state() -> CombatState:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)
	return CombatState.new(Grid.new(5, 5), [unit])


## `input_owner` defaults to a fresh `FakeInputOwner` — `setup()` always
## arms active-target tracking against it immediately (this panel's own
## `_arm_active_tracking`), so ANY caller needs the real duck-typed shape,
## not just tests that exercise picking directly.
func _open_panel(input_owner: Object = FakeInputOwner.new()) -> DebugControlPanel:
	var panel := DebugControlPanel.new()
	add_child_autofree(panel)
	panel.setup(BoutInjector.new(_make_state()), DeepStrike.reference_humanoid_pool(), input_owner)
	return panel


## `DebugVerbs.all()` is the one authority for ordering — a test must
## never hardcode an index, same convention the overlay tests already use.
func _verb_index(verb_id: StringName) -> int:
	var verbs: Array[DebugVerbSpec] = DebugVerbs.all()
	for i in range(verbs.size()):
		if verbs[i].id == verb_id:
			return i
	fail_test("no verb %s in DebugVerbs.all()" % verb_id)
	return -1


## `_center_top()` reads `size`, which only reflects real content after a
## layout pass — same reasoning as InspectPanel's own clamp test: pin
## `size` to a known value first rather than race the engine's own layout
## timing. Godot itself enforces `custom_minimum_size` synchronously on
## assignment, so a requested size BELOW that floor is silently raised —
## reading `panel.size` back right after assigning it (never re-deriving
## the panel's own minimum-width number here) is what's actually forced,
## the same "read the real node back" discipline as everywhere else.
func test_center_top_pins_the_panel_to_a_fixed_top_margin() -> void:
	var panel := _open_panel()
	panel.size = Vector2(600.0, 200.0)

	panel._center_top()

	assert_eq(panel.position.y, DebugControlPanel.TOP_MARGIN)


func test_center_top_horizontally_centers_the_panel_in_the_real_viewport() -> void:
	var panel := _open_panel()
	panel.size = Vector2(600.0, 200.0)
	var actual_width: float = panel.size.x

	panel._center_top()

	var viewport_size: Vector2 = panel.get_viewport_rect().size
	assert_eq(panel.position.x, (viewport_size.x - actual_width) / 2.0)


## A window resized while the panel is open must re-center, not stay put
## at an offset computed against the old size.
func test_viewport_resize_recenters_the_panel() -> void:
	var panel := _open_panel()
	panel.size = Vector2(600.0, 200.0)
	panel._center_top()
	var original_x: float = panel.position.x

	panel.position = Vector2(-999.0, 999.0)
	panel._center_top()

	assert_ne(panel.position, Vector2(-999.0, 999.0))
	assert_eq(panel.position.x, original_x)
	assert_eq(panel.position.y, DebugControlPanel.TOP_MARGIN)


## "make the drop down box of debug options a scrolling list ... on the
## left side." An `ItemList` scrolls natively — no wrapping
## ScrollContainer needed — and is on the interactive-widget whitelist
## `test_every_richtextlabel_panel_ignores_the_mouse_except_the_log`
## already checks against, so its own default STOP filter is expected,
## not a lint offender.
func test_verb_picker_is_a_real_scrolling_item_list() -> void:
	var panel := _open_panel()

	assert_true(panel._verb_list is ItemList)
	# Every verb, plus taskblock-51's one non-verb category at the end.
	assert_eq(panel._verb_list.item_count, DebugVerbs.all().size() + 1)


## "whatever is selected in the list ... populates what's in the control
## panel." Selecting a verb by index rebuilds the param rows for THAT
## verb's own params — proven against Move Object's own two params
## (object, to_cell) rather than a hand-counted magic number.
func test_selecting_a_verb_in_the_list_populates_its_own_param_rows() -> void:
	var panel := _open_panel()

	panel._select_verb(_verb_index(&"move_object"))

	assert_eq(
		panel._param_container.get_child_count(), 3, "object row + to_cell row + Move On Next Click"
	)
	assert_true(panel._param_controls.has(&"to_cell"), "to_cell keeps its own manual X/Y entry")
	assert_false(
		panel._param_controls.has(&"object"),
		"object always resolves from Active Target, never a widget"
	)


## "the active thing ... can go above the control panel part." The label
## exists and starts empty before any click.
func test_active_label_starts_as_none() -> void:
	var panel := _open_panel()

	assert_eq(panel._active_label.text, "Active: none")


## "click a cell, and it has that cell in memory. Click a bot and it has
## that bot in memory." Every board click while the panel is open updates
## `_active` — not just a field's own "Pick" press.
func test_a_board_click_while_open_sets_the_active_target() -> void:
	var owner := FakeInputOwner.new()
	var panel := _open_panel(owner)
	var state: CombatState = panel.combat_state
	var target: Unit = state.units[0]

	owner.board_clicked.emit({"kind": Enums.HitKind.UNIT, "unit": target, "cell": target.cell})

	assert_eq(panel._active.get("unit"), target)
	assert_eq(panel._active_label.text, "Active: Unit #%d @ %s" % [target.id, target.cell])

	owner.board_clicked.emit({"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(3, 3)})

	assert_eq(panel._active.get("kind"), Enums.HitKind.CELL)
	assert_eq(panel._active_label.text, "Active: Cell %s" % [Vector2i(3, 3)])


## A miss (off the board entirely) must never wipe a real target already
## in memory.
func test_a_missed_click_never_clears_an_existing_active_target() -> void:
	var owner := FakeInputOwner.new()
	var panel := _open_panel(owner)
	var target: Unit = panel.combat_state.units[0]
	owner.board_clicked.emit({"kind": Enums.HitKind.UNIT, "unit": target, "cell": target.cell})

	owner.board_clicked.emit({})

	assert_eq(panel._active.get("unit"), target)


## The panel arms `input_capture_mode` for as long as it's visible, and
## disarms it the instant it's closed — a debug panel left open must never
## silently keep eating ordinary board clicks after the operator hides it.
func test_input_capture_mode_follows_the_panels_own_visibility() -> void:
	var owner := FakeInputOwner.new()
	var panel := _open_panel(owner)

	assert_true(owner.input_capture_mode, "sanity: armed while the panel starts visible")

	panel.visible = false
	assert_false(owner.input_capture_mode)

	panel.visible = true
	assert_true(owner.input_capture_mode)


func _select_move_object(panel: DebugControlPanel) -> void:
	panel._select_verb(_verb_index(&"move_object"))


## "generalize move unit to move object, so I can move cover, units, or
## dropped objects" + "move needs to keep the cell coords option" — the
## ordinary Apply path, driven entirely off the active target and the
## to_cell param's own manual X/Y fields, exactly like every other verb.
func test_move_object_via_apply_uses_the_active_target_and_manual_cell_entry() -> void:
	var owner := FakeInputOwner.new()
	var panel := _open_panel(owner)
	var unit: Unit = panel.combat_state.units[0]
	owner.board_clicked.emit({"kind": Enums.HitKind.UNIT, "unit": unit, "cell": unit.cell})
	_select_move_object(panel)
	var cell_fields: Array = panel._param_controls[&"to_cell"]
	(cell_fields[0] as SpinBox).value = 4
	(cell_fields[1] as SpinBox).value = 4

	panel._on_apply_pressed()

	assert_eq(unit.cell, Vector2i(4, 4))


func test_move_object_via_apply_refuses_with_no_active_target() -> void:
	var panel := _open_panel()
	_select_move_object(panel)
	var cell_fields: Array = panel._param_controls[&"to_cell"]
	(cell_fields[0] as SpinBox).value = 4
	(cell_fields[1] as SpinBox).value = 4

	panel._on_apply_pressed()

	assert_eq(panel._status_label.text, "Move Object: no object found")


## "move needs ... a 'move to next cell clicked' ability." A dedicated
## button, only shown for this verb, that applies the move the instant a
## destination cell lands — no separate Apply press.
func test_move_on_next_click_button_exists_only_for_move_object() -> void:
	var panel := _open_panel()

	_select_move_object(panel)
	assert_not_null(_find_button(panel._param_container, "Move On Next Click"))

	panel._select_verb(_verb_index(&"force_current_unit"))
	assert_null(_find_button(panel._param_container, "Move On Next Click"))


func _find_button(container: Node, text: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and (child as Button).text == text:
			return child
	return null


func test_move_on_next_click_applies_immediately_on_the_next_board_click() -> void:
	var owner := FakeInputOwner.new()
	var panel := _open_panel(owner)
	var unit: Unit = panel.combat_state.units[0]
	owner.board_clicked.emit({"kind": Enums.HitKind.UNIT, "unit": unit, "cell": unit.cell})
	_select_move_object(panel)
	var applied_signal := [null, {}]
	panel.applied.connect(
		func(verb_id: StringName, args: Dictionary, _events: Array[LogEvent]) -> void:
			applied_signal[0] = verb_id
			applied_signal[1] = args
	)

	_find_button(panel._param_container, "Move On Next Click").pressed.emit()
	owner.board_clicked.emit({"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)})

	assert_eq(unit.cell, Vector2i(2, 2), "the move applied without a separate Apply press")
	assert_eq(applied_signal[0], &"move_object")
	assert_eq(panel._status_label.text, "Move Object: applied")


## The destination click that completes a move-on-next-click also feeds
## the always-on active-target tracker — the object being moved is
## snapshotted BEFORE that click lands, so it can't shift out from under
## itself, but the click itself still legitimately becomes the new active
## target afterward (it's the last real thing clicked).
func test_move_on_next_click_snapshots_the_object_before_the_destination_click_lands() -> void:
	var owner := FakeInputOwner.new()
	var panel := _open_panel(owner)
	var unit: Unit = panel.combat_state.units[0]
	owner.board_clicked.emit({"kind": Enums.HitKind.UNIT, "unit": unit, "cell": unit.cell})
	_select_move_object(panel)

	_find_button(panel._param_container, "Move On Next Click").pressed.emit()
	owner.board_clicked.emit({"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(2, 2)})

	assert_eq(
		unit.cell, Vector2i(2, 2), "moved the unit that was active BEFORE the destination click"
	)
	assert_eq(
		panel._active.get("cell"), Vector2i(2, 2), "the destination click is now the active target"
	)


func test_move_on_next_click_refuses_with_no_active_target() -> void:
	var panel := _open_panel()
	_select_move_object(panel)

	_find_button(panel._param_container, "Move On Next Click").pressed.emit()

	assert_eq(panel._status_label.text, "Move Object: no active target set")


## Stands in for `CameraRig`: same input stage, records what reached it.
class UnhandledWheelSpy:
	extends Node

	var wheels: Array[int] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.pressed:
				wheels.append(button.button_index)


func _wheel_at(button_index: MouseButton, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = at
	get_viewport().push_input(event)


## BR30.05, symptom 1: "clicking within the debug menu itself can also select a
## world cell." The panel draws a real opaque background (`HulkTheme` gives
## every `PanelContainer` one), so it must take what lands on it — taskblock-07
## Pass B4's "a plain container has no click of its own" rule was written about
## genuinely invisible containers and does not fit this one.
func test_the_panel_blocks_clicks_because_it_draws_a_real_background() -> void:
	var panel: DebugControlPanel = _open_panel()
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)


## Guards the wheel tests below against passing vacuously.
func test_the_spy_does_see_a_wheel_that_misses_the_panel() -> void:
	var spy := UnhandledWheelSpy.new()
	add_child_autofree(spy)
	var panel: DebugControlPanel = _open_panel()
	await get_tree().process_frame
	await get_tree().process_frame

	_wheel_at(MOUSE_BUTTON_WHEEL_DOWN, panel.get_global_rect().end + Vector2(400.0, 400.0))

	assert_eq(spy.wheels.size(), 1, "a wheel away from the panel does reach the camera stage")


## BR30.05, symptom 2: "once the verb list's own `ItemList` is scrolled to the
## bottom, further scroll input bleeds through and zooms the world camera
## instead of stopping at the list's own end."
func test_scrolling_the_verb_list_never_reaches_the_camera() -> void:
	var spy := UnhandledWheelSpy.new()
	add_child_autofree(spy)
	var panel: DebugControlPanel = _open_panel()
	await get_tree().process_frame
	await get_tree().process_frame

	var over_the_list: Vector2 = panel._verb_list.get_global_rect().get_center()
	for _i in range(6):
		_wheel_at(MOUSE_BUTTON_WHEEL_DOWN, over_the_list)
	for _i in range(6):
		_wheel_at(MOUSE_BUTTON_WHEEL_UP, over_the_list)

	assert_eq(
		spy.wheels, [] as Array[int], "past both ends of the list, the panel still absorbs it"
	)


func test_the_verb_list_still_scrolls() -> void:
	var panel: DebugControlPanel = _open_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var bar: VScrollBar = panel._verb_list.get_v_scroll_bar()
	if bar.max_value <= bar.page:
		pass_test("the verb list fits without scrolling in this layout — nothing to check")
		return
	bar.value = 0.0

	_wheel_at(MOUSE_BUTTON_WHEEL_DOWN, panel._verb_list.get_global_rect().get_center())
	await get_tree().process_frame

	assert_gt(bar.value, 0.0, "absorbed BY scrolling, not instead of it")


## Consuming the wheel wholesale would silently delete `SpinBox`'s own
## wheel-to-adjust. The panel forwards to whatever is under the cursor first.
func test_a_spin_box_still_adjusts_on_the_wheel() -> void:
	var panel: DebugControlPanel = _open_panel()
	panel._select_verb(_verb_index(&"set_ap"))
	await get_tree().process_frame
	await get_tree().process_frame

	var spin: SpinBox = _first_spin_box(panel)
	if spin == null:
		pass_test("no SpinBox on this verb's form — nothing to check")
		return
	spin.value = 5.0
	var before: float = spin.value

	_wheel_at(MOUSE_BUTTON_WHEEL_UP, spin.get_global_rect().get_center())
	await get_tree().process_frame

	assert_ne(spin.value, before, "the wheel still reaches the widget that wanted it")


func _first_spin_box(node: Node) -> SpinBox:
	if node is SpinBox:
		return node as SpinBox
	for child: Node in node.get_children():
		var found: SpinBox = _first_spin_box(child)
		if found != null:
			return found
	return null


## **Cover must not read as the cell beneath it.** The label special-cased units and called
## everything else a cell, so clicking a barrel showed "Active: Cell (2, 2)" and there was
## no way to tell whether the panel held the barrel or the floor — which is how `BR51.02`
## looked like a broken verb rather than a mislabelled target.
func test_a_cover_click_is_named_by_its_part_not_by_its_cell() -> void:
	var panel: DebugControlPanel = _open_panel()
	var cover := Part.new()
	cover.id = &"goo_barrel"

	panel._on_active_target_clicked(
		{"kind": Enums.HitKind.PART, "unit": null, "part": cover, "cell": Vector2i(2, 2)}
	)

	var label: String = panel._active_label.text
	assert_true(label.contains("goo_barrel"), "the label names the part: %s" % label)
	assert_false(label.begins_with("Active: Cell"), "and does not read as the bare cell")


## A genuinely bare cell still reads as a cell — widening what the label recognises must
## not make every click claim to have hit something.
func test_a_bare_cell_click_still_reads_as_a_cell() -> void:
	var panel: DebugControlPanel = _open_panel()

	panel._on_active_target_clicked(
		{"kind": Enums.HitKind.CELL, "unit": null, "cell": Vector2i(4, 4)}
	)

	assert_true(panel._active_label.text.begins_with("Active: Cell"))


# --- taskblock-51: the UI element category ------------------------------------------


func _ui_entry_index(panel: DebugControlPanel) -> int:
	return panel._verbs.size()


## **The category has its own entry in the list**, after every verb. The supervisor's call,
## and it is the shape the panel already had: a two-column layout is a list and a pane, and a
## control belonging to neither a verb nor the panel chrome has nowhere honest to go. A first
## attempt put the checkbox in the pane directly, where it captioned every verb in the list.
func test_the_ui_element_category_is_a_list_entry() -> void:
	var panel: DebugControlPanel = _open_panel()
	var index: int = _ui_entry_index(panel)

	assert_eq(panel._verb_list.item_count, panel._verbs.size() + 1, "one entry past the verbs")
	assert_eq(panel._verb_list.get_item_text(index), DebugControlPanel.UI_ELEMENT_ENTRY)


## Selecting it fills the same pane every verb uses — one checkbox per table row, no verb
## parameters, and nothing from the previously selected verb left behind.
func test_selecting_it_shows_a_box_per_registered_element() -> void:
	var panel: DebugControlPanel = _open_panel()

	panel._select_verb(_ui_entry_index(panel))

	var boxes: Array[Node] = []
	for child: Node in panel._param_container.get_children():
		if child is CheckBox:
			boxes.append(child)
	assert_eq(boxes.size(), DebugUiElements.all().size(), "one box per registered element")
	assert_true(panel._param_controls.is_empty(), "and no verb parameters are left standing")
	assert_eq(
		(boxes[0] as CheckBox).text,
		DebugUiElements.find(DebugUiElements.PERF_PANEL).label,
		"labelled from the table, not from this file"
	)


## **Ticking a box emits the element's id, not a per-element signal.** The overlay owns the
## node and maps the id to it; a signal per element would put the panel back in the business
## of knowing what a performance readout is.
func test_ticking_a_box_emits_the_element_id() -> void:
	var panel: DebugControlPanel = _open_panel()
	panel._select_verb(_ui_entry_index(panel))
	var seen: Array = []
	panel.ui_element_toggled.connect(
		func(element: StringName, shown: bool) -> void: seen.append([element, shown])
	)

	var box: CheckBox = panel._ui_element_boxes[DebugUiElements.PERF_PANEL]
	box.button_pressed = true

	assert_eq(seen.size(), 1, "one emission")
	assert_eq(seen[0][0], DebugUiElements.PERF_PANEL)
	assert_true(seen[0][1], "switched on")
	assert_true(panel.is_ui_element_shown(DebugUiElements.PERF_PANEL))


## **The state lives in the panel, not in the checkbox.** The right-hand pane is torn down and
## rebuilt on every verb switch, so a box holding its own state would silently forget every
## time the operator looked at another verb — and the readout would still be on screen,
## disagreeing with its own switch.
func test_the_switch_survives_looking_at_another_verb() -> void:
	var panel: DebugControlPanel = _open_panel()
	panel._select_verb(_ui_entry_index(panel))
	panel._ui_element_boxes[DebugUiElements.PERF_PANEL].button_pressed = true

	panel._select_verb(_verb_index(&"force_current_unit"))
	panel._select_verb(_ui_entry_index(panel))

	assert_true(
		panel.is_ui_element_shown(DebugUiElements.PERF_PANEL), "the panel still knows it is on"
	)
	assert_true(
		panel._ui_element_boxes[DebugUiElements.PERF_PANEL].button_pressed,
		"and the rebuilt box shows it",
	)


## Rebuilding the box must not re-announce a state nothing changed — an overlay listening for
## the toggle would re-show an element the operator had already dismissed.
func test_rebuilding_the_pane_emits_nothing() -> void:
	var panel: DebugControlPanel = _open_panel()
	panel._select_verb(_ui_entry_index(panel))
	panel._ui_element_boxes[DebugUiElements.PERF_PANEL].button_pressed = true
	var emissions: Array[int] = [0]
	panel.ui_element_toggled.connect(func(_e: StringName, _s: bool) -> void: emissions[0] += 1)

	panel._select_verb(_verb_index(&"force_current_unit"))
	panel._select_verb(_ui_entry_index(panel))

	assert_eq(emissions[0], 0, "restoring a box's state is not a change")


## **Apply is disabled here, not silently inert.** Switching a readout on is not an injection;
## a button that does nothing when pressed is the exact failure this project keeps filing.
func test_apply_is_disabled_for_the_ui_category() -> void:
	var panel: DebugControlPanel = _open_panel()

	panel._select_verb(_ui_entry_index(panel))
	assert_true(panel._apply_button.disabled, "nothing to apply")

	panel._select_verb(_verb_index(&"force_current_unit"))
	assert_false(panel._apply_button.disabled, "and it comes back for a real verb")


## Pressing Apply on the category cannot reach a verb — the index is past the end of the
## table. Asserted directly because the guard is an inequality that a later insertion could
## quietly invalidate.
func test_apply_on_the_category_applies_no_verb() -> void:
	var panel: DebugControlPanel = _open_panel()
	var applied: Array[int] = [0]
	panel.applied.connect(
		func(_id: StringName, _args: Dictionary, _events: Array[LogEvent]) -> void: applied[0] += 1
	)

	panel._select_verb(_ui_entry_index(panel))
	panel._on_apply_pressed()

	assert_eq(applied[0], 0, "no verb ran")


## **A verb given a target it cannot use reports a refusal, and names it.** Pass K's rule:
## declining must be explicit and visible, because half the symptoms it was written for were
## things silently doing nothing. Asserted rather than assumed — the "refused" path already
## existed, but nothing proved it survived widening what a target can be.
func test_a_verb_refusing_an_unsupported_target_says_what_it_refused() -> void:
	var panel: DebugControlPanel = _open_panel()
	panel._select_verb(_verb_index(&"set_part_hp"))
	# A bare cell with nothing standing on it — a legal target shape the verb cannot act on.
	panel._active = SelectionTarget.for_cell(Vector2i(4, 4)).to_hit()

	panel._on_apply_pressed()

	gut.p("status: %s" % panel._status_label.text)
	assert_true(panel._status_label.text.contains("refused"), "it declined out loud")
	assert_true(panel._status_label.text.contains("cell (4, 4)"), "and named the target")


## A verb that does not act on the active item must not name it — that would report the wrong
## cause for its own failure.
func test_a_non_object_verb_does_not_blame_the_active_target() -> void:
	var panel: DebugControlPanel = _open_panel()
	panel._active = SelectionTarget.for_cell(Vector2i(4, 4)).to_hit()

	panel._select_verb(_verb_index(&"force_current_unit"))
	var suffix: String = panel._refused_target_suffix(
		panel._verbs[_verb_index(&"force_current_unit")]
	)

	assert_eq(suffix, "", "it never touched the active item")


# --- taskblock-61 Pass E3 (BR51.21): the channel that lets an injection animate ---------


## A board with a real volatile barrel on it, which is the entry's own reproduction: *"forcing a
## detonation... there is no visible explosion animation."* A bare `Part.new()` unit is enough for
## every other test in this file and is deliberately not enough here — the whole question is
## whether a verb's *effects* reach the signal, so the verb has to have some.
func _open_panel_with_a_barrel(cell: Vector2i) -> DebugControlPanel:
	var root := Part.new()
	root.hp = 5
	root.max_hp = 5
	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var injector := BoutInjector.new(state)
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	assert_not_null(barrel, "sanity: the shipped volatile barrel must load")
	assert_true(
		injector.place_cover(cell, &"goo_barrel", {&"goo_barrel": barrel.duplicate(true)}),
		"sanity: a barrel is on the board"
	)

	var panel := DebugControlPanel.new()
	add_child_autofree(panel)
	panel.setup(injector, DeepStrike.reference_humanoid_pool(), FakeInputOwner.new())
	return panel


## `BR51.21` — **no injection ever animated, and the missing piece was a channel, not a call.**
##
## A forced detonation, move or kill snapped the board and played nothing. The capability was never
## absent: `ResolutionModule.play(events)` animates a specific event list and both real resolution
## paths already use it. What was absent is that `applied` fires *after* the verb has run, so
## nothing downstream could recover the events it produced — there was nowhere to get them from.
##
## This pins the channel at its source. Without `_capture` the signal carries two arguments and
## this does not even compile.
func test_a_verb_that_causes_effects_hands_them_to_the_applied_signal() -> void:
	var cell := Vector2i(3, 3)
	var panel: DebugControlPanel = _open_panel_with_a_barrel(cell)
	var carried: Array[LogEvent] = []
	panel.applied.connect(
		func(_id: StringName, _args: Dictionary, events: Array[LogEvent]) -> void:
			carried.assign(events)
	)

	panel._select_verb(_verb_index(&"set_part_hp"))
	panel._active = SelectionTarget.for_cell(cell).to_hit()
	_fill_set_part_hp(panel, &"", 0)
	panel._on_apply_pressed()

	gut.p("status: %s" % panel._status_label.text)
	gut.p("%d events carried: %s" % [carried.size(), _kinds_of(carried)])
	assert_true(panel._status_label.text.contains("applied"), "sanity: the verb actually ran")
	assert_false(
		carried.is_empty(),
		"a forced detonation has effects; the injection has nothing to animate without them"
	)
	for event: LogEvent in carried:
		assert_false(
			InjectionEvents.AUDIT_KINDS.has(event.kind),
			(
				(
					"%s is bookkeeping ABOUT the injection, not an effect of it — handing it to the "
					+ "resolution player would flash the banner for a verb that did nothing visible"
				)
				% event.kind
			)
		)


## The other half, and the reason `InjectionEvents.effects` exists at all: **every verb emits
## `command`, `command_outcome` and `inject` whether or not it changed anything**, so a raw capture
## is never empty. Filtering the bookkeeping out is what makes an empty list mean what it says —
## and an empty list is what lets *"which verbs animate"* be a property of the verb's own output
## rather than a table somebody has to keep in step with `DebugVerbs`.
func test_a_verb_that_changes_nothing_carries_an_empty_list_rather_than_its_own_bookkeeping(
) -> void:
	var panel: DebugControlPanel = _open_panel()
	var seen: Array[int] = []
	panel.applied.connect(
		func(_id: StringName, _args: Dictionary, events: Array[LogEvent]) -> void:
			seen.append(events.size())
	)

	panel._select_verb(_verb_index(&"force_current_unit"))
	panel._on_apply_pressed()

	assert_eq(seen.size(), 1, "sanity: the verb applied and the signal fired")
	assert_eq(seen[0], 0, "its three bookkeeping lines are not effects and must not be carried")


## **The sink is removed whether or not the verb succeeds.** A `MemorySink` left attached would
## collect every event for the rest of the battle, which is the exact leak `CombatLog.remove_sink`
## documents itself against — and a refusal is the path most likely to skip a cleanup, so it is the
## one worth pinning.
func test_the_capture_sink_is_detached_even_when_the_verb_refuses() -> void:
	var panel: DebugControlPanel = _open_panel()
	var stream: CombatLog = panel.combat_state.combat_log
	var before: int = stream._sinks.size()

	panel._select_verb(_verb_index(&"set_part_hp"))
	panel._active = SelectionTarget.for_cell(Vector2i(4, 4)).to_hit()
	panel._on_apply_pressed()

	assert_true(panel._status_label.text.contains("refused"), "sanity: this path refuses")
	assert_eq(
		stream._sinks.size(), before, "the capture sink must not outlive the call that made it"
	)


## Fills whichever widgets the `set_part_hp` param row built, by walking the real container rather
## than assuming an index — the param pane is rebuilt per verb and its layout is not this test's
## business.
func _fill_set_part_hp(panel: DebugControlPanel, part_id: StringName, hp: int) -> void:
	for row: Node in panel._param_container.get_children():
		for child: Node in row.get_children():
			if child is LineEdit:
				(child as LineEdit).text = String(part_id)
			elif child is SpinBox:
				(child as SpinBox).value = hp


func _kinds_of(events: Array[LogEvent]) -> String:
	var kinds := PackedStringArray()
	for event: LogEvent in events:
		kinds.append(String(event.kind))
	return ", ".join(kinds)
