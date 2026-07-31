class_name PerfPanel
extends Control

## taskblock-51: **the performance readout, as its own surface.**
##
## The supervisor asked for this rather than more combat-log lines, and the reason is in
## taskblock-51's own history: four framerate defects were hunted through log dumps that
## sampled once and reported a number nobody could act on. A live panel answers "is it bad
## *right now*" without a round trip through a file.
##
## ## What it shows, and why the fourth line exists
##
## Instant, rolling, 1% low, and the average with the fastest 1% of speeds removed — see
## `PerfStats` for exactly what each means. **The fourth line carries its own coverage**
## ("reporting 62% of 4 210 frames") because a figure computed after discarding data should
## say how much it discarded.
##
## ## Where it sits, and what closes it
##
## To the right of `DebugControlPanel`, toggled from inside it. **Closing the debug panel
## does not close this** — that is deliberate and was asked for: you open the debug panel to
## turn the readout on, then get it out of the way and keep watching the numbers while you
## play. The two are tied only at the point of *offering* the toggle, which is why this
## exists wherever the debug panel does rather than in one overlay.
##
## ## It must not cost what it measures
##
## The panel redraws on the rolling tick — once every `PerfStats.ROLLING_WINDOW_SECONDS` —
## not every frame. `sample()` runs per frame and is an append; the sorting behind the 1%
## figures happens on the tick. A profiler that shows 40 fps because it is a profiler is
## worse than no profiler.

## Emitted on each rolling tick while `log_dumps_enabled`, carrying `PerfStats.snapshot()`.
## The overlay owns the combat log, not this panel — a view that reached into a
## `CombatState` to write events would be the second logging path this project keeps
## deleting.
signal stats_ticked(snapshot: Dictionary)

## Enough for the longest line ("avg less top 1% 118.4 (reporting 62% of 12345 frames)")
## without the panel resizing as the numbers change width — a readout that jitters is one
## you stop being able to read at a glance.
const PANEL_WIDTH := 420.0
const BACKGROUND_ALPHA := 0.82
## Clear of `DebugControlPanel`'s own centred position at any viewport width.
const RIGHT_MARGIN := 16.0
const TOP_MARGIN := 8.0

var stats := PerfStats.new()
var log_dumps_enabled: bool = false

var _body: PanelContainer
var _lines: Label
var _dump_checkbox: CheckBox


func _ready() -> void:
	# **All four anchors and all four offsets, set explicitly.**
	#
	# Two attempts got this wrong and the second one *passed a test*. Setting `position`
	# with right-edge anchors placed it at x = -16 — the supervisor saw it hard against the
	# left edge with only its right sliver visible. Replacing that with a lone
	# `offset_right` left `offset_left` at the anchor, so the panel resolved to the full
	# 1904-pixel width starting at x = 0, and an assertion checking "left edge on screen,
	# right edge on screen" was satisfied by a panel covering the entire screen.
	#
	# Pinning both horizontal offsets against the right anchor makes the width arithmetic
	# rather than a negotiation, and `test_debug_panel_layout.gd` now asserts the width
	# itself — which is the property both broken versions actually violated.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -(PANEL_WIDTH + RIGHT_MARGIN)
	offset_right = -RIGHT_MARGIN
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_body = PanelContainer.new()
	_body.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, BACKGROUND_ALPHA
	)
	_body.add_theme_stylebox_override("panel", style)
	add_child(_body)

	var column := VBoxContainer.new()
	_body.add_child(column)

	var title := Label.new()
	title.text = "Performance"
	column.add_child(title)

	_lines = Label.new()
	_lines.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	column.add_child(_lines)

	var row := HBoxContainer.new()
	column.add_child(row)

	_dump_checkbox = CheckBox.new()
	_dump_checkbox.text = "Log every %ds" % int(PerfStats.ROLLING_WINDOW_SECONDS)
	_dump_checkbox.toggled.connect(_on_dump_toggled)
	row.add_child(_dump_checkbox)

	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(reset_stats)
	row.add_child(reset)

	_refresh()


## **Samples every frame; redraws only on the tick.** The split is the whole reason this is
## affordable to leave running.
func _process(delta: float) -> void:
	if not stats.sample(delta):
		return
	_refresh()
	if log_dumps_enabled:
		stats_ticked.emit(stats.snapshot())


func reset_stats() -> void:
	stats.reset()
	_refresh()


## Named rather than poked, so a test drives the real path instead of the flag behind it.
func set_log_dumps(enabled: bool) -> void:
	log_dumps_enabled = enabled
	if _dump_checkbox != null:
		_dump_checkbox.set_pressed_no_signal(enabled)


func readout_text() -> String:
	return _lines.text if _lines != null else ""


func _on_dump_toggled(pressed: bool) -> void:
	log_dumps_enabled = pressed


func _refresh() -> void:
	if _lines == null:
		return
	_lines.text = "\n".join(stats.describe())
