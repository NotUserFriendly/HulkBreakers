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
