class_name ControlToggleModule
extends ViewModule

## **Watch / Assume Control — handing the squad to the AI and taking it back.**
##
## The UI review moved this out of the retired top-left cluster and into the turn-order column:
## *"'watch' can be moved in with 'end turn' and 'reset turn'"* for the player, and *"Assume Control
## should move to the TURN ORDER MANAGEMENT section"* for the spectator. Same button, same
## `battle.toggle_blue_control()`, one label per direction.
##
## ## Why it is its own module rather than a third button on `TurnControlsModule`
##
## It was one, briefly, and that broke the spectator's contract outright.
## **`TurnControlsModule` is an INPUT module** — End Turn leaves TACTICS and resolves against the
## authoritative `CombatState`, which is the most state-mutating control on the surface — and
## `ViewMode.has_unit_input()` answers by building each declared module *unmounted* and asking
## `kind()`. A module cannot make that answer depend on whether it found a `TacticsController`,
## because at that point it has no context to look in.
##
## So a spectator declaring `turn_controls` claimed unit input, and `_on_battle_loaded` therefore
## drove the AI batch itself: bouts advanced two turns per step, clicks landed on a board that had
## moved under them, and eight tests in `test_spectator_overlay.gd` went red at once. **The mode
## table's central claim is that a display-only mode cannot mutate through the view**, and it is
## checkable precisely because `kind()` is a static fact about a module.
##
## Handing over control is **not** unit input by that definition: it queues nothing against a unit,
## it changes who plays the squad. So it is a `DISPLAY` module, and both modes may have it.
##
## ## Placement
##
## The same slot the turn verbs use. It puts itself at the **top of their column** when they exist
## and builds its own otherwise — and it carries the gap under itself, because *"Watch should go
## above the other buttons, with an approximately button height gap between it and the actual turn
## related buttons"* is a fact about what is under this button, not about what is above those.

## The gap between this button and whatever is declared under it, before UI scale — about a button's
## height, so the two groups read as two groups. A starting position, not a decision.
const GAP_HEIGHT := 28.0

## "Watch" from the player view, "Assume Control" from the spectator — the same call either way,
## and only the label says which direction you are going. **Set before `mount`**, like every other
## mode option.
var watch_label: String = "Watch"

var button: Button = null
var column: VBoxContainer = null


func module_id() -> StringName:
	return &"control_toggle"


## Right of the action bar, above the turn verbs. Falls back the same way `TurnControlsModule` does,
## so a mode with neither slot still gets a working button on the module itself.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_RIGHT


func _mount() -> void:
	button = Button.new()
	button.text = watch_label
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(_on_pressed)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, UiLayout.scaled(GAP_HEIGHT))
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# **Into the turn-order column itself when a mode has one**, at the top, so this button and the
	# turn verbs are one stack rather than two columns side by side. `ACTION_BAR_RIGHT` is an
	# `HBoxContainer`, so two modules each adding their own column put Watch *beside* End Turn — read
	# off the real rects, Watch ended at y=1048 while End Turn started at 1026.
	#
	# Declared **after** `turn_controls` for that reason: a module that reads another at mount time
	# comes after it, which is the ordering rule the mode table already lives under.
	var turns: TurnControlsModule = (
		context.module(&"turn_controls") as TurnControlsModule if context != null else null
	)
	if turns != null and turns.column != null:
		column = turns.column
		column.add_child(button)
		column.add_child(gap)
		column.move_child(button, 0)
		column.move_child(gap, 1)
		return

	# No turn verbs in this mode — the spectator — so it builds its own column in the same slot.
	var fallback: Control = context.slots.get(ModuleSlots.ACTION_ROW)
	var row: Control = context.slot(preferred_slot(), fallback)
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	if row != null:
		# The same left margin the turn verbs pad themselves by — the bar's row carries no separation
		# of its own, so each satellite supplies its own or it touches the bar.
		var pad := MarginContainer.new()
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override("margin_left", int(UiLayout.scaled(BattleLayout.PADDING)))
		row.add_child(pad)
		pad.add_child(column)
	else:
		add_child(column)
	column.add_child(button)
	column.add_child(gap)


## `BattleScene`'s own toggle, unchanged. A mode with no battle has a button that does nothing,
## which is the stand-alone case every module owes.
func _on_pressed() -> void:
	if context != null and context.battle != null:
		context.battle.toggle_blue_control()
