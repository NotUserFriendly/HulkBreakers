extends GutTest

## taskblock-30 follow-up (supervisor report): the panel had no anchor at
## all, so a freshly opened panel sat at the top-left corner, directly on
## top of the existing top-left HUD (`controls`/`tunables` in both
## overlays). CLAUDE.md's own view-math rule applies: build the real node,
## read `position`/`size` back — don't re-derive the centering formula in
## the test.
##
## taskblock-30 follow-up #2 (supervisor): "keep an active thing in
## memory," "move needs the cell coords option AND a move-to-next-tile-
## clicked ability," "generalize move unit to move object," "the verb list
## should scroll, on the left, with the active target above the control
## panel." `FakeInputOwner` below is a minimal stand-in for whichever real
## `board_clicked`/`input_capture_mode` owner (`TacticsController`/
## `SpectatorOverlay`) is live — the panel is duck-typed against that
## shape on purpose (its own header comment), so a fake with the same two
## members drives it exactly the same way the real ones do.


## Minimal duck-typed stand-in for `TacticsController`/`SpectatorOverlay`'s
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
	assert_eq(panel._verb_list.item_count, DebugVerbs.all().size())


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


## "click a tile, and it has that tile in memory. Click a bot and it has
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


## "move needs ... a 'move to next tile clicked' ability." A dedicated
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
		func(verb_id: StringName, args: Dictionary) -> void:
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
