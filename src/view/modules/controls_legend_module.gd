class_name ControlsLegendModule
extends ViewModule

## taskblock-56 Pass C: the top-right keybindings legend and the button that shows it.
##
## tb31 Pass A made the display default OFF — it is reference, not chrome — and gave it two
## surfaces that flip **the same** `label.visible`: the H key inside `ControlsOverlay` itself, and
## this button. Two surfaces, one piece of state, never two mechanisms; that is the property worth
## preserving through the move.
##
## `set_log_path` is re-pointed on every battle load, because the legend shows where the current
## bout's log is being written and `file_sink` is rebuilt per bout.

## How solid the sheet is, and how far its text sits from its own edge. Starting positions.
const PANEL_ALPHA := 0.92
const PANEL_PADDING := 12.0

var controls_overlay: ControlsOverlay = null
var keybindings_button: UiButton = null
## The centred sheet itself. Public so a test reads back what is actually shown.
var panel: PanelContainer = null
var close_button: Button = null
var label: Label = null


func module_id() -> StringName:
	return &"controls_legend"


## taskblock-57 Pass C: the button belongs to the UI buttons cluster above the bar's right edge —
## the table's *"module toggles, Inspect, the debug menu"*, which is where every chrome control now
## lives. **The legend itself is not a button and stays where it was**: it is a wall of reference
## text, and the cluster is a row of controls.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_TOP_RIGHT


func _mount() -> void:
	var column: Control = context.slot(ModuleSlots.TOP_RIGHT, null)

	# A `UiButton`, so the cluster is one row of squares rather than three shapes — see `UiButton`.
	keybindings_button = UiButton.build(
		"KEY", "Keybindings", "Summons and dismisses the list of bound keys.", _tooltip_view()
	)
	keybindings_button.pressed.connect(toggle)
	_parent_into(context.slot(preferred_slot(), column), keybindings_button)

	# **A real panel, centred, with a way out.** The UI review: *"Keybindings pop up should have a
	# panel with a background that appears in the center of the screen, along with a [x] at the top
	# right to dismiss it."* It was a bare `Label` tinted `DIM` and anchored into whatever corner was
	# free, which reads as text that has escaped rather than as a thing you opened.
	panel = PanelContainer.new()
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, PANEL_ALPHA
	)
	for side: String in [
		"content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"
	]:
		style.set(side, UiLayout.scaled(PANEL_PADDING))
	panel.add_theme_stylebox_override("panel", style)
	# **It blocks scrolls as well as clicks.** The UI review: *"Keybindings pop-up currently blocks
	# clicks and should block clicks and scrolls."* A `PanelContainer` defaults to `STOP`, which
	# takes the click — but a wheel event it does not *accept* still reaches `_unhandled_input`, and
	# `CameraRig` zooms the board underneath a sheet that is covering it.
	panel.gui_input.connect(_on_sheet_input)

	var sheet := VBoxContainer.new()
	panel.add_child(sheet)

	var header := HBoxContainer.new()
	sheet.add_child(header)
	var title := Label.new()
	title.text = "Keybindings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	close_button = Button.new()
	close_button.text = "[x]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(toggle)
	header.add_child(close_button)

	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(label)

	# Centred on the surface rather than anchored to a corner — a modal reference sheet, which is
	# what the review asked for and what it always behaved like.
	if context != null and context.ui_root != null:
		context.ui_root.add_child(panel)
		# **Re-centred whenever it changes size, not once at build time.** `set_anchors_preset` works
		# off the rect the node has *now*, and a `PanelContainer` built this frame has no size yet —
		# so the sheet anchored itself around (0,0) and opened in the top-left corner. Measured: its
		# centre came out at (0,0) against a screen centre of (960,540).
		panel.anchor_left = 0.5
		panel.anchor_top = 0.5
		panel.anchor_right = 0.5
		panel.anchor_bottom = 0.5
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		panel.resized.connect(_recentre)
		_recentre()
	else:
		add_child(panel)

	controls_overlay = ControlsOverlay.new()
	add_child(controls_overlay)
	controls_overlay.setup(label, "", panel)


func rebind() -> void:
	if controls_overlay == null or context == null or context.battle == null:
		return
	controls_overlay.set_log_path(context.battle.file_sink.path)


## Pulls the sheet back onto the centre line. Its offsets are half its own size each way, which is
## a different number every time its content changes — the keybinding list grows a row whenever a
## binding is added.
func _recentre() -> void:
	if panel == null:
		return
	var half: Vector2 = panel.size * 0.5
	panel.offset_left = -half.x
	panel.offset_top = -half.y
	panel.offset_right = half.x
	panel.offset_bottom = half.y


## Summons or dismisses the sheet, and lights the button while it is up.
func toggle() -> void:
	if panel != null:
		panel.visible = not panel.visible
		_recentre()
	if keybindings_button != null:
		keybindings_button.active = panel != null and panel.visible


func _parent_into(parent: Control, child: Control) -> void:
	if parent != null:
		parent.add_child(child)
	else:
		add_child(child)


## The one shared tooltip renderer, if this mode declared it. Null is legal and means the button
## carries no hover description.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	return (module as TooltipModule).view if module != null else null


## Swallows the wheel over the sheet, so scrolling a reference panel does not zoom the board behind
## it. Only the wheel: everything else the panel is already `STOP` for.
func _on_sheet_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	var wheel: Array[int] = [
		MOUSE_BUTTON_WHEEL_UP,
		MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT,
		MOUSE_BUTTON_WHEEL_RIGHT,
	]
	if wheel.has(button.button_index):
		panel.accept_event()
