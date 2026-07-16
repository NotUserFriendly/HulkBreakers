class_name UnitView
extends Node3D

## docs/10 "render is hitbox": every box UnitGeometry.placements() produces
## becomes exactly one BoxMesh, nothing more. `refresh()` rebuilds from the
## unit's current state — call it after resolution so destroyed parts
## vanish; there is no per-part diffing, only rebuild-from-truth.
##
## Team flagging (docs/10) is an overlay on top, never touching a part's
## material albedo: a ground disc under the unit (brighter when selected)
## plus a rim outline riding each part material's own `next_pass`.

const TEAM_MARKER_RADIUS := 0.4
const TEAM_MARKER_HEIGHT := 0.02
const TEAM_MARKER_Y := 0.01
const SELECTED_BRIGHTEN := 0.35

var unit: Unit
var material_table: MaterialTable

var _selected: bool = false
var _team_marker: MeshInstance3D


func setup(p_unit: Unit, p_material_table: MaterialTable) -> void:
	unit = p_unit
	material_table = p_material_table
	refresh()


## Brightens the ground marker — TacticsController.selection_changed drives
## this across every UnitView (docs/10: "the selected unit gets a brighter
## ring").
func set_selected(is_selected: bool) -> void:
	_selected = is_selected
	if _team_marker != null and unit != null:
		_team_marker.material_override = WorldPalette.overlay_material(_marker_color())


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_team_marker = null
	if unit == null:
		return

	_team_marker = _build_team_marker()
	add_child(_team_marker)

	var rim: StandardMaterial3D = WorldPalette.rim_outline_material(
		WorldPalette.team_color(unit.squad_id)
	)
	for placement: BoxPlacement in UnitGeometry.placements(unit):
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = placement.box.size
		var material: StandardMaterial3D = WorldPalette.lit_material(
			material_table.color_for(placement.part.material)
		)
		material.next_pass = rim
		box_mesh.material = material
		instance.mesh = box_mesh
		instance.transform = placement.transform.translated_local(placement.box.center)
		add_child(instance)


func _marker_color() -> Color:
	var base: Color = WorldPalette.team_color(unit.squad_id)
	return base.lerp(Color.WHITE, SELECTED_BRIGHTEN) if _selected else base


func _build_team_marker() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TEAM_MARKER_RADIUS
	disc.bottom_radius = TEAM_MARKER_RADIUS
	disc.height = TEAM_MARKER_HEIGHT
	instance.mesh = disc
	instance.material_override = WorldPalette.overlay_material(_marker_color())
	instance.position = Vector3(unit.cell.x, TEAM_MARKER_Y, unit.cell.y) * UnitGeometry.CELL_SIZE
	return instance
