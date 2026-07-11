class_name SwapPartAction
extends CombatAction

## Swaps the part installed in `slot_type` with `new_part`, drawn from
## `container` (a container Part the unit carries). The displaced old part
## goes back into `container`, checked against its volume/mass limits
## (Inventory.can_attach) — a swap is rejected if the old part wouldn't fit
## back in once the new one is removed.

const AP_COST: int = 1

var unit: Unit
var slot_type: Enums.SlotType
var container: Part
var new_part: Part


func _init(p_unit: Unit, p_slot_type: Enums.SlotType, p_container: Part, p_new_part: Part) -> void:
	unit = p_unit
	slot_type = p_slot_type
	container = p_container
	new_part = p_new_part


func is_legal(state: CombatState) -> bool:
	if not unit.alive:
		return false
	if state.current_unit() != unit:
		return false
	if unit.ap < AP_COST:
		return false
	if container == null or new_part == null:
		return false
	if not container.contents.has(new_part):
		return false
	if new_part.slot_type != slot_type:
		return false

	var old_part: Part = unit.chassis.slots.get(slot_type, null)
	if old_part == null:
		return true

	# Simulate freeing new_part's space before checking whether old_part fits;
	# reverted immediately, so no observable mutation from is_legal.
	container.contents.erase(new_part)
	var old_part_fits: bool = Inventory.can_attach(old_part, container, unit.chassis)
	container.contents.append(new_part)
	return old_part_fits


func apply(state: CombatState) -> void:
	unit.ap -= AP_COST
	var old_part: Part = unit.chassis.remove(slot_type)
	Inventory.detach(new_part, container)
	unit.chassis.install(new_part)
	if old_part != null:
		Inventory.attach(old_part, container, unit.chassis)
	state.log_action("SwapPartAction: unit %d swapped slot %d" % [unit.id, slot_type])


func describe() -> String:
	return "SwapPartAction(unit=%d, slot=%d)" % [unit.id, slot_type]
