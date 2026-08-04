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


func module_id() -> StringName:
	return &"action_bar"


## Arming an action is the first half of queueing one.
func kind() -> Kind:
	return Kind.INPUT


func _mount() -> void:
	var row: Control = context.slot(ModuleSlots.ACTION_ROW, null)

	action_column = VBoxContainer.new()
	action_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if row != null:
		row.add_child(action_column)
	else:
		add_child(action_column)

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
