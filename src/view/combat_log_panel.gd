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
## What remains here is plumbing, which is why there are no acceptance tests on
## the chrome itself — the exception being the wheel's behaviour, which has its
## own test because getting it wrong is invisible until someone tries to zoom.
##
## **taskblock-57 Pass C took the FPS readout off this panel.** taskblock-41 drew
## a live figure on the title bar because at the time there was nowhere else for
## it; the placement table now gives framerate its own surface in the corner and
## says to use *"the existing perf stats from the debug menu rather than the
## log's"*. So the meter is gone from here and `PerfMonitorModule` is the one
## framerate surface. Two readouts over two different meters, disagreeing by a
## frame, is the kind of thing that costs an afternoon. `FpsMeter` itself is
## untouched and still unit-tested; nothing in the view reads it any more.
##
## **BR34.02 is answered structurally, not closed.** That entry (SUPERVISOR-
## owned) says one of two things must change: the log gets a visible background,
## or its transparent region stops eating clicks. This gives it a real
## background, so the panel is now honest about the space it occupies — but the
## call is the supervisor's and CC does not close it.

## Emitted on every minimize/restore, so a future layout can react to the
## panel's own collapse without polling it.
signal minimized_changed(is_minimized: bool)

## taskblock-57 Pass C: the verbose checkbox changed. Emitted rather than
## acted on, because folding belongs to the sink (`HierarchicalUiSink`) and
## this panel deliberately knows nothing about a `LogFold` — tb22 F2's rule
## that folding is presentation over an untouched event stream.
signal verbose_changed(is_verbose: bool)

## How far the overflow preview's background extends past its own text, in pixels.
##
## **A background exactly the size of the glyphs is tangent to the lines above and below**, so the
## revealed line reads as part of the log rather than as something lifted out of it — the
## supervisor's review point. Vertical is the half that matters, since log lines stack with no gap.
## A starting position, not a decision.
const PREVIEW_MARGIN := Vector2(6.0, 3.0)

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

## How far one wheel notch scrolls, as a fraction of a visible page. Flagged and
## tunable (CLAUDE.md: never invent a final number); picked to feel close to the
## engine default rather than derived from anything.
const SCROLL_PAGE_FRACTION := 0.25

var log_label: RichTextLabel
## The drag-to-resize strip. A `PanelContainer`, deliberately NOT a `Button`
## any more — see `_on_title_bar_input`.
var title_bar: PanelContainer
var minimize_button: Button
## taskblock-57 Pass C: the table's two checkboxes. Public so a test drives
## the real controls rather than the fields behind them.
var wrap_checkbox: CheckBox
var verbose_checkbox: CheckBox

## taskblock-57 Pass C: the overflow preview — the *revealing* half of the
## table's two hover behaviours. Public so a test reads what it says.
var overflow_preview: Label

## The title label, hidden while minimized — taskblock-57 Pass C's "minimises
## to a BUTTON", not to a full-width strip with a title on it.
var _title_label: Label
var _controls_row: HBoxContainer
## **The same clock the tooltip uses**, which is the taskblock's own
## requirement: "two behaviours sharing one timer". The content models stay
## apart — a tooltip says what a control will DO, this says what a line
## already SAYS — and only the 1.5 s dwell is common.
var _dwell := HoverDwell.new()
## The line offsets `_line_offsets` last computed, and the line count they were computed at. See
## that function — this exists because it was being rebuilt on every mouse-motion event.
var _cached_offsets := PackedFloat32Array()
var _cached_line_count: int = -1
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
## The width to come back to, captured at the same moment and for the same
## reason as `_restore_height` — minimizing now narrows the panel to its
## button, so a restore has a width to undo as well as a height.
var _restore_width := DEFAULT_WIDTH


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

	_title_label = Label.new()
	_title_label.text = TITLE
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_row.add_child(_title_label)

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
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# taskblock-57 Pass C: **"Word wrap and verbose as checkboxes."** They live inside the body
	# rather than on the title bar, so minimizing takes them away with everything else and the
	# minimized panel really is just a button.
	var body_column := VBoxContainer.new()
	body_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(body_column)
	body_column.add_child(log_label)

	_controls_row = HBoxContainer.new()
	_controls_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_column.add_child(_controls_row)

	# **Off by default, and that is preserved rather than chosen.** `runNotes.md`, carried in this
	# file's own comment since taskblock-41: "scrollable and not word wrapping". The checkbox makes
	# it reachable; it does not change the default.
	wrap_checkbox = CheckBox.new()
	wrap_checkbox.text = "Wrap"
	wrap_checkbox.focus_mode = Control.FOCUS_NONE
	wrap_checkbox.toggled.connect(set_word_wrap)
	_controls_row.add_child(wrap_checkbox)

	verbose_checkbox = CheckBox.new()
	verbose_checkbox.text = "Verbose"
	verbose_checkbox.focus_mode = Control.FOCUS_NONE
	verbose_checkbox.toggled.connect(set_verbose)
	_controls_row.add_child(verbose_checkbox)

	# **Shown in place, over the text** — the table's own words, and the reason this is a child of
	# the body rather than a floating box near the cursor. A tooltip that appears beside the cursor
	# is answering "what will this do"; this is answering "what does that line say", so it belongs
	# on the line.
	overflow_preview = Label.new()
	overflow_preview.visible = false
	overflow_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overflow_preview.top_level = true
	overflow_preview.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, 1.0
	)
	# **The background is bigger than the text it backs**, which is the supervisor's review point:
	# *"the highlight needs to have a background slightly bigger than itself to make it not tangent
	# other text."* Filled exactly to the glyphs, the revealed line touched the lines above and
	# below and read as part of them rather than as something lifted off the log.
	#
	# The vertical margin is the one that matters — log lines are stacked with no gap — but the
	# horizontal one is here too, so the right-hand edge does not end flush against the character it
	# is revealing.
	preview_style.content_margin_left = PREVIEW_MARGIN.x
	preview_style.content_margin_right = PREVIEW_MARGIN.x
	preview_style.content_margin_top = PREVIEW_MARGIN.y
	preview_style.content_margin_bottom = PREVIEW_MARGIN.y
	overflow_preview.add_theme_stylebox_override("normal", preview_style)
	# Parented to this panel's own root, not to the body: `top_level` Controls are skipped by
	# `Container`'s own child sorting, so this never fights the layout it draws over.
	add_child(overflow_preview)

	log_label.gui_input.connect(_on_log_hovered)
	log_label.mouse_exited.connect(_on_log_exited)

	# The minimize toggle. A real child Button, so it takes its own click and a
	# press on it never starts a drag on the bar underneath — that separation is
	# structural, not a flag either handler has to remember to check.
	minimize_button = Button.new()
	minimize_button.text = MINIMIZE_LABEL
	minimize_button.focus_mode = Control.FOCUS_NONE
	minimize_button.tooltip_text = "Minimize %s" % TITLE
	minimize_button.custom_minimum_size = Vector2(TITLE_BAR_HEIGHT, 0)
	minimize_button.pressed.connect(toggle_minimized)
	bar_row.add_child(minimize_button)


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.content_margin_left = log_label.get_v_scroll_bar().get_combined_minimum_size().x
	log_label.add_theme_stylebox_override("normal", style)


## Drives the dwell clock. **The second of the table's two hover behaviours, on the same timer as
## the first** — `HoverDwell.DELAY_SEC` is the single 1.5 s, and neither this nor `TooltipView`
## keeps its own count.
func _process(delta: float) -> void:
	if _dwell.tick(delta):
		_reveal_hovered_line()


## Tracks which line the cursor is over. Aiming at the line *index* rather than at the position is
## what lets the cursor drift within one line without restarting the wait — the same rule
## `TooltipView` follows by aiming at its rendered text.
func _on_log_hovered(event: InputEvent) -> void:
	if event is not InputEventMouseMotion:
		return
	# **No preview while wrapping.** With `AUTOWRAP_WORD_SMART` nothing is cut off, so there is
	# nothing to reveal — and a wrapped line spans several visual rows, which would make the index
	# arithmetic below wrong as well as pointless.
	if is_word_wrapped():
		_hide_preview()
		return
	var local_y: float = (event as InputEventMouseMotion).position.y
	var line: int = LogLineProbe.line_at(_line_offsets(), local_y + _scroll_value())
	if line < 0:
		_hide_preview()
		return
	_dwell.aim_at(line)
	if not _dwell.fired:
		overflow_preview.visible = false


func _on_log_exited() -> void:
	_hide_preview()


func _hide_preview() -> void:
	_dwell.cancel()
	overflow_preview.visible = false


## Shows the hovered line's full text, in place over it, if it is actually cut off.
func _reveal_hovered_line() -> void:
	var aimed: Variant = _dwell.target()
	if aimed == null:
		overflow_preview.visible = false
		return
	var line: int = int(aimed)
	var offsets: PackedFloat32Array = _line_offsets()
	var text: String = LogLineProbe.text_of(log_label.get_parsed_text().split("\n"), line)
	if text == "" or line >= offsets.size():
		overflow_preview.visible = false
		return
	var font: Font = log_label.get_theme_font(&"normal_font")
	var font_size: int = log_label.get_theme_font_size(&"normal_font_size")
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if not LogLineProbe.overflows(width, log_label.size.x):
		overflow_preview.visible = false
		return
	overflow_preview.text = text
	# **On the line**, not beside the cursor. `top_level` means this is a global position, and the
	# line's own content offset minus the scroll is where that line currently sits on screen.
	# **Offset by the margin so the TEXT lands on the line, not the background's corner.** The style
	# box now extends past its own content, so positioning the Control at the line's origin would
	# push the glyphs down and right by exactly the margin and the reveal would not line up with
	# what it is revealing.
	overflow_preview.global_position = (
		log_label.global_position + Vector2(0.0, offsets[line] - _scroll_value()) - PREVIEW_MARGIN
	)
	overflow_preview.reset_size()
	overflow_preview.visible = true


## Every visible line's y offset, **cached between text changes**.
##
## **This ran on every mouse-motion event over the log**, walking the whole label and calling
## `get_line_offset(i)` once per line — on a long log that is hundreds of engine calls per motion,
## and a camera pan generates a motion event per frame. Reported as *"Player view is dropping FPS
## when panning. It might be in the current combat log."*
##
## The offsets only change when the text or the wrap does, so they are computed once and reused. The
## line count is the invalidation key: `UiLogSink` rewrites `log_label.text` wholesale on a dirty
## frame, and any rewrite that changes what is on screen changes how many lines are on screen.
##
## **Not a cache with a manual invalidate**, deliberately — a caller that forgot to invalidate would
## produce a preview pointing at the wrong line, which is far harder to notice than a slow pan.
func _line_offsets() -> PackedFloat32Array:
	var count: int = log_label.get_line_count()
	if count == _cached_line_count and _cached_offsets.size() == count:
		return _cached_offsets
	var offsets := PackedFloat32Array()
	for i in range(count):
		offsets.append(log_label.get_line_offset(i))
	_cached_offsets = offsets
	_cached_line_count = count
	return offsets


func _scroll_value() -> float:
	var bar: VScrollBar = log_label.get_v_scroll_bar()
	return bar.value if bar != null else 0.0


func is_minimized() -> bool:
	return _minimized


## **Collapses to a BUTTON**, not to a full-width title strip.
##
## taskblock-57 Pass C: *"Minimises to a button flush against the bar, no padding."* The title text
## goes with the body, so what is left is the toggle itself — which is the difference between "the
## log is out of the way" and "the log is a 520-pixel bar with nothing in it". `CombatLogModule`
## owns the *flush* half, because padding is a property of the slot, not of the panel.
##
## The restore width is captured at the moment of collapsing for the same reason the height already
## was: a panel that was resized comes back to the size it was resized to.
func toggle_minimized() -> void:
	_minimized = not _minimized
	if _minimized:
		# Captured HERE, at the moment of collapsing, so whatever the panel had
		# been dragged to is what comes back.
		_restore_height = custom_minimum_size.y
		_restore_width = custom_minimum_size.x
		_apply_height(TITLE_BAR_HEIGHT)
		custom_minimum_size.x = TITLE_BAR_HEIGHT
		size.x = TITLE_BAR_HEIGHT
	else:
		_apply_height(_restore_height)
		custom_minimum_size.x = _restore_width
		size.x = _restore_width
	_body.visible = not _minimized
	_title_label.visible = not _minimized
	minimize_button.text = RESTORE_LABEL if _minimized else MINIMIZE_LABEL
	# **Minimised, it says what it will restore.** The UI review: *"The [+] symbol you click to show
	# the combat log should say 'Combat Log' when hovered, not just 'Restore'."* Collapsed to a
	# button, `[+]` is the only thing on screen naming this panel — "Restore" answers "what does this
	# control do" when the question is "what IS this".
	minimize_button.tooltip_text = TITLE if _minimized else "Minimize %s" % TITLE
	minimized_changed.emit(_minimized)


## taskblock-57 Pass C: the word-wrap checkbox. Named rather than poked, so a test drives the real
## path. `AUTOWRAP_OFF` is the shipped default — see the checkbox's own comment.
func set_word_wrap(enabled: bool) -> void:
	log_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART if enabled else TextServer.AUTOWRAP_OFF
	)
	if wrap_checkbox != null:
		wrap_checkbox.set_pressed_no_signal(enabled)


func is_word_wrapped() -> bool:
	return log_label.autowrap_mode != TextServer.AUTOWRAP_OFF


## taskblock-57 Pass C: the verbose checkbox. **Emitted, not applied** — what "verbose" means is the
## sink's business (every fold group drawn open instead of summarised), and this panel deliberately
## knows nothing about folding.
func set_verbose(enabled: bool) -> void:
	if verbose_checkbox != null:
		verbose_checkbox.set_pressed_no_signal(enabled)
	verbose_changed.emit(enabled)


func is_verbose() -> bool:
	return verbose_checkbox != null and verbose_checkbox.button_pressed


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
		_apply_height(clampf(_drag_start_height + delta_y, MIN_HEIGHT, MAX_HEIGHT))


## Sets the panel's height through BOTH routes, because this panel is used in
## two different layout situations and only one of them respects each.
##
## Inside a container (the player mode's left column) the container sizes
## its children from `custom_minimum_size` and overwrites `size` every layout
## pass. Absolutely positioned (the spectator mode anchors it to the bottom-left
## corner) nothing reads `custom_minimum_size` at all and only `size` does
## anything. Writing one and not the other silently breaks resize in whichever
## situation the author wasn't looking at — so write both, and let each layout
## take the one it cares about.
func _apply_height(height: float) -> void:
	# The BOTTOM edge is what stays put. This panel lives at the bottom of the
	# screen in both views, so growing it has to extend the top upward — writing
	# `size.y` alone pins the top and pushes the bottom down off the corner
	# instead, which is what "the bottom of the panel changes shape" looked like.
	# `grow_vertical` does not cover this: it only applies when a control's
	# MINIMUM size forces a resize, not when `size` is written directly.
	var bottom_edge: float = position.y + size.y
	custom_minimum_size.y = height
	size.y = height
	position.y = bottom_edge - height


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
