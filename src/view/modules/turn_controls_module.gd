class_name TurnControlsModule
extends ViewModule

## taskblock-56 Pass C: End Turn and Reset Turn, the column to the action bar's right.
##
## **An INPUT module, and the sharpest example of why the axis is drawn where it is.** End Turn
## leaves TACTICS and runs resolution against the authoritative `CombatState` — it is the single
## most state-mutating control on the surface. A mode that declares no input modules does not have
## this button, and that is precisely Spectator's contract: a spectator watches turns resolve and
## cannot end one.
##
## `BR27.08`: "Resolve to Here" is deliberately **not** here. It moved to a per-queue-row button in
## `QueuePanelModule`, which is why this column is two buttons rather than three and why a test
## reaches these by name instead of by a child index that shifted when the third left.

var column: VBoxContainer = null
var end_turn_button: Button = null
var reset_turn_button: Button = null


func module_id() -> StringName:
	return &"turn_controls"


func kind() -> Kind:
	return Kind.INPUT


## taskblock-57 Pass C: **right of the action bar, padded** — a slot the bar publishes, so this
## column travels with the bar. Falls back to the taskblock-56 `ACTION_ROW` for a mode whose chrome
## still builds one, and to the module itself for a mode with neither.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_RIGHT


func _mount() -> void:
	var fallback: Control = context.slots.get(ModuleSlots.ACTION_ROW)
	var row: Control = context.slot(preferred_slot(), fallback)
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if row != null:
		row.add_child(column)
	else:
		add_child(column)

	end_turn_button = _button("End Turn", _on_end_turn_pressed)
	# docs/10 taskblock03 D4: "a single Reset Turn control (button + R)."
	reset_turn_button = _button("Reset Turn", _on_reset_turn_pressed)


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(handler)
	# `BR31.01`: a stale tooltip from the board is dismissed when the cursor crosses onto a Button,
	# because `TacticsController`'s hover tracking cannot see over one.
	button.mouse_entered.connect(_hide_stale_tooltip)
	column.add_child(button)
	return button


func _hide_stale_tooltip() -> void:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	if module != null:
		(module as TooltipModule).hide_stale()


func _on_end_turn_pressed() -> void:
	if context != null and context.tactics != null:
		context.tactics.end_turn()


func _on_reset_turn_pressed() -> void:
	if context != null and context.tactics != null:
		context.tactics.reset_turn()
