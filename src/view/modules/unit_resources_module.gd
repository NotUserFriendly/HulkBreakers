class_name UnitResourcesModule
extends ViewModule

## taskblock-57 Pass C: **the selected unit's resources, above the action bar.**
##
## The pip rows used to be built inside `ActionBarModule`, whose own header argued that "splitting a
## two-line label row into its own module would be structure for its own sake". Pass C's placement
## table overrules that for a stated reason rather than a stylistic one: **G2 replaces this exact
## surface with a coordinate readout in editor mode — *"same slot, different module"*.** Two modules
## cannot share a slot if one of them is welded inside a third, so the split is what makes the
## editor's readout a table entry instead of a branch inside the action bar.
##
## What the bar keeps is the bar: arming an action. What moved out is the readout of what arming one
## would cost.
##
## ## Room for later resources is the point of the column
##
## The table reads *"AP/MP pips, RAM, room for later resources"*. The pips and the RAM line are what
## exist to show today; the container is a `VBoxContainer` so a later resource is a row rather
## than a re-layout.
##
## Display: it reads the selection and draws it, and queues nothing.

## The label prefix width that keeps a 0-pip row legible as "AP"/"MP" rather than as blank space —
## taskblock-07 Pass G's "a unit with 0 shows an empty row, not a missing one". Carried over with
## the widths and colour overrides that make it read.
const PIP_LABEL_WIDTH := 28.0

## Shown when nothing is selected, so the row is present and empty rather than absent. Same rule the
## pip rows follow, for the same reason: a surface that vanishes reads as broken.
const RAM_ABSENT := "RAM --"

var ap_mp_pip_row: ApMpPipRow = null
## The column the pips, the RAM line and whatever comes next share. Exposed because a test asserts
## the ordering structurally rather than by eye.
var column: VBoxContainer = null
var ram_label: Label = null


func module_id() -> StringName:
	return &"unit_resources"


## Above the bar, from its left edge — published by `ActionBarModule`, so this moves when the bar
## moves rather than being separately anchored near where it expects the bar to be.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_TOP_LEFT


func _mount() -> void:
	var slot: Control = context.slot(preferred_slot(), null)
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if slot != null:
		slot.add_child(column)
	else:
		add_child(column)

	var ap_pips: HBoxContainer = _pip_row("AP", HulkTheme.HIGHLIGHT)
	var mp_pips: HBoxContainer = _pip_row("MP", HulkTheme.MP_PIP)

	ram_label = Label.new()
	ram_label.text = RAM_ABSENT
	ram_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ram_label.add_theme_color_override("font_color", HulkTheme.DIM)
	column.add_child(ram_label)

	ap_mp_pip_row = ApMpPipRow.new()
	add_child(ap_mp_pip_row)
	if context.tactics != null:
		ap_mp_pip_row.setup(context.tactics, ap_pips, mp_pips, _tooltip_view())


## The RAM line follows the selection, exactly as the pips do.
func link() -> void:
	var input: ViewModule = context.module(&"unit_input")
	if input != null:
		(input as UnitInputModule).selection_changed.connect(refresh_ram)
	refresh_ram()


## **Read off the shell, not recomputed.** `total_ram`/`max_ram` are the same pair
## `DeepStrike.validate` fails an assembly on, so the number shown is the number the assembler
## enforced.
func refresh_ram() -> void:
	if ram_label == null:
		return
	var unit: Unit = _selected_unit()
	if unit == null or unit.shell == null:
		ram_label.text = RAM_ABSENT
		return
	ram_label.text = "RAM %.1f / %.1f" % [unit.shell.total_ram(), unit.shell.max_ram]


## Hidden as a whole, so the collapse toggle takes the column and not one row of it. Meaningless
## today — this slot floats with the bar rather than pinning to an edge — but a mode that re-slots
## it somewhere pinned gets working behaviour rather than a flag that does nothing.
func _on_collapsed(value: bool) -> void:
	if column != null:
		column.visible = not value


func _selected_unit() -> Unit:
	var tactics: TacticsController = context.tactics if context != null else null
	if tactics == null or tactics.selection == null:
		return null
	return tactics.selection.selected_unit


func _pip_row(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
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
## answer — `ApMpPipRow` already accepts it.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip")
	return (module as TooltipModule).view if module != null else null
