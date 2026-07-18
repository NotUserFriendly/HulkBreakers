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
## taskblock-08 A1: a click arms `TacticsController.arm_action()` — the ONE
## entry point regardless of which box, no per-action special-casing here
## either. The armed slot highlights so the player can see what a
## subsequent enemy click will do; `TacticsController.armed_action` stays
## the single source of truth, this just reads it back on every
## `aim_changed` (arm/disarm/enter-aim/cancel-aim all emit it).

const SLOT_COUNT := 10
## taskblock-08 E1: "3x its current size. Slots are square." The old box
## was 36x28 (non-square); 3x the larger dimension gives a clean square,
## not 3x each axis independently (which would have stayed non-square).
const BOX_SIZE := Vector2(108, 108)

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
		panel.gui_input.connect(_on_box_gui_input.bind(i))
	tactics.selection_changed.connect(refresh)
	tactics.aim_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var unit: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	_current_actions = []
	if unit != null:
		_current_actions = ActionCatalog.actions_for(unit)
	var armed_id: StringName = tactics.armed_action.id if tactics.armed_action != null else &""
	for i in range(SLOT_COUNT):
		if i < _current_actions.size():
			_boxes[i].text = _current_actions[i].initials
			if _current_actions[i].id == armed_id:
				_boxes[i].modulate = HulkTheme.HIGHLIGHT
			else:
				_boxes[i].modulate = HulkTheme.FOREGROUND
		else:
			_boxes[i].text = ""
			_boxes[i].modulate = HulkTheme.DIM


## taskblock-08 A1/D1: click arms (one path, every box, no per-action
## branching — `arm_action` itself is the only place an action id turns
## into behaviour); motion re-enters (`_on_box_entered`) so the tooltip
## keeps tracking the cursor while hovering the same box (D1), matching
## the inventory tooltip's own per-motion-event pattern — TooltipView's
## own show_data() just repositions on a repeat call, it never restarts
## the hover delay.
func _on_box_gui_input(event: InputEvent, index: int) -> void:
	if index >= _current_actions.size():
		return
	if event is InputEventMouseMotion:
		_on_box_entered(index)
		return
	var button_event := event as InputEventMouseButton
	if button_event == null or not button_event.pressed:
		return
	if button_event.button_index == MOUSE_BUTTON_LEFT:
		tactics.arm_action(_current_actions[index].id)


func _on_box_entered(index: int) -> void:
	if tooltip_view == null or index >= _current_actions.size():
		return
	var data: TooltipData = TooltipBuilder.for_action(_current_actions[index])
	tooltip_view.show_data(data, _panels[index].get_viewport().get_mouse_position())


func _on_box_exited() -> void:
	if tooltip_view != null:
		tooltip_view.hide_tooltip()
