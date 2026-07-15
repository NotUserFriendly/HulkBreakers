class_name ModifyAssemblyAction
extends CombatAction

## Strips one sub-part off a dropped assembly lying on the ground (docs/01:
## destroying a part drops its whole subtree intact; stripping it apart
## afterward is a separate, paid action, not free at pickup). The stripped
## part becomes its own loose field item at the same cell.

var unit: Unit
var assembly_cell: Vector2i
var assembly_id: StringName
var target_id: StringName
var ap_cost: int


func _init(
	p_unit: Unit,
	p_assembly_cell: Vector2i,
	p_assembly_id: StringName,
	p_target_id: StringName,
	p_ap_cost: int
) -> void:
	unit = p_unit
	assembly_cell = p_assembly_cell
	assembly_id = p_assembly_id
	target_id = p_target_id
	ap_cost = p_ap_cost


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.ap < ap_cost or actual.cell != assembly_cell:
		return false

	var assembly: Variant = state.grid.find_field_item(assembly_cell, assembly_id)
	if assembly == null or not (assembly is Part):
		return false
	return _find_target(assembly) != null


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var assembly: Part = state.grid.find_field_item(assembly_cell, assembly_id)
	var target: Part = _find_target(assembly)

	PartGraph.drop(assembly, target)
	state.grid.field_items[assembly_cell].append(target)

	actual.ap -= ap_cost
	state.log_action(
		"ModifyAssemblyAction: unit %d stripped %s from %s" % [actual.id, target_id, assembly_id]
	)


## `target_id` anywhere in the assembly's subtree, the assembly's own root
## excluded — you can strip a part off an assembly, not strip the whole
## assembly off itself.
func _find_target(assembly: Part) -> Part:
	for part: Part in PartGraph.walk(assembly):
		if part == assembly:
			continue
		if part.id == target_id:
			return part
	return null


func describe() -> String:
	return (
		"ModifyAssemblyAction(unit=%d, assembly=%s, target=%s)" % [unit.id, assembly_id, target_id]
	)
