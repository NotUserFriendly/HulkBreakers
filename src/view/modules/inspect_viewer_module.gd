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

var viewer: BotViewer = null


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
	slot.add_child(viewer)
	# The slot's rect is the placement. The viewer's own `custom_minimum_size` is what it wants when
	# nobody places it; filling the slot is what the table asks for when somebody does.
	viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_collapsed(value: bool) -> void:
	if viewer != null and value:
		viewer.visible = false
