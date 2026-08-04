class_name ActionBarModule
extends ViewModule

## taskblock-56 Pass C: the action bar and the AP/MP pip rows above it — the left half of the
## bottom-right `[actions][turn controls]` row.
##
## **An INPUT module.** `ActionBar` arms an action and `TacticsController` turns the next click into
## a queued `CombatAction`; the pips are display, but they belong to the same column and were built
## in the same block, and splitting a two-line label row into its own module would be structure for
## its own sake. The pair moves together, exactly as `SquadControlOverlay` had it.
##
## **A label prefix on each pip row is what keeps a 0-pip row legible** as "AP"/"MP" rather than as
## blank space — taskblock-07 Pass G's "a unit with 0 shows an empty row, not a missing one".
## Preserved with the widths and colour overrides that make it read.

const PIP_LABEL_WIDTH := 28.0

var action_bar: ActionBar = null
var ap_mp_pip_row: ApMpPipRow = null
## The column pairing the pip rows above the action bar. Exposed because a test confirms that
## ordering structurally rather than by eye.
var action_column: VBoxContainer = null

## taskblock-57 Pass B: the bar's own root, holding the four published slots and the bar itself.
## **Moving this moves every dependant surface**, because they are its children rather than
## separately anchored to a screen corner — which is the whole reason the bar publishes slots
## instead of four modules each anchoring themselves near where they expect it to be.
var bar_root: VBoxContainer = null
## The four published slot containers. Public so a test reads back what was published rather than
## re-deriving where the bar put them.
var left_slot: HBoxContainer = null
var right_slot: HBoxContainer = null
var top_left_slot: HBoxContainer = null
var top_right_slot: HBoxContainer = null


func module_id() -> StringName:
	return &"action_bar"


## Arming an action is the first half of queueing one.
func kind() -> Kind:
	return Kind.INPUT


## taskblock-57 Pass B: **the first module to publish slots.** Nothing here is special-cased in the
## host — `ControlOverlay` publishes whatever any module returns from this hook.
func published_slots() -> Dictionary:
	return {
		ModuleSlots.ACTION_BAR_LEFT: left_slot,
		ModuleSlots.ACTION_BAR_RIGHT: right_slot,
		ModuleSlots.ACTION_BAR_TOP_LEFT: top_left_slot,
		ModuleSlots.ACTION_BAR_TOP_RIGHT: top_right_slot,
	}


func _mount() -> void:
	var row: Control = context.slot(ModuleSlots.ACTION_ROW, null)

	# The bar and its four satellite slots, as one subtree. Two rows: the surfaces that sit *above*
	# the bar, then the bar flanked by the surfaces beside it.
	bar_root = VBoxContainer.new()
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if row != null:
		row.add_child(bar_root)
	else:
		add_child(bar_root)

	var above := HBoxContainer.new()
	above.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(above)
	top_left_slot = _slot_container(above, true)
	top_right_slot = _slot_container(above, false)

	var beside := HBoxContainer.new()
	beside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(beside)
	left_slot = _slot_container(beside, false)

	action_column = VBoxContainer.new()
	action_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beside.add_child(action_column)

	right_slot = _slot_container(beside, false)

	var pip_rows := VBoxContainer.new()
	pip_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(pip_rows)

	var ap_pips: HBoxContainer = _pip_row(pip_rows, "AP", HulkTheme.HIGHLIGHT)
	var mp_pips: HBoxContainer = _pip_row(pip_rows, "MP", HulkTheme.MP_PIP)

	# taskblock-08 E1: "action bar 3x its current size" — `ActionBar.BOX_SIZE` carries the actual
	# number; this row only has to sit directly under the pips, both inside `action_column`.
	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(action_row)

	var tooltip: TooltipView = _tooltip_view()
	action_bar = ActionBar.new()
	add_child(action_bar)
	ap_mp_pip_row = ApMpPipRow.new()
	add_child(ap_mp_pip_row)
	if context.tactics != null:
		action_bar.setup(context.tactics, action_row, tooltip)
		ap_mp_pip_row.setup(context.tactics, ap_pips, mp_pips, tooltip)


## One published slot container. `expanding` gives it the leftover width, which is what pushes the
## slot after it to the far edge — the "above the bar, right edge" placement in Pass C's table.
##
## `MOUSE_FILTER_IGNORE`, like every other wrapping container in the layout: these span real width
## and would otherwise swallow camera drags that started over them before `CameraRig` ever saw the
## event. **Whatever mounts INTO the slot sets its own filter**; an empty slot must never be a dead
## patch of screen.
func _slot_container(parent: HBoxContainer, expanding: bool) -> HBoxContainer:
	var slot := HBoxContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expanding:
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slot)
	return slot


func _pip_row(parent: VBoxContainer, text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(PIP_LABEL_WIDTH, 0)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var pips := HBoxContainer.new()
	row.add_child(pips)
	return pips


## The one shared tooltip renderer, if this mode declared it before this module. Null is a legal
## answer — `ActionBar`/`ApMpPipRow` both already accept it.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip")
	return (module as TooltipModule).view if module != null else null
