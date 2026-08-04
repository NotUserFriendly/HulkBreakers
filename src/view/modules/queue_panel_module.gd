class_name QueuePanelModule
extends ViewModule

## taskblock-56 Pass C: the in-turn, ordered list of the selected unit's queued actions.
##
## **Display, despite each row carrying a "Resolve" button.** `BR27.08` moved Resolve to Here out of
## the turn-control column and onto the row it applies to; that button resolves an already-queued
## action rather than queueing one, so it is on the resolution path, not the input path. The
## distinction matters because a mode wanting to *watch* a queue — the obvious spectator want — must
## be able to take this without taking the ability to fill it.
##
## **The `ScrollContainer` is doing real work and its settings are not decoration.** Horizontal
## scroll is disabled because a row's "what" label uses `SIZE_EXPAND_FILL` to eat the row's slack
## width, and that is only well-defined once something bounds the width. Without it the row claimed
## an oversized natural size and landed hundreds of pixels past the right edge of a 1920-wide
## viewport, taking every button in it along — found live, not reasoned about.

const PANEL_SIZE := Vector2(320, 100)

var panel: QueuePanel = null
var rows: VBoxContainer = null


func module_id() -> StringName:
	return &"queue_panel"


func _mount() -> void:
	var column: Control = context.slot(ModuleSlots.READOUT_COLUMN, null)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = PANEL_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if column != null:
		column.add_child(scroll)
	else:
		add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	panel = QueuePanel.new()
	add_child(panel)
	if context.tactics != null:
		var tooltip_module: ViewModule = context.module(&"tooltip")
		var tooltip: TooltipView = (
			(tooltip_module as TooltipModule).view if tooltip_module != null else null
		)
		panel.setup(context.tactics, rows, tooltip)
