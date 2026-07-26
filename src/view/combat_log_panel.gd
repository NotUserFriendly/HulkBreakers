class_name CombatLogPanel
extends VBoxContainer

## taskblock-41 Pass F: the combat log becomes a real window — a title bar, a
## minimize toggle, drag-to-resize by the bar, a genuine background, scroll
## hand-off at the content's ends, and a live FPS readout drawn over it.
##
## **This is a session opener, not a definition of done.** Window chrome is
## normally settled by rapid back-and-forth with the supervisor rather than
## spec'd up front, so this is deliberately something concrete to react to. The
## numbers below are flagged starting positions, not decisions.
##
## The one real rule left outside this class is `FpsMeter`'s arithmetic, which
## is unit-tested headlessly. What remains here is plumbing, which is why there
## are no acceptance tests on the chrome itself — the exception being the
## wheel's behaviour, which has its own test because getting it wrong is
## invisible until someone tries to zoom.
##
## **BR34.02 is answered structurally, not closed.** That entry (SUPERVISOR-
## owned) says one of two things must change: the log gets a visible background,
## or its transparent region stops eating clicks. This gives it a real
## background, so the panel is now honest about the space it occupies — but the
## call is the supervisor's and CC does not close it.

## Emitted on every minimize/restore, so a future layout can react to the
## panel's own collapse without polling it.
signal minimized_changed(is_minimized: bool)

## Starting geometry. Flagged/tunable — resize is interactive anyway, so these
## only set where it opens.
## Supervisor, post-tb41: "the combat log should be ~2x as wide as it is
## currently." It previously took whatever width the surrounding column
## happened to give it (~260px), which cut most lines off — the panel asks for
## its own width now rather than inheriting one.
const DEFAULT_WIDTH := 520.0
const DEFAULT_HEIGHT := 220.0
const MIN_HEIGHT := 64.0
const MAX_HEIGHT := 640.0
const TITLE_BAR_HEIGHT := 22.0
const TITLE := "Combat Log"
## The bar is the resize grip as well as the title, so it wants a little more
## than a text row's worth of height to be an easy target.
const BACKGROUND_ALPHA := 0.82

## Drawn ON the panel rather than emitted INTO the stream: a per-frame FPS
## event would drown the log it sits on (tb35 A1 already established the log is
## for greppable dumps, not a continuous readout).
const FPS_MARGIN := Vector2(8.0, 4.0)

## How far one wheel notch scrolls, as a fraction of a visible page. Flagged and
## tunable (CLAUDE.md: never invent a final number); picked to feel close to the
## engine default rather than derived from anything.
const SCROLL_PAGE_FRACTION := 0.25

var log_label: RichTextLabel
var title_bar: Button
var fps_label: Label

var _meter := FpsMeter.new()
var _body: PanelContainer
var _minimized := false
var _dragging := false
var _drag_start_y := 0.0
var _drag_start_height := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	# The container itself draws NOTHING — the background lives on `_body` and
	# the bar is a real Button. A full-rect container at STOP that renders
	# nothing is exactly the BR31.01/BR34.02 failure, so it stays IGNORE and
	# lets its children take their own clicks. `_input` below still runs
	# regardless of this filter, so the scroll decision is unaffected.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	title_bar = Button.new()
	title_bar.text = TITLE
	title_bar.custom_minimum_size = Vector2(0, TITLE_BAR_HEIGHT)
	title_bar.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_bar.focus_mode = Control.FOCUS_NONE
	title_bar.tooltip_text = "Click to minimize/restore. Drag to resize."
	title_bar.pressed.connect(toggle_minimized)
	title_bar.gui_input.connect(_on_title_bar_input)
	add_child(title_bar)

	_body = PanelContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, BACKGROUND_ALPHA
	)
	_body.add_theme_stylebox_override("panel", style)
	add_child(_body)

	log_label = RichTextLabel.new()
	# Preserved verbatim from the overlay this replaced — RTL layout puts the
	# scrollbar on the left so it never overlaps the text, and autowrap stays
	# OFF ("scrollable and not word wrapping", runNotes.md).
	log_label.layout_direction = Control.LAYOUT_DIRECTION_RTL
	log_label.scroll_following = true
	log_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	log_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.add_child(log_label)

	# In the TITLE BAR, right-aligned — not over the log body. Rendering it
	# revealed the obvious-in-hindsight problem: at this panel's real width the
	# body's top-right corner is exactly where the first log line sits, so the
	# readout printed straight through the text. The bar is the one strip of
	# this panel with no content to collide with. `MOUSE_FILTER_IGNORE` keeps
	# the click-to-minimize and drag-to-resize on the bar underneath it.
	#
	# Anchored right and grown LEFTWARD rather than via `PRESET_TOP_RIGHT`:
	# that preset bakes offsets from the control's minimum size, zero for a
	# Label with no text yet, so the readout grew rightward off the panel and
	# over the board instead. Both of these were found by rendering; neither was
	# visible to any headless assertion.
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.anchor_top = 0.0
	fps_label.anchor_bottom = 1.0
	fps_label.offset_right = -FPS_MARGIN.x
	fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.add_theme_color_override("font_color", HulkTheme.DIM)
	title_bar.add_child(fps_label)


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.content_margin_left = log_label.get_v_scroll_bar().get_combined_minimum_size().x
	log_label.add_theme_stylebox_override("normal", style)


func _process(delta: float) -> void:
	_meter.sample(delta)
	fps_label.text = _meter.readout_text()


func is_minimized() -> bool:
	return _minimized


## Collapses to just the title bar, so the log can be got out of the way
## without losing where it is or what it says.
func toggle_minimized() -> void:
	_minimized = not _minimized
	_body.visible = not _minimized
	custom_minimum_size.y = TITLE_BAR_HEIGHT if _minimized else _drag_start_height_or_default()
	minimized_changed.emit(_minimized)


func _drag_start_height_or_default() -> float:
	return DEFAULT_HEIGHT if _drag_start_height <= 0.0 else _drag_start_height


## Drag the title bar to resize vertically. Deliberately drag-on-the-bar rather
## than a separate grip: the bar is already the one part of this panel with no
## content to occlude.
func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = button.pressed
		if _dragging:
			_drag_start_y = button.global_position.y
			_drag_start_height = custom_minimum_size.y
	elif event is InputEventMouseMotion and _dragging and not _minimized:
		var motion := event as InputEventMouseMotion
		# The panel is anchored at the BOTTOM of its column, so dragging the bar
		# UP (a decreasing y) must make it taller.
		var delta_y: float = _drag_start_y - motion.global_position.y
		custom_minimum_size.y = clampf(_drag_start_height + delta_y, MIN_HEIGHT, MAX_HEIGHT)


## **The log absorbs the wheel whenever the cursor is over it — at the ends of
## the content too.** Scrolling past the bottom must not start zooming the
## camera; the panel is a solid surface for the wheel exactly as it already is
## for left/middle/right clicks.
##
## This REVERSES taskblock-41 Pass F's own spec, which said the wheel should
## "fall through to the camera rather than dead-stopping" at the ends. The
## supervisor corrected it after using it, and the correction is consistent with
## `BR30.05`, which reports that same fall-through as a bug in the debug panel:
## "once the verb list's own `ItemList` is scrolled to the bottom, further
## scroll input bleeds through and zooms the world camera instead of stopping at
## the list's own end." Building the spec as written reproduced a known bug in a
## second place. See `docs/SUPERSEDED.md`.
##
## **`MOUSE_FILTER_STOP` is not enough, which is not obvious and was measured.**
## A STOP control consumes ordinary clicks — which is why left/middle/right
## already behaved — but a wheel event still reaches `_unhandled_input`, where
## `CameraRig` lives, unless something actively consumes it. Verified with a spy
## at that exact stage (`test_combat_log_panel.gd`), including a control case
## proving the spy sees wheels that miss the panel. So the scrolling is done
## here explicitly and the event is marked handled, rather than left to the
## `RichTextLabel`'s own handler, which scrolls without consuming.
##
## Handled in `_input` — before GUI routing — so marking it handled also stops
## the label's built-in handler, and the log scrolls once rather than twice.


func _input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	var direction := 0
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1
	else:
		return
	if not get_global_rect().has_point(button.position):
		return

	# Minimized: nothing to scroll, but the bar is still a solid surface — a
	# strip of the screen that zooms while the rest of the panel does not would
	# be worse than either behaviour on its own.
	if not _minimized:
		var bar: VScrollBar = log_label.get_v_scroll_bar()
		var step: float = maxf(bar.page * SCROLL_PAGE_FRACTION, 1.0)
		bar.value = clampf(bar.value + direction * step, bar.min_value, bar.max_value - bar.page)
	get_viewport().set_input_as_handled()
