class_name TooltipView
extends PanelContainer

## taskblock-07 Pass F1/F2: THE one tooltip renderer — every hoverable
## surface (inventory rows, action bar boxes, tiles, units, field objects,
## queue entries) shows through this single instance, replacing both
## InventoryPanel's old plain-text `set_tooltip_text` mechanism and the
## whole combat_readout_panel.gd (deleted, F2). Manually shown/positioned
## rather than Godot's native per-Control tooltip system: the 3D board
## (tiles/units) has no Control to hang a native tooltip off at all, and a
## shared instance is simpler than overriding `_make_custom_tooltip` on
## every single hoverable Control separately — that's what "one renderer"
## means here. Parent this as the LAST child under `theme_root` so it
## draws above every other panel and inherits HulkTheme automatically.
##
## docs/08: RichTextLabel + BBCode does the highlighting natively — a
## `changed` row's own value gets HIGHLIGHT color, nothing else does.
## `TooltipPanel`/`TooltipLabel` (hulk_theme.gd) are the exact stylebox/
## color keys Godot's OWN stock tooltip already used; reusing them here
## keeps one visual language rather than inventing a second.

const OFFSET := Vector2(16, 16)
const EDGE_MARGIN := 4.0
const MIN_WIDTH := 220.0

var _label: RichTextLabel


func _init() -> void:
	visible = false
	theme_type_variation = &"TooltipPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	_label = RichTextLabel.new()
	_label.theme_type_variation = &"TooltipLabel"
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.custom_minimum_size = Vector2(MIN_WIDTH, 0)
	add_child(_label)


## Hides itself for an empty TooltipData (nothing to say — e.g. hovering
## open space) rather than showing an empty box.
func show_data(data: TooltipData, at_position: Vector2) -> void:
	if data == null or (data.title == "" and data.rows.is_empty() and data.footer == ""):
		hide_tooltip()
		return
	_label.text = _to_bbcode(data)
	visible = true
	reset_size()
	_reposition(at_position)


func hide_tooltip() -> void:
	visible = false


func _to_bbcode(data: TooltipData) -> String:
	var lines: Array[String] = []
	if data.title != "":
		lines.append("[b]%s[/b]" % data.title)
	for row: Dictionary in data.rows:
		var value: String = str(row.get("value", ""))
		if row.get("changed", false):
			value = "[color=#%s]%s[/color]" % [HulkTheme.HIGHLIGHT.to_html(false), value]
		lines.append("%s: %s" % [row.get("label", ""), value])
	if data.footer != "":
		lines.append("[color=#%s]%s[/color]" % [HulkTheme.DIM.to_html(false), data.footer])
	return "\n".join(lines)


## Cursor-anchored, clamped inside the viewport — never lets the box hang
## off the right/bottom edge the way an unclamped tooltip would at the
## board's own far corners.
func _reposition(at_position: Vector2) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var target: Vector2 = at_position + OFFSET
	target.x = clampf(target.x, EDGE_MARGIN, viewport_size.x - size.x - EDGE_MARGIN)
	target.y = clampf(target.y, EDGE_MARGIN, viewport_size.y - size.y - EDGE_MARGIN)
	global_position = target
