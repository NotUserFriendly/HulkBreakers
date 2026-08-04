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

## taskblock-57 Pass C: raised when End Turn is pressed with AP or MP unspent, so a test can assert
## the prompt appeared without driving a real modal.
signal end_turn_confirmation_raised(message: String)

var column: VBoxContainer = null
var end_turn_button: Button = null
var reset_turn_button: Button = null
## The confirmation the table asks for. Built lazily on the first press that needs it — a mode that
## never ends a turn with anything left never constructs one.
var confirm_dialog: ConfirmationDialog = null


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
		# taskblock-57 Pass C: **"right of the action bar, PADDED."** The bar's own row carries no
		# separation — padding is a property of each surface, so the combat log can be flush when
		# minimised — which means this column supplies its own gap or it touches the bar.
		var pad := MarginContainer.new()
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override("margin_left", int(UiLayout.scaled(BattleLayout.PADDING)))
		row.add_child(pad)
		pad.add_child(column)
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


## taskblock-57 Pass C: **ending a turn with AP or MP left asks first, and cancelling changes
## nothing.**
##
## "Cancelling leaves the turn intact" is a property of *not acting*, and that is how it is built:
## the cancel path has no code at all. `TacticsController.end_turn()` is the single thing that ends
## a turn, and it is reached from exactly one place below — so there is no partial end-turn to undo,
## and no second path that could end a turn without asking.
func _on_end_turn_pressed() -> void:
	if context == null or context.tactics == null:
		return
	var unit: Unit = _previewed_unit()
	if not TurnEndPrompt.should_confirm(unit):
		_end_turn_now()
		return
	var message: String = TurnEndPrompt.message(unit)
	_dialog().dialog_text = message
	_dialog().popup_centered()
	end_turn_confirmation_raised.emit(message)


## The unit **as the queue will leave it**, not as it stands now — see `TurnEndPrompt`. Falls back
## to the raw selection when there is no preview to take, which is the same degrade `ApMpPipRow`
## already makes.
func _previewed_unit() -> Unit:
	var selection: SelectionController = context.tactics.selection
	if selection == null or selection.selected_unit == null:
		return null
	var previewed: Unit = selection.previewed_unit()
	return previewed if previewed != null else selection.selected_unit


## Named, so a test drives the real confirmed path rather than reaching past the dialog.
func confirm_end_turn() -> void:
	_end_turn_now()


func _end_turn_now() -> void:
	if context != null and context.tactics != null:
		context.tactics.end_turn()


func _dialog() -> ConfirmationDialog:
	if confirm_dialog != null:
		return confirm_dialog
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "End Turn"
	confirm_dialog.confirmed.connect(confirm_end_turn)
	# Parented to the module rather than to `ui_root`: a `Window` is its own surface, so it does not
	# need to be in the layout, and this keeps the stand-alone acceptance intact for a mode with no
	# `ui_root` at all.
	add_child(confirm_dialog)
	return confirm_dialog


func _on_reset_turn_pressed() -> void:
	if context != null and context.tactics != null:
		context.tactics.reset_turn()
