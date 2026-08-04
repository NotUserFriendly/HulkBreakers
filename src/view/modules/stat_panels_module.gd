class_name StatPanelsModule
extends ViewModule

## taskblock-56 Pass C: the bottom-right combat readout cluster — header, resolution banner, aim
## READING/RESOLVES readout, stat block and its drill-down — plus the left column's weapons list.
##
## **Extracted verbatim from `SquadControlOverlay._build_ui`**, labels, minimum sizes, colour
## overrides and mouse filters included. Every one of those is load-bearing for a reason recorded
## where it was set: `RichTextLabel` defaults to `MOUSE_FILTER_STOP` (unlike plain `Label`), so a
## read-only readout swallows clicks over its own rect unless told not to — the exact class of bug
## taskblock-07 Pass B4 audited the whole surface for.
##
## **Display, not input.** Everything here reads `TacticsController` and draws; nothing queues. With
## no `tactics` in the context the panels are still built and simply have nothing to render, which
## is what makes this module legal in a spectator mode that wants a stat block without a selection
## path. It is not wired into one today — Pass C moves code and changes nothing — but the
## possibility is the point of the two axes.

## The header's two faces. Active exactly when there is a selected unit (the stat block has
## something to resolve) or a live aim (the readout has something to show) — the same two conditions
## that already drive whether `AimView`/`StatPanel` render anything at all, read rather than
## re-derived.
const HEADER_ACTIVE := "COMBAT READOUT — active"
const HEADER_IDLE := "COMBAT READOUT — idle"

var stat_panel: StatPanel = null
var weapon_panel: WeaponPanel = null
var banner: Label = null
var aim_readout: RichTextLabel = null
var stat_label: RichTextLabel = null
var stat_drill_down: RichTextLabel = null
var weapon_label: RichTextLabel = null
var header: Label = null


func module_id() -> StringName:
	return &"stat_panels"


func _mount() -> void:
	var readout: Control = context.slot(ModuleSlots.READOUT_COLUMN, null)
	var inventory: Control = context.slot(ModuleSlots.INVENTORY_ROW, readout)

	weapon_label = RichTextLabel.new()
	weapon_label.bbcode_enabled = true
	weapon_label.custom_minimum_size = Vector2(260, 0)
	weapon_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapon_label.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(inventory, weapon_label)

	# runNotes.md: "I'm not entirely sure what the info is. Highlight what it's doing, and IF it's
	# doing it." A plain, named header whose colour and text follow whether the cluster underneath
	# actually has anything live to show.
	header = Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(readout, header)

	banner = Label.new()
	banner.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(readout, banner)

	aim_readout = RichTextLabel.new()
	aim_readout.bbcode_enabled = false
	aim_readout.custom_minimum_size = Vector2(320, 60)
	aim_readout.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	aim_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(readout, aim_readout)

	stat_label = RichTextLabel.new()
	stat_label.custom_minimum_size = Vector2(320, 40)
	stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(readout, stat_label)

	stat_drill_down = RichTextLabel.new()
	stat_drill_down.custom_minimum_size = Vector2(320, 60)
	stat_drill_down.add_theme_color_override("default_color", HulkTheme.DIM)
	stat_drill_down.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parent_into(readout, stat_drill_down)

	# `DataLibrary.material_table()` directly, never `context.battle.combat_state`'s own: a module
	# must build before a battle is loaded, and the table's content is the same shared game data
	# whichever `CombatState` holds it.
	var material_table: MaterialTable = DataLibrary.material_table()
	var tactics: TacticsController = context.tactics

	stat_panel = StatPanel.new()
	add_child(stat_panel)
	weapon_panel = WeaponPanel.new()
	add_child(weapon_panel)
	if tactics != null:
		stat_panel.setup(tactics, stat_label, stat_drill_down)
		weapon_panel.setup(tactics, weapon_label)

	refresh_header()


## The header follows the selection and the aim, and a debug verb can kill a part the header needs
## to know about — the same three triggers the player overlay wired by hand.
##
## **taskblock-57 Pass F also hands the aim readout to whoever owns the dartboard.** `AimView` moved
## to `UnitInputModule` — it is world geometry driven by the controller that module owns, and it has
## to survive both this module's retirement in Pass D and the aim mode turning most surfaces off.
## The text readout beside it is a UI panel and stayed here, so the two are joined at `link()` time
## rather than by one owning the other. A mode missing either end simply skips it.
func link() -> void:
	var input: ViewModule = context.module(&"unit_input")
	if input != null:
		(input as UnitInputModule).selection_changed.connect(refresh_header)
		if (input as UnitInputModule).aim_view != null:
			(input as UnitInputModule).aim_view.set_readout(aim_readout)
	var debug: ViewModule = context.module(&"debug_panel")
	if debug != null:
		(debug as DebugPanelModule).verb_applied.connect(_on_verb_applied)


func _on_verb_applied(_verb_id: StringName) -> void:
	refresh_header()


## Flips the header between its two faces. Called by the mode on selection and aim changes, and
## after a debug verb applies — the same three triggers `SquadControlOverlay` used.
func refresh_header() -> void:
	if header == null:
		return
	var tactics: TacticsController = context.tactics if context != null else null
	if tactics == null or tactics.selection == null:
		return
	var active: bool = tactics.aiming_at != null or tactics.selection.selected_unit != null
	header.text = HEADER_ACTIVE if active else HEADER_IDLE
	header.add_theme_color_override("font_color", HulkTheme.HIGHLIGHT if active else HulkTheme.DIM)


func _parent_into(parent: Control, child: Control) -> void:
	if parent != null:
		parent.add_child(child)
	else:
		add_child(child)
