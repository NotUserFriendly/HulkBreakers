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
## docs/10 taskblock02 F3: a facing wedge on the ring, so the player can
## actually see which way a unit is turned before spending MP to change
## it — a tab riding the marker's own edge, pointing in
## `Unit.orientation`'s direction (docs/02's continuous, never-snapped
## angle, same one BodyProjector reads). Sized to actually read at the
## default tactical camera distance (docs/10: "legibility is not
## optional") — taller than the ground marker so it never z-fights with it.
const FACING_WEDGE_SIZE := Vector3(0.16, 0.10, 0.30)
const FACING_WEDGE_OFFSET := TEAM_MARKER_RADIUS * 0.85

var unit: Unit
var material_table: MaterialTable

## docs/10 taskblock03 E3: "the wedge shows committed state — it must show
## PREVIEW." Set by whoever drives selection (BattleScene) to
## SelectionController.previewed_orientation() while this is the selected
## unit during TACTICS; null renders the committed `unit.orientation`
## instead (RESOLUTION, or any unit that isn't selected).
var preview_orientation: Variant = null

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
	add_child(_build_facing_wedge())

	var rim: StandardMaterial3D = WorldPalette.rim_outline_material(
		WorldPalette.team_color(unit.squad_id)
	)
	for placement: BoxPlacement in UnitGeometry.placements(unit, preview_orientation):
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


func _build_facing_wedge() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = FACING_WEDGE_SIZE
	instance.mesh = box
	instance.material_override = WorldPalette.overlay_material(_marker_color())
	var orientation: float = _display_orientation()
	var forward: Vector2 = BodyProjector.WORLD_FORWARD.rotated(orientation)
	var base := (
		Vector3(unit.cell.x, TEAM_MARKER_Y + TEAM_MARKER_HEIGHT, unit.cell.y)
		* UnitGeometry.CELL_SIZE
	)
	instance.position = base + Vector3(forward.x, 0.0, forward.y) * FACING_WEDGE_OFFSET
	instance.basis = Basis(Vector3.UP, orientation)
	return instance


func _display_orientation() -> float:
	return preview_orientation if preview_orientation != null else unit.orientation
