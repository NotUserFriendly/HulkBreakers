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
##
## taskblock-08 D: "one controller, one delay, one follow behaviour" —
## every caller (InventoryPanel, ActionBar, TooltipController) already
## funnels through this one instance, so the delay+cursor-tracking lives
## here ONCE rather than being copied into each caller. `show_data()`
## calls repeated with the SAME content (the inventory tooltip's own
## per-motion-event pattern) just track the cursor (D1) — either updating
## the pending hover's own target position while its delay is still
## running, or repositioning the already-revealed tooltip directly; a
## GENUINELY new hover target resets the delay clock. `_process()` is the
## clock — driven by the real per-frame delta in the live game, and
## directly callable with an explicit delta in tests (same pattern
## CameraRig's tween tests use via `custom_step`), so the delay stays
## headless-testable with no real wall-clock wait.

const OFFSET := Vector2(16, 16)
const EDGE_MARGIN := 4.0
const MIN_WIDTH := 220.0
## taskblock-08 D2: "wait a beat before appearing" — the ONE hover-delay
## value, shared by every caller because there is only one tooltip
## mechanism now. A flagged tuning number, not a design decision.
const HOVER_DELAY_SEC := 0.4

var _label: RichTextLabel
var _has_pending: bool = false
var _pending_text: String = ""
var _pending_position: Vector2 = Vector2.ZERO
var _pending_elapsed: float = 0.0


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
## open space) rather than showing an empty box. Otherwise never shows
## instantly (D2): a genuinely new hover target starts the delay clock;
## a repeated call with the SAME content — the inventory tooltip's own
## per-motion-event pattern, and every other caller now matching it — just
## tracks the cursor (D1), never restarting the wait.
func show_data(data: TooltipData, at_position: Vector2) -> void:
	if data == null or (data.title == "" and data.rows.is_empty() and data.footer == ""):
		hide_tooltip()
		return
	var text: String = to_bbcode(data)
	if visible and text == _label.text:
		_reposition(at_position)
		return
	if _has_pending and text == _pending_text:
		_pending_position = at_position
		return
	visible = false
	_has_pending = true
	_pending_text = text
	_pending_position = at_position
	_pending_elapsed = 0.0


func hide_tooltip() -> void:
	visible = false
	_has_pending = false
	_pending_elapsed = 0.0


func _process(delta: float) -> void:
	if not _has_pending:
		return
	_pending_elapsed += delta
	if _pending_elapsed < HOVER_DELAY_SEC:
		return
	_label.text = _pending_text
	visible = true
	reset_size()
	_reposition(_pending_position)
	_has_pending = false


## taskblock-21 Pass A5: static (no instance state used) so the inspect
## panel's own fixed, always-docked info region can render the exact same
## TooltipData -> BBCode shape this floating tooltip uses, without needing
## a TooltipView instance of its own — one rendering rule, two hosts (a
## floating follow-cursor box here, a fixed dead-zone-holding panel there).
static func to_bbcode(data: TooltipData) -> String:
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
