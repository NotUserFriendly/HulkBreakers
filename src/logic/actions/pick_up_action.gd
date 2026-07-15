class_name PickUpAction
extends CombatAction

## Picks a loose Part or Matrix off the unit's own cell (docs/01/05). A
## Matrix goes straight to `held_matrix`; a Part needs a `container` already
## worn on the frame with room for it. Resolved fresh from `state` every
## time (docs/09): a preview's grid/frame are independent clones.

const DEFAULT_AP_COST := 1

var unit: Unit
var item_cell: Vector2i
var item_id: StringName
var container_id: StringName
var ap_cost: int


func _init(
	p_unit: Unit,
	p_item_cell: Vector2i,
	p_item_id: StringName,
	p_container_id: StringName = &"",
	p_ap_cost: int = DEFAULT_AP_COST
) -> void:
	unit = p_unit
	item_cell = p_item_cell
	item_id = p_item_id
	container_id = p_container_id
	ap_cost = p_ap_cost


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.ap < ap_cost or actual.cell != item_cell:
		return false

	var item: Variant = state.grid.find_field_item(item_cell, item_id)
	if item == null:
		return false

	if item is Matrix:
		return actual.held_matrix == null

	var container: Part = actual.frame.find_part(container_id)
	if container == null:
		return false
	return Inventory.can_attach(item, container, actual.frame)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var item: Variant = state.grid.find_field_item(item_cell, item_id)

	var items: Array = state.grid.field_items[item_cell]
	items.erase(item)
	if items.is_empty():
		state.grid.field_items.erase(item_cell)

	if item is Matrix:
		actual.held_matrix = item
	else:
		var container: Part = actual.frame.find_part(container_id)
		Inventory.attach(item, container, actual.frame)

	actual.ap -= ap_cost
	var text: String = "PickUpAction: unit %d picked up %s" % [actual.id, item_id]
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"pick_up",
				{"item": item_id, "is_matrix": item is Matrix},
				text
			)
		)


func describe() -> String:
	return "PickUpAction(unit=%d, item=%s)" % [unit.id, item_id]
