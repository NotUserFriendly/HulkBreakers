class_name Chassis
extends Resource

@export var slots: Dictionary = {}  # Enums.SlotType (int) -> Part
@export var max_mass: float = 0.0


func install(part: Part) -> void:
	slots[part.slot_type] = part


func remove(slot_type: Enums.SlotType) -> Part:
	if not slots.has(slot_type):
		return null
	var part: Part = slots[slot_type]
	slots.erase(slot_type)
	return part


func aggregate_stats() -> Dictionary:
	var result: Dictionary = {}
	for part: Part in slots.values():
		if part == null:
			continue
		for key: Variant in part.stat_mods.keys():
			result[key] = result.get(key, 0) + part.stat_mods[key]
	return result


func living_parts() -> Array[Part]:
	var result: Array[Part] = []
	for part: Part in slots.values():
		if part != null and part.hp > 0:
			result.append(part)
	return result


func carried_mass() -> float:
	var total := 0.0
	for part: Part in slots.values():
		if part == null:
			continue
		total += part.mass
		if part.is_container:
			total += _flat_contents(part) * part.mass_multiplier
	return total


func _flat_contents(container: Part) -> float:
	var total := 0.0
	for child: Part in container.contents:
		total += child.mass
		if child.is_container:
			total += _flat_contents(child)
	return total
