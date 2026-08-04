class_name InspectModule
extends ViewModule

## taskblock-56 Pass C: the inspect/status modal, and the button that opens it.
##
## **Both overlays built this and wired it differently, and both wirings survive here.**
## `SquadControlOverlay` gave it the live `SelectionController` and a `TacticsController` and opened
## it from a button; `SpectatorOverlay` gave it neither and opened it from a board click, pausing
## the bout. The panel itself was identical — same preferred size, same tree-before-`setup` order,
## same live-view lookup. What differed was who opens it, which is now the mode's business.
##
## **Added to the tree BEFORE `setup()`, and that order is load-bearing.** `setup()` builds a bot
## viewer whose `Camera3D.look_at()` needs a live tree to resolve a `Node3D`'s global transform
## against. Getting this backwards produces an error at construction, not at first open.
##
## **900x600 is the PREFERRED size, not an anchor.** `InspectPanel._clamp_to_viewport` shrinks and
## re-centres against the real viewport; a one-shot `PRESET_CENTER` never revisited was the "falls
## off the bottom" bug.
##
## Display: it describes what is already there and queues nothing.

## Emitted when the panel closes, so a mode that paused something to open it can resume.
signal closed

const PREFERRED_SIZE := Vector2(900, 600)

## Set before `mount`. `SquadControlOverlay` had an Inspect button in its left column;
## `SpectatorOverlay` opened the same panel from a board click and had none.
var with_button: bool = false

var panel: InspectPanel = null
var button: Button = null


func module_id() -> StringName:
	return &"inspect"


func _mount() -> void:
	var root: Control = context.ui_root
	panel = InspectPanel.new()
	panel.custom_minimum_size = PREFERRED_SIZE
	if root != null:
		root.add_child(panel)
	else:
		add_child(panel)
	panel.closed.connect(_on_panel_closed)

	var tactics: TacticsController = context.tactics
	var selection: SelectionController = tactics.selection if tactics != null else null
	var lookup: Callable = context.battle.find_unit_view if context.battle != null else Callable()
	panel.setup(DataLibrary.material_table(), selection, lookup, tactics)

	if with_button:
		button = Button.new()
		button.text = "Inspect"
		# `BR51.10`: starts disabled, because nothing is selected yet. An affordance that lies about
		# what it can do reads as a broken action when it correctly does nothing.
		button.disabled = true
		button.pressed.connect(open_selected)
		var column: Control = context.slot(ModuleSlots.LEFT_COLUMN, null)
		if column != null:
			column.add_child(button)
		else:
			add_child(button)


## The button's enabled state follows the selection.
func link() -> void:
	var input: ViewModule = context.module(&"unit_input")
	if input != null:
		(input as UnitInputModule).selection_changed.connect(refresh_button)


## Opens on whatever the selection currently holds. Since taskblock-51 Pass K that includes cover:
## `open_cell` could always describe a loose part, the selection simply could never hold one.
func open_selected() -> void:
	var tactics: TacticsController = context.tactics if context != null else null
	if tactics == null or tactics.selection == null:
		return
	open_target(tactics.selection.selected_target)


## **Only opens what the panel can describe.** `BR48.01`: opening the modal for a target it cannot
## render leaves the dim over the board with nothing on top of it, which reads as a stuck dim rather
## than a refused action. Returns whether it actually opened, so a caller that pauses a bout only
## pauses when something is on screen.
func open_target(target: SelectionTarget) -> bool:
	if panel == null or target == null or not target.can_inspect():
		return false
	if target.is_unit():
		panel.open(target.unit)
	else:
		panel.open_cell(target.cell, target.part)
	return true


## Opens a cell's own root part directly — the coarse pick a spectator's ground-plane click
## produces when the ray missed the blocker's body but hit the cell it stands on.
func open_cell(cell: Vector2i, part: Part) -> bool:
	if panel == null or part == null:
		return false
	panel.open_cell(cell, part)
	return true


## Drives the button's enabled state from whether the TARGET has something to describe, not from
## whether anything has been clicked — a bare cell is a real selection with nothing to inspect
## (`BR51.10`). Called by the mode on selection changes.
func refresh_button() -> void:
	if button == null:
		return
	var tactics: TacticsController = context.tactics if context != null else null
	button.disabled = (
		tactics == null or tactics.selection == null or not tactics.selection.can_inspect()
	)


func _on_panel_closed() -> void:
	closed.emit()
