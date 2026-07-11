class_name PickUpAction
extends CombatAction

## Collects a field item (dropped Part, salvage, or an ejected Matrix) from
## an adjacent (or the unit's own) cell. A picked-up Part goes into
## `container`, a container Part the unit is already carrying; a Matrix
## goes into unit.held_matrix instead (it isn't inventory — ImplantAction
## consumes it directly), so `container` is ignored for that case.

const AP_COST: int = 1

var unit: Unit
var item_cell: Vector2i
var item: Resource  # Part or Matrix
var container: Part


func _init(p_unit: Unit, p_item_cell: Vector2i, p_item: Resource, p_container: Part = null) -> void:
	unit = p_unit
	item_cell = p_item_cell
	item = p_item
	container = p_container


func is_legal(state: CombatState) -> bool:
	if not unit.alive:
		return false
	if state.current_unit() != unit:
		return false
	if unit.ap < AP_COST:
		return false
	if Grid.distance_chebyshev(unit.cell, item_cell) > 1:
		return false
	if not state.grid.field_items.has(item_cell):
		return false
	if not (state.grid.field_items[item_cell] as Array).has(item):
		return false

	if item is Matrix:
		return true

	if container == null or not container.is_container:
		return false
	return _unit_carries(container)


func apply(state: CombatState) -> void:
	unit.ap -= AP_COST
	var items: Array = state.grid.field_items[item_cell]
	items.erase(item)
	if items.is_empty():
		state.grid.field_items.erase(item_cell)

	if item is Matrix:
		unit.held_matrix = item
	else:
		container.contents.append(item)

	state.log_action("PickUpAction: unit %d picked up an item at %s" % [unit.id, item_cell])


func _unit_carries(target: Part) -> bool:
	for part: Part in unit.chassis.slots.values():
		if part == target or _search_contents(part, target):
			return true
	return false


func _search_contents(part: Part, target: Part) -> bool:
	if part == null:
		return false
	for child: Part in part.contents:
		if child == target or _search_contents(child, target):
			return true
	return false


func describe() -> String:
	return "PickUpAction(unit=%d, cell=%s)" % [unit.id, item_cell]
