class_name InspectViewerModule
extends ViewModule

## taskblock-57 Pass C3: **the Inspect viewer, in its own slot.**
##
## Pass C's table: *"top-left, ~2/3 tall, half as wide — the 3D view, **split out so the centre
## stays clear**. Escapes the safe rect."* The whole point of the row is that the 3D subject and the
## inventory tree stop sharing one box in one corner, so the middle of the screen — the board — is
## not covered by the inspector.
##
## ## It owns the node; Inspect drives it
##
## This module builds the `BotViewer` and puts it in the slot. `InspectModule` hands it to
## `InspectPanel` before `setup()`, and the panel then drives it exactly as it drove the one it used
## to build itself: `begin`, `show_live`/`show_copy`, `clear_subject`, `refresh`.
##
## **Declaration order matters, and it is the rule the mode table already lives under**: this must
## come before `inspect`, because `InspectModule` looks this up at its own mount time. Declared
## after, Inspect builds its own viewer inside its own body — which is not broken, just the old
## layout, and is exactly what every mode without this module still gets.
##
## Display: it renders a subject. It queues nothing.

## How the viewer's frame is drawn. Starting positions, not decisions.
const FRAME_ALPHA := 0.82
const FRAME_BORDER := 1
const FRAME_PADDING := 8.0

var viewer: BotViewer = null
## The panel the viewer sits in, so it has an edge and can be padded off it. Its visibility follows
## the viewer's — `InspectPanel` drives the viewer, and the frame is what the player actually sees.
var frame: PanelContainer = null


func module_id() -> StringName:
	return &"inspect_viewer"


## Top-left, two thirds tall, half as wide. **Escapes the safe rect** (`ModuleSlots.ESCAPING_SLOTS`)
## and is left-edge-pinned, so this module is collapsible by the derivation in
## `ViewModule.is_collapsible` — which for the largest 3D surface on the screen is the one a cramped
## ratio most wants to be able to fold away.
func preferred_slot() -> StringName:
	return ModuleSlots.INSPECT_VIEWER


func _mount() -> void:
	viewer = BotViewer.new()
	# Hidden until Inspect opens something. `InspectPanel.open`/`close` own this flag, because the
	# viewer is no longer a child of the panel and hiding the panel no longer hides it.
	viewer.visible = false
	var slot: Control = context.slots.get(preferred_slot())
	if slot == null:
		# No such slot in this mode. The viewer is still real — `InspectModule` will still take it
		# and the panel will still drive it — it simply has nowhere of its own to be drawn, which is
		# the stand-alone case taskblock-56 Pass C's acceptance requires.
		add_child(viewer)
		return

	# **A frame around it, not a bare subview.** The UI review: *"INSPECT VIEWER in Player view —
	# Just a loose window, it needs a border of some sort, likely embedded in a panel so it can be
	# padded."* A `SubViewportContainer` over the board with nothing around it reads as a hole in
	# the screen rather than as a panel showing something.
	frame = PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, FRAME_ALPHA
	)
	style.border_color = HulkTheme.DIM
	var border: int = int(UiLayout.scaled(FRAME_BORDER))
	style.border_width_left = border
	style.border_width_right = border
	style.border_width_top = border
	style.border_width_bottom = border
	for side: String in [
		"content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"
	]:
		style.set(side, UiLayout.scaled(FRAME_PADDING))
	frame.add_theme_stylebox_override("panel", style)
	slot.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.visible = false

	frame.add_child(viewer)
	# The frame's rect is the placement; the viewer fills what the frame's padding leaves.
	viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _on_collapsed(value: bool) -> void:
	if value:
		if viewer != null:
			viewer.visible = false
		if frame != null:
			frame.visible = false


## The frame follows the viewer, which `InspectPanel` owns the flag for. Called on the host's frame
## tick because the panel sets `viewer.visible` directly and has no reason to learn about a frame.
func tick(_delta: float) -> void:
	if frame != null and viewer != null and frame.visible != viewer.visible:
		frame.visible = viewer.visible
