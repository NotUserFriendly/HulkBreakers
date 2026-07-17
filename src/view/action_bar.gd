class_name ActionBar
extends Node

## taskblock-07 Pass E1: "a row of 10 boxes along the bottom, merged with
## the turn controls." Pure presentation, same split as WeaponPanel/
## InventoryPanel: every box's content already comes from
## ActionCatalog.actions_for(unit) — this only fills SLOT_COUNT fixed
## boxes with placeholder initials text. taskblock-07 Pass F1: each box is
## now also hoverable — TooltipBuilder.for_action() is this class's own
## `tooltip_content()`.
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
var tooltip_view: TooltipView
var _boxes: Array[Label] = []
var _panels: Array[PanelContainer] = []
var _current_actions: Array[ActionDef] = []


func setup(
	p_tactics: TacticsController, container: HBoxContainer, p_tooltip_view: TooltipView
) -> void:
	tactics = p_tactics
	tooltip_view = p_tooltip_view
	_boxes.clear()
	_panels.clear()
	for child: Node in container.get_children():
		child.queue_free()
	for i in range(SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = BOX_SIZE
		# docs/09 taskblock07 Pass B4's own rule ("non-interactive Controls
		# must not default to STOP") still holds — but these boxes ARE
		# interactive now (F1: hoverable, for a tooltip). PASS, not STOP:
		# it still fires mouse_entered/mouse_exited, but — unlike STOP —
		# never blocks a click from reaching whatever's behind it, so this
		# stays outside Pass B4's own "eaten clicks" class of bug.
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		container.add_child(panel)
		_boxes.append(label)
		_panels.append(panel)
		panel.mouse_entered.connect(_on_box_entered.bind(i))
		panel.mouse_exited.connect(_on_box_exited)
	tactics.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	_current_actions = []
	if unit != null:
		_current_actions = ActionCatalog.actions_for(unit)
	for i in range(SLOT_COUNT):
		if i < _current_actions.size():
			_boxes[i].text = _current_actions[i].initials
			_boxes[i].modulate = HulkTheme.FOREGROUND
		else:
			_boxes[i].text = ""
			_boxes[i].modulate = HulkTheme.DIM


func _on_box_entered(index: int) -> void:
	if tooltip_view == null or index >= _current_actions.size():
		return
	var data: TooltipData = TooltipBuilder.for_action(_current_actions[index])
	tooltip_view.show_data(data, _panels[index].get_viewport().get_mouse_position())


func _on_box_exited() -> void:
	if tooltip_view != null:
		tooltip_view.hide_tooltip()
