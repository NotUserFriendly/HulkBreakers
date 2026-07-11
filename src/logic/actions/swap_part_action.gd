class_name SwapPartAction
extends CombatAction

## Swaps the part installed in `slot_type` with `new_part`, drawn from
## `container` (a container Part the unit carries). Phase 9 replaces the raw
## contents erase/append below with volume/mass-checked attach()/detach().

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
	return new_part.slot_type == slot_type


func apply(state: CombatState) -> void:
	unit.ap -= AP_COST
	var old_part: Part = unit.chassis.remove(slot_type)
	container.contents.erase(new_part)
	unit.chassis.install(new_part)
	if old_part != null:
		container.contents.append(old_part)
	state.log_action("SwapPartAction: unit %d swapped slot %d" % [unit.id, slot_type])


func describe() -> String:
	return "SwapPartAction(unit=%d, slot=%d)" % [unit.id, slot_type]
