class_name UnitView
extends Node3D

## docs/10 "render is hitbox": every box UnitGeometry.placements() produces
## becomes exactly one BoxMesh, nothing more. `refresh()` rebuilds from the
## unit's current state — call it after resolution so destroyed parts
## vanish; there is no per-part diffing, only rebuild-from-truth.

var unit: Unit
var material_table: MaterialTable


func setup(p_unit: Unit, p_material_table: MaterialTable) -> void:
	unit = p_unit
	material_table = p_material_table
	refresh()


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if unit == null:
		return
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = placement.box.size
		box_mesh.material = HulkTheme.flat_material(
			HulkTheme.color_for_material(placement.part.material, material_table)
		)
		instance.mesh = box_mesh
		instance.transform = placement.transform.translated_local(placement.box.center)
		add_child(instance)
