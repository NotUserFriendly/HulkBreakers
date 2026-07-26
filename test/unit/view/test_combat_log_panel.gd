extends GutTest

## taskblock-41 Pass F follow-up: the scroll hand-off has to be verified
## against a REAL panel in a REAL tree with a REAL wheel event, not against the
## threshold rule alone. `LogScrollHandoff` was already unit-tested and correct
## — and the hand-off still did not work, because the event never reached the
## code that consulted it. That is exactly the "read the real node back, don't
## re-derive it" case docs/00 warns about, in event-routing form.


func _panel_in_tree() -> CombatLogPanel:
	var panel := CombatLogPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(panel)
	return panel


func _fill(panel: CombatLogPanel, lines: int) -> void:
	var text := PackedStringArray()
	for i in range(lines):
		text.append("log line %d" % i)
	panel.log_label.text = "\n".join(text)


## The load-bearing state: is the LOG transparent for this event. The panel
## container itself is always IGNORE (it draws nothing — see its own comment),
## so it is not the thing to read.
func _handed_off(panel: CombatLogPanel) -> bool:
	return panel.log_label.mouse_filter == Control.MOUSE_FILTER_IGNORE


func _over_the_log(panel: CombatLogPanel) -> Vector2:
	return panel.log_label.get_global_rect().get_center()


func _wheel(button_index: MouseButton, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = at
	return event


## **Why these read `mouse_filter` rather than `is_input_handled()`.** The
## obvious observable — "was the event left unhandled" — is not usable here:
## GUT's own runner UI shares the viewport and marks mouse events handled
## itself, so that flag reports the harness, not the panel. What actually
## matters, and what the camera actually depends on, is whether the panel made
## itself transparent for that event. That is real state on a real node after a
## real wheel event, read back rather than re-derived.


## The load-bearing one. With the log scrolled to its end, a further wheel-down
## must leave the panel click-through so the event reaches the camera. A panel
## that stays opaque turns part of the screen into a dead zone where zoom
## silently stops working.
func test_a_wheel_at_the_end_of_the_content_hands_the_panel_over_to_the_camera() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	var bar: VScrollBar = panel.log_label.get_v_scroll_bar()
	bar.value = bar.max_value - bar.page
	await get_tree().process_frame

	get_viewport().push_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel)))

	assert_true(
		_handed_off(panel), "at the bottom the log must go transparent, not dead-stop the wheel"
	)
	assert_eq(
		panel._body.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"and so must the background — a STOP control under the cursor consumes it alone"
	)


func test_a_wheel_mid_content_keeps_the_panel_opaque_so_the_log_scrolls() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	var bar: VScrollBar = panel.log_label.get_v_scroll_bar()
	bar.value = maxf((bar.max_value - bar.page) * 0.5, 1.0)
	await get_tree().process_frame

	get_viewport().push_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel)))

	assert_false(_handed_off(panel), "there is content below — the log keeps the wheel")


func test_a_wheel_up_at_the_top_hands_over() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	panel.log_label.get_v_scroll_bar().value = 0.0
	await get_tree().process_frame

	get_viewport().push_input(_wheel(MOUSE_BUTTON_WHEEL_UP, _over_the_log(panel)))

	assert_true(_handed_off(panel), "nothing above — hand off")


## A nearly-empty log has nothing to scroll at all, so every wheel event over
## it belongs to the camera.
func test_a_log_shorter_than_its_viewport_never_takes_the_wheel() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	_fill(panel, 2)
	await get_tree().process_frame
	await get_tree().process_frame

	get_viewport().push_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel)))

	assert_true(_handed_off(panel))


## A hand-off must never leave the panel click-through for an ordinary click —
## that would make the title bar and the fold's click-to-expand dead.
func test_an_ordinary_click_after_a_hand_off_restores_the_panel() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	_fill(panel, 2)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().push_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel)))
	assert_true(_handed_off(panel), "sanity: handed off")

	get_viewport().push_input(_wheel(MOUSE_BUTTON_LEFT, _over_the_log(panel)))

	assert_false(_handed_off(panel), "a click restores it")
	assert_eq(panel._body.mouse_filter, Control.MOUSE_FILTER_STOP)


## The wheel outside the panel is nobody's business but the camera's, and must
## not leave the panel transparent either.
func test_a_wheel_outside_the_panel_leaves_it_alone() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	var outside: Vector2 = panel.get_global_rect().end + Vector2(200, 200)
	get_viewport().push_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, outside))

	assert_false(_handed_off(panel))


## Supervisor, post-tb41: "~2x as wide as it is currently."
func test_the_panel_asks_for_its_own_width_rather_than_inheriting_the_columns() -> void:
	var panel: CombatLogPanel = _panel_in_tree()
	assert_eq(panel.custom_minimum_size.x, CombatLogPanel.DEFAULT_WIDTH)
	assert_true(CombatLogPanel.DEFAULT_WIDTH >= 500.0, "roughly double the old ~260px column")
