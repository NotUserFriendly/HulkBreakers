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
## **taskblock-57 Pass C moved the placement out of this file.** It used to anchor itself
## into the top-right corner clear of `DebugControlPanel`; the layout now owns every
## position, so `PerfMonitorModule` puts it in the true bottom-right corner and this class
## only says how big it wants to be. What survives from the old block is the width being
## arithmetic rather than a negotiation — see `PANEL_WIDTH` — which is the property both
## broken versions of the old anchoring actually violated.
##
## **Closing the debug panel does not close this** — that is deliberate and was asked for:
## you open the debug panel to turn the readout on, then get it out of the way and keep
## watching the numbers while you play. The two are tied only at the point of *offering* the
## toggle, which is why the module that owns this is not the module that owns the panel.
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
## The default opacity, kept for a caller that builds this panel bare. **Set before `_ready`** to
## override it — `PerfMonitorModule` does, because a readout sitting over the board wants to be
## more transparent than one that had an empty corner to itself.
const BACKGROUND_ALPHA := 0.82

var stats := PerfStats.new()
var log_dumps_enabled: bool = false
## Assigned before the panel enters the tree; read once, in `_ready`.
var background_alpha: float = BACKGROUND_ALPHA

var _body: PanelContainer
var _lines: Label
var _dump_checkbox: CheckBox


func _ready() -> void:
	# **The width stays arithmetic; the position is the layout's business now.**
	#
	# Two attempts at self-anchoring got this wrong and the second one *passed a test*. Setting
	# `position` with right-edge anchors placed it at x = -16 — the supervisor saw it hard
	# against the left edge with only its right sliver visible. Replacing that with a lone
	# `offset_right` left `offset_left` at the anchor, so the panel resolved to the full
	# 1904-pixel width starting at x = 0, and an assertion checking "left edge on screen, right
	# edge on screen" was satisfied by a panel covering the entire screen.
	#
	# taskblock-57 Pass C deletes the anchoring rather than fixing it a third time: `BattleLayout`
	# owns where every surface sits, and `PerfMonitorModule` anchors this into the corner the
	# table names. **What is kept is the width being stated rather than negotiated**, which is
	# the property both broken versions actually violated and which
	# `test_debug_panel_layout.gd` still asserts.
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# Click-through: a readout over the board's corner must never eat a camera drag. The two
	# controls below take their own clicks; everything else here is text.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_body = PanelContainer.new()
	_body.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, background_alpha
	)
	_body.add_theme_stylebox_override("panel", style)
	add_child(_body)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(column)

	var title := Label.new()
	title.text = "Performance"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	_lines = Label.new()
	_lines.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_lines)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)

	_dump_checkbox = CheckBox.new()
	_dump_checkbox.text = "Log every %ds" % int(PerfStats.ROLLING_WINDOW_SECONDS)
	_dump_checkbox.toggled.connect(_on_dump_toggled)
	row.add_child(_dump_checkbox)

	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(reset_stats)
	row.add_child(reset)

	# **The outer node has to carry the body's height, and that is new in taskblock-57 Pass C.**
	#
	# `PerfPanel` is a plain `Control`, not a container, so it never sized itself to its child —
	# the outer rect stayed (420, 0) and the body simply drew downward from it. That was invisible
	# while the panel hung from the TOP of the screen. Pinned to the BOTTOM-right corner it is not:
	# a zero-height rect at y = 1080 draws its body from 1080 downward, entirely off screen. Found
	# by reading the real rect back, not by looking at it.
	#
	# Tracking the body rather than hard-coding a height keeps the readout's own "no jitter" rule —
	# `PANEL_WIDTH` exists so the numbers changing width cannot resize the panel, and a fixed height
	# would break the moment `PerfStats.describe()` grows a line.
	_body.resized.connect(_match_body_height)
	_match_body_height()
	_refresh()


## The outer rect grows to whatever the body needs. With `grow_vertical = GROW_DIRECTION_BEGIN` set
## by whoever placed this, that growth goes UP out of the corner rather than down off the screen.
func _match_body_height() -> void:
	custom_minimum_size.y = _body.size.y


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
