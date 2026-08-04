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
var keybindings_button: Button = null
var label: Label = null


func module_id() -> StringName:
	return &"controls_legend"


func _mount() -> void:
	var column: Control = context.slot(ModuleSlots.TOP_RIGHT, null)

	keybindings_button = Button.new()
	keybindings_button.text = "Keybindings"
	keybindings_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	keybindings_button.pressed.connect(toggle)
	_parent_into(column, keybindings_button)

	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(column, label)

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
