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

var controls_overlay: ControlsOverlay = null
var keybindings_button: UiButton = null
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

	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# taskblock-57 Pass D: **the legend anchors itself when no column publishes one.** The battle
	# layout has no `TOP_RIGHT` slot — that column existed for the readout cluster Pass D retires —
	# and the placement table has no row for a wall of reference text. It is off by default (tb31
	# Pass A: "reference, not chrome"), so a corner it shares with a closed Inspect costs nothing.
	if column != null:
		column.add_child(label)
	elif context.ui_root != null:
		context.ui_root.add_child(label)
		label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		add_child(label)

	controls_overlay = ControlsOverlay.new()
	add_child(controls_overlay)
	# "" placeholder: a module must build before a battle exists. `rebind()` corrects it the instant
	# a real battle (and its `file_sink`) does.
	controls_overlay.setup(label, "")


func rebind() -> void:
	if controls_overlay == null or context == null or context.battle == null:
		return
	controls_overlay.set_log_path(context.battle.file_sink.path)


func toggle() -> void:
	if controls_overlay != null and controls_overlay.label != null:
		controls_overlay.label.visible = not controls_overlay.label.visible


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
