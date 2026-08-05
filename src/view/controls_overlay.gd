class_name ControlsOverlay
extends Node

## docs/10 taskblock03 J: a persistent overlay listing the bindings, dim,
## corner-anchored, toggleable with H — content generated from
## ControlBindings.all(), never a hand-typed block that could drift the
## first time a key changes. Pure presentation: this Node only formats
## ControlBindings' rows into text and flips the label's visibility.
##
## tb31 Pass A: default OFF now — reference, not chrome, so it shouldn't
## eat screen space by default. The H-key toggle above and the new
## `Keybindings` button (`SquadControlOverlay`) both just flip this SAME
## `label.visible` — one state, two surfaces to reach it, never two
## mechanisms.

var label: Label
## The `Control` whose visibility IS the on/off state. Defaults to `label`, and is the surrounding
## panel once there is one — **one state, whatever is wrapped around it**, which is the property
## this class has had since tb31 and the reason the H key and the `KEY` button cannot disagree.
var surface: Control = null
var log_path: String = ""


func setup(p_label: Label, p_log_path: String, p_surface: Control = null) -> void:
	label = p_label
	surface = p_surface if p_surface != null else p_label
	log_path = p_log_path
	label.add_theme_color_override("font_color", HulkTheme.DIM)
	surface.visible = false
	refresh()


## True while the legend is up. Read by whatever draws the button's own border.
func is_open() -> bool:
	return surface != null and surface.visible


## Called whenever the session's log path changes (a fresh FileSink per
## docs/09 taskblock03 B2's `new_battle()`) — rebuilds the text so the
## overlay never shows a stale path.
func set_log_path(p_log_path: String) -> void:
	log_path = p_log_path
	refresh()


func refresh() -> void:
	var lines: Array[String] = []
	for binding: Dictionary in ControlBindings.all(log_path):
		lines.append("%s: %s" % [binding["trigger"], binding["action"]])
	label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if surface == null or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and key_event.keycode == ControlBindings.TOGGLE_KEY:
		surface.visible = not surface.visible
