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
## The minimize toggle's two faces. `[-]` collapses to the bar, `[+]` restores.
const MINIMIZE_LABEL := "[-]"
const RESTORE_LABEL := "[+]"
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
## The drag-to-resize strip. A `PanelContainer`, deliberately NOT a `Button`
## any more — see `_on_title_bar_input`.
var title_bar: PanelContainer
var minimize_button: Button
var fps_label: Label

var _meter := FpsMeter.new()
var _body: PanelContainer
var _minimized := false
var _dragging := false
var _drag_start_y := 0.0
var _drag_start_height := 0.0
## The height to come back to when restored. Captured at the moment of
## minimizing, so a panel that was dragged taller returns to the height it was
## dragged to — not to whatever it happened to be when some earlier drag began,
## which is what the first version restored to.
var _restore_height := DEFAULT_HEIGHT


func _init() -> void:
	custom_minimum_size = Vector2(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	# The container itself draws NOTHING — the background lives on `_body` and
	# the bar is a real Button. A full-rect container at STOP that renders
	# nothing is exactly the BR31.01/BR34.02 failure, so it stays IGNORE and
	# lets its children take their own clicks. `_input` below still runs
	# regardless of this filter, so the scroll decision is unaffected.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The bar does ONE thing: resize. Minimizing is its own button, below.
	# It used to be a single `Button` wired to both — and `Button` emits
	# `pressed` on RELEASE, so every drag-to-resize also toggled minimize the
	# instant you let go. Supervisor: "behaving erratically", which it was.
	# Splitting the two gestures onto two controls is the fix; nothing about
	# the resize maths needed changing.
	title_bar = PanelContainer.new()
	title_bar.custom_minimum_size = Vector2(0, TITLE_BAR_HEIGHT)
	title_bar.tooltip_text = "Drag to resize."
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, 1.0
	)
	title_bar.add_theme_stylebox_override("panel", bar_style)
	title_bar.gui_input.connect(_on_title_bar_input)
	add_child(title_bar)

	var bar_row := HBoxContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(bar_row)

	var title_label := Label.new()
	title_label.text = TITLE
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_row.add_child(title_label)

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

	# In the TITLE BAR, not over the log body: at this panel's real width the
	# body's top-right corner is exactly where the first log line sits, so a
	# readout there printed straight through the text. Found by rendering.
	# `MOUSE_FILTER_IGNORE` so it never interrupts a drag started on the bar.
	# It is a row child now rather than an anchored overlay — the HBox handles
	# the placement the old hand-rolled anchors were doing badly.
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.add_theme_color_override("font_color", HulkTheme.DIM)
	bar_row.add_child(fps_label)

	# The minimize toggle. A real child Button, so it takes its own click and a
	# press on it never starts a drag on the bar underneath — that separation is
	# structural, not a flag either handler has to remember to check.
	minimize_button = Button.new()
	minimize_button.text = MINIMIZE_LABEL
	minimize_button.focus_mode = Control.FOCUS_NONE
	minimize_button.tooltip_text = "Minimize"
	minimize_button.custom_minimum_size = Vector2(TITLE_BAR_HEIGHT, 0)
	minimize_button.pressed.connect(toggle_minimized)
	bar_row.add_child(minimize_button)


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
	if _minimized:
		# Captured HERE, at the moment of collapsing, so whatever the panel had
		# been dragged to is what comes back.
		_restore_height = custom_minimum_size.y
		custom_minimum_size.y = TITLE_BAR_HEIGHT
	else:
		custom_minimum_size.y = _restore_height
	_body.visible = not _minimized
	minimize_button.text = RESTORE_LABEL if _minimized else MINIMIZE_LABEL
	minimize_button.tooltip_text = "Restore" if _minimized else "Minimize"
	minimized_changed.emit(_minimized)


## Drag the title bar to resize vertically. Deliberately drag-on-the-bar rather
## than a separate grip: the bar is already the one part of this panel with no
## content to occlude.
## Drag the bar to resize vertically, and nothing else. The minimize button is
## a child of this bar, so a press on it is consumed there and never reaches
## here — the two gestures cannot collide the way they did when one `Button`
## owned both (`pressed` fires on release, so every drag ended in a toggle).
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
