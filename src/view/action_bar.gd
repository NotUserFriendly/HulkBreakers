class_name ActionBar
extends Node

## taskblock-07 Pass E1: "a row of 10 boxes along the bottom, merged with
## the turn controls." Pure presentation, same split as WeaponPanel/
## InventoryPanel: every box's content already comes from
## ActionCatalog.actions_for(unit) — this only fills SLOT_COUNT fixed
## boxes with placeholder initials text. Details on hover are Pass F's.
##
## Click-to-queue is deliberately not built here: neither Pass E's own
## text nor its TESTS specify what a click does (they're scoped entirely
## to the catalog — availability, ordering, source-agnostic collection —
## plus this display), and there is no existing "pick a weapon, then act"
## UI convention in the codebase to extend (TacticsController has no
## select_weapon/select_action of any kind; confirm_shot() auto-picks a
## weapon via DeepStrike.find_operable_weapon, and OverwatchAction has no
## UI call site at all yet). A flagged hook, not a silent gap (CLAUDE.md
## "ask, don't invent" / "leave a flagged hook").

const SLOT_COUNT := 10
const BOX_SIZE := Vector2(36, 28)

var tactics: TacticsController
var _boxes: Array[Label] = []


func setup(p_tactics: TacticsController, container: HBoxContainer) -> void:
	tactics = p_tactics
	_boxes.clear()
	for child: Node in container.get_children():
		child.queue_free()
	for i in range(SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = BOX_SIZE
		# docs/09 taskblock07 Pass B4: every non-interactive Control in this
		# scene must default to IGNORE, never STOP — these boxes are pure
		# display (click-to-queue is out of scope, see the class doc above).
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		container.add_child(panel)
		_boxes.append(label)
	tactics.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	var actions: Array[ActionDef] = []
	if unit != null:
		actions = ActionCatalog.actions_for(unit)
	for i in range(SLOT_COUNT):
		if i < actions.size():
			_boxes[i].text = actions[i].initials
			_boxes[i].modulate = HulkTheme.FOREGROUND
		else:
			_boxes[i].text = ""
			_boxes[i].modulate = HulkTheme.DIM
