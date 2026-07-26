extends GutTest

## Supervisor correction, post-taskblock-41: **the combat log absorbs the wheel
## whenever the cursor is over it, at the ends of its content too.** Scrolling
## past the bottom must not start zooming the camera. This reverses Pass F's own
## spec ("falls through to the camera rather than dead-stopping"), which had
## reproduced `BR30.05`'s reported behaviour in a second place.
##
## `CameraRig` reads the wheel in `_unhandled_input`, so "did it reach the
## camera" is testable directly with a spy at that same stage — which is what
## these do, rather than asserting on a `mouse_filter` and hoping it means what
## I think it means. Pass F's first version of this file asserted the filter
## because `is_input_handled()` reports GUT's own runner UI; a spy sidesteps
## both problems and tests the actual requirement.


## Stands in for `CameraRig`: same input stage, records what reached it.
class UnhandledWheelSpy:
	extends Node

	var wheels: Array[int] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.pressed:
				wheels.append(button.button_index)


func _panel_and_spy() -> Array:
	var spy := UnhandledWheelSpy.new()
	add_child_autofree(spy)
	var panel := CombatLogPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(panel)
	return [panel, spy]


func _fill(panel: CombatLogPanel, lines: int) -> void:
	var text := PackedStringArray()
	for i in range(lines):
		text.append("log line %d" % i)
	panel.log_label.text = "\n".join(text)


func _over_the_log(panel: CombatLogPanel) -> Vector2:
	return panel.log_label.get_global_rect().get_center()


func _wheel(button_index: MouseButton, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = at
	get_viewport().push_input(event)


## Guards every other test in this file against being vacuously true. If the
## harness swallowed wheel events before `_unhandled_input` regardless of the
## panel, "the camera saw nothing" would pass everywhere and prove nothing.
func test_the_spy_does_see_a_wheel_that_misses_the_panel() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	var spy: UnhandledWheelSpy = built[1]
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(200.0, 100.0)
	await get_tree().process_frame
	await get_tree().process_frame

	_wheel(MOUSE_BUTTON_WHEEL_DOWN, panel.get_global_rect().end + Vector2(300.0, 300.0))

	assert_eq(spy.wheels.size(), 1, "a wheel nowhere near the panel does reach the camera stage")


## The reported bug, directly: hover the log, scroll to the bottom, keep
## scrolling — the camera must not move.
func test_scrolling_past_the_bottom_never_reaches_the_camera() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	var spy: UnhandledWheelSpy = built[1]
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	var bar: VScrollBar = panel.log_label.get_v_scroll_bar()
	bar.value = bar.max_value - bar.page
	await get_tree().process_frame

	for _i in range(5):
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel))

	assert_eq(spy.wheels, [] as Array[int], "the log absorbs the wheel at its own end")


func test_scrolling_past_the_top_never_reaches_the_camera() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	var spy: UnhandledWheelSpy = built[1]
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	panel.log_label.get_v_scroll_bar().value = 0.0
	await get_tree().process_frame

	for _i in range(5):
		_wheel(MOUSE_BUTTON_WHEEL_UP, _over_the_log(panel))

	assert_eq(spy.wheels, [] as Array[int])


## A log with nothing to scroll must still block — it is a solid surface, not a
## conditionally solid one, and "there is nothing left to scroll" is invisible
## to whoever is spinning the wheel.
func test_a_log_shorter_than_its_viewport_still_blocks_the_wheel() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	var spy: UnhandledWheelSpy = built[1]
	_fill(panel, 2)
	await get_tree().process_frame
	await get_tree().process_frame

	_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel))
	_wheel(MOUSE_BUTTON_WHEEL_UP, _over_the_log(panel))

	assert_eq(spy.wheels, [] as Array[int])


## The title bar is part of the same surface — scrolling over it must not zoom
## either, or the panel would have a strip along its top that behaves
## differently from the rest of it.
func test_the_title_bar_blocks_the_wheel_too() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	var spy: UnhandledWheelSpy = built[1]
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	_wheel(MOUSE_BUTTON_WHEEL_DOWN, panel.title_bar.get_global_rect().get_center())

	assert_eq(spy.wheels, [] as Array[int])


## Blocking the camera must not have been achieved by breaking scrolling.
func test_the_log_still_scrolls_mid_content() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	_fill(panel, 200)
	await get_tree().process_frame
	await get_tree().process_frame

	var bar: VScrollBar = panel.log_label.get_v_scroll_bar()
	bar.value = 0.0
	await get_tree().process_frame

	_wheel(MOUSE_BUTTON_WHEEL_DOWN, _over_the_log(panel))
	await get_tree().process_frame

	assert_gt(bar.value, 0.0, "the wheel is absorbed BY scrolling, not instead of it")


## Supervisor, post-tb41: "~2x as wide as it is currently."
func test_the_panel_asks_for_its_own_width_rather_than_inheriting_the_columns() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	assert_eq(panel.custom_minimum_size.x, CombatLogPanel.DEFAULT_WIDTH)
	assert_true(CombatLogPanel.DEFAULT_WIDTH >= 500.0, "roughly double the old ~260px column")


# --- title bar: drag to resize, minimize is its own button ------------------
#
# Supervisor: the first version wired BOTH to one `Button`, and `Button` emits
# `pressed` on release — so every drag-to-resize also toggled minimize the
# instant you let go ("behaving erratically"). These pin the split: a drag on
# the bar must never minimize, and a click on the button must never resize.


func _press(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	get_viewport().push_input(event)


func _release(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	get_viewport().push_input(event)


func _move_to(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	get_viewport().push_input(event)


## Dragging the bar upward makes the panel taller (it is anchored at the bottom
## of its column), and must leave it expanded.
func test_dragging_the_title_bar_resizes_and_never_minimizes() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	await get_tree().process_frame
	await get_tree().process_frame
	var before: float = panel.custom_minimum_size.y

	var grip: Vector2 = panel.title_bar.get_global_rect().get_center()
	_press(grip)
	_move_to(grip - Vector2(0.0, 60.0))
	_release(grip - Vector2(0.0, 60.0))
	await get_tree().process_frame

	assert_almost_eq(
		panel.custom_minimum_size.y, before + 60.0, 1.0, "dragged up 60px, 60px taller"
	)
	assert_false(panel.is_minimized(), "a drag must not toggle minimize on release")
	assert_eq(panel.minimize_button.text, CombatLogPanel.MINIMIZE_LABEL)


func test_the_minimize_button_collapses_to_the_bar_and_flips_to_plus() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	await get_tree().process_frame
	await get_tree().process_frame

	panel.minimize_button.pressed.emit()

	assert_true(panel.is_minimized())
	assert_eq(panel.custom_minimum_size.y, CombatLogPanel.TITLE_BAR_HEIGHT)
	assert_eq(panel.minimize_button.text, CombatLogPanel.RESTORE_LABEL)
	assert_false(panel._body.visible, "the log itself is hidden, not merely squashed")


## The bug the first version could not have got right: restore went back to the
## height captured when some earlier DRAG began, not to the height the panel was
## actually at when it was minimized.
func test_restoring_returns_to_the_height_it_was_dragged_to() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	await get_tree().process_frame
	await get_tree().process_frame

	var grip: Vector2 = panel.title_bar.get_global_rect().get_center()
	_press(grip)
	_move_to(grip - Vector2(0.0, 80.0))
	_release(grip - Vector2(0.0, 80.0))
	await get_tree().process_frame
	var dragged_to: float = panel.custom_minimum_size.y

	panel.minimize_button.pressed.emit()
	panel.minimize_button.pressed.emit()

	assert_almost_eq(panel.custom_minimum_size.y, dragged_to, 0.5)
	assert_false(panel.is_minimized())
	assert_true(panel._body.visible)


## The button sits inside the bar, so pressing it must be consumed there rather
## than starting a drag on the bar underneath.
func test_pressing_the_minimize_button_does_not_start_a_drag() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	await get_tree().process_frame
	await get_tree().process_frame

	var on_button: Vector2 = panel.minimize_button.get_global_rect().get_center()
	_press(on_button)
	_move_to(on_button - Vector2(0.0, 50.0))

	assert_false(panel._dragging, "the button consumed the press; the bar never saw it")
	_release(on_button - Vector2(0.0, 50.0))


## Resizing is clamped, so a wild drag cannot collapse the panel to nothing or
## grow it past the screen.
func test_a_drag_is_clamped_at_both_ends() -> void:
	var built: Array = _panel_and_spy()
	var panel: CombatLogPanel = built[0]
	await get_tree().process_frame
	await get_tree().process_frame

	var grip: Vector2 = panel.title_bar.get_global_rect().get_center()
	_press(grip)
	_move_to(grip + Vector2(0.0, 5000.0))
	assert_eq(panel.custom_minimum_size.y, CombatLogPanel.MIN_HEIGHT)
	_move_to(grip - Vector2(0.0, 5000.0))
	assert_eq(panel.custom_minimum_size.y, CombatLogPanel.MAX_HEIGHT)
	_release(grip)
