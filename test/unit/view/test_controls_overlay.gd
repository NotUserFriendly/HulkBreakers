extends GutTest

## docs/10 taskblock03 J: ControlsOverlay is a thin renderer over
## ControlBindings.all() — content is covered there; this only checks the
## Label actually gets built from it and H toggles visibility.


func _key_event(keycode: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event


func test_setup_fills_the_label_with_every_binding_row() -> void:
	var label := Label.new()
	var overlay := ControlsOverlay.new()
	add_child_autofree(label)
	add_child_autofree(overlay)

	overlay.setup(label, "res://out/combat.log")

	for row: Dictionary in ControlBindings.all("res://out/combat.log"):
		assert_true(label.text.contains(row["action"] as String))


func test_setup_dims_the_label() -> void:
	var label := Label.new()
	var overlay := ControlsOverlay.new()
	add_child_autofree(label)
	add_child_autofree(overlay)

	overlay.setup(label, "")

	assert_true(label.has_theme_color_override("font_color"))
	assert_eq(label.get_theme_color("font_color"), HulkTheme.DIM)


## tb31 Pass A: default OFF now — reference, not chrome.
func test_h_toggles_the_labels_visibility() -> void:
	var label := Label.new()
	var overlay := ControlsOverlay.new()
	add_child_autofree(label)
	add_child_autofree(overlay)
	overlay.setup(label, "")
	assert_false(label.visible, "reference, not chrome: hidden by default")

	overlay._unhandled_input(_key_event(KEY_H))
	assert_true(label.visible)

	overlay._unhandled_input(_key_event(KEY_H))
	assert_false(label.visible)


func test_other_keys_do_not_toggle_visibility() -> void:
	var label := Label.new()
	var overlay := ControlsOverlay.new()
	add_child_autofree(label)
	add_child_autofree(overlay)
	overlay.setup(label, "")

	overlay._unhandled_input(_key_event(KEY_R))

	assert_false(label.visible)


func test_set_log_path_rebuilds_the_text_with_the_new_path() -> void:
	var label := Label.new()
	var overlay := ControlsOverlay.new()
	add_child_autofree(label)
	add_child_autofree(overlay)
	overlay.setup(label, "res://out/old.log")
	assert_true(label.text.contains("res://out/old.log"))

	overlay.set_log_path("res://out/new.log")

	assert_true(label.text.contains("res://out/new.log"))
	assert_false(label.text.contains("res://out/old.log"))
