class_name HitVolumeView
extends Node3D

## docs/10 "render is hitbox": every box UnitGeometry.placements() produces
## becomes exactly one BoxMesh, nothing more. `refresh()` rebuilds from the
## unit's current state — call it after resolution so destroyed parts
## vanish; there is no per-part diffing, only rebuild-from-truth.
##
## docs/09 taskblock06 Pass I1: promoted from prototype scaffolding to a
## permanent, toggleable feature (renamed from `UnitView`) — a dev tool,
## the one checkpoint artifact for "does the hitbox match the mesh" that
## can never be automated, and plausibly a player-facing option later.
##
## docs/09 taskblock06 Pass I2: a Part's optional `mesh_scene` (commissioned
## art) is drawn in the box's place — decided per PART, never globally, so
## mixed assemblies (a rigged torso above box arms) are legal with no
## cutover. `show_hit_volumes` overlays the boxes back on TOP of a
## commissioned mesh too, independent of whether that mesh exists at all —
## the whole point of a hitbox visualiser is to check the two agree.
## Nothing here ever touches what actually resolves a shot
## (BodyProjector/ShotPlane/UnitGeometry all still read `volume` alone) —
## the mesh is drawn, never hit-tested.
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
## docs/10 taskblock03 G: "a unit with no matrix docked... needs to read as
## down at a glance." Darkens the team ring rather than a separate material —
## cheap, and it still reads as "this squad's, but not right."
const DOWNED_MARKER_DIM := 0.4

var unit: Unit
var material_table: MaterialTable

## docs/09 taskblock06 Pass I1: "toggleable" — false is the Pass I2 default
## ("the view draws the mesh if present, hit volumes otherwise"); true
## overlays hit-volume boxes on every part regardless, commissioned mesh or
## not. Set directly and call refresh() (matching preview_orientation's own
## convention below — a plain field, not a setter method).
var show_hit_volumes: bool = false

## docs/10 taskblock03 E3: "the wedge shows committed state — it must show
## PREVIEW." Set by whoever drives selection (BattleScene) to
## SelectionController.previewed_orientation() while this is the selected
## unit during TACTICS; null renders the committed `unit.orientation`
## instead (RESOLUTION, or any unit that isn't selected).
var preview_orientation: Variant = null

var _selected: bool = false
var _team_marker: MeshInstance3D
## docs/10 taskblock05 C: "hovering a part highlights it in the world" —
## which Part is currently glowing, and which of this unit's own mesh
## instances belong to it (a part can own more than one box). Rebuilt every
## refresh(); highlight_part() re-applies against the fresh set so a
## highlight survives a rebuild (e.g. taking damage mid-hover).
var _highlighted_part: Part = null
var _meshes_by_part: Dictionary = {}  # Part -> Array[MeshInstance3D]


func setup(p_unit: Unit, p_material_table: MaterialTable) -> void:
	unit = p_unit
	material_table = p_material_table
	refresh()


## Brightens the ground marker — TacticsController.selection_changed drives
## this across every HitVolumeView (docs/10: "the selected unit gets a brighter
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
	_meshes_by_part.clear()
	if unit == null:
		return

	_team_marker = _build_team_marker()
	add_child(_team_marker)
	if not is_downed():
		# docs/10 taskblock03 G: "kill its facing wedge" — a downed unit
		# isn't facing anything.
		add_child(_build_facing_wedge())

	var team_color: Color = WorldPalette.team_color(unit.squad_id)
	# docs/10 taskblock05 F3: DOWN is now a real Pose, passed in explicitly
	# (taskblock03 G's old _downed_transform hack is gone) — no separate
	# view-only transform left to apply after the fact; UnitGeometry
	# composes it directly, so any headless caller that goes through the
	# same explicit override (UnitPicker's hit-testing included, once
	# something threads it through) agrees with what's drawn.
	var pose: Variant = Poses.down() if is_downed() else null
	# docs/09 taskblock06 Pass I2: grouped by part first — a commissioned
	# mesh draws ONCE per part (it models the whole part, not one box at a
	# time), while hit-volume boxes still draw once per BoxPlacement.
	var placements_by_part: Dictionary = {}  # Part -> Array[BoxPlacement]
	var part_order: Array[Part] = []
	for placement: BoxPlacement in UnitGeometry.placements(unit, preview_orientation, pose):
		if not placements_by_part.has(placement.part):
			placements_by_part[placement.part] = [] as Array[BoxPlacement]
			part_order.append(placement.part)
		(placements_by_part[placement.part] as Array[BoxPlacement]).append(placement)

	for part: Part in part_order:
		var part_placements: Array[BoxPlacement] = placements_by_part[part]
		if part.mesh_scene != null:
			_add_mesh_instance(part, part_placements[0])
		# docs/09 taskblock06 Pass I2: "the view draws the mesh if present,
		# hit volumes otherwise" — the box is the ONLY representation a
		# part without a commissioned mesh has, so it always draws one
		# regardless of the toggle; a part WITH a mesh only also gets boxes
		# when show_hit_volumes explicitly asks for the overlay.
		if part.mesh_scene == null or show_hit_volumes:
			for placement: BoxPlacement in part_placements:
				_add_box_instance(placement, team_color)

	if _highlighted_part != null:
		highlight_part(_highlighted_part)


## docs/09 taskblock06 Pass I2: one instance per part, positioned at that
## part's own composed transform (the same one a box placement carries,
## minus the box-local center offset a box needs and a whole-part mesh
## doesn't) — never hit-tested, never read by BodyProjector/ShotPlane.
func _add_mesh_instance(part: Part, placement: BoxPlacement) -> void:
	var instance: Node3D = part.mesh_scene.instantiate() as Node3D
	instance.transform = placement.transform
	add_child(instance)


func _add_box_instance(placement: BoxPlacement, team_color: Color) -> void:
	var instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = placement.box.size
	var material: StandardMaterial3D = WorldPalette.lit_material(
		material_table.color_for(placement.part.material)
	)
	# docs/10 taskblock05 C: each box gets its OWN rim instance (never
	# shared across boxes) so a part's own highlight next_pass can chain
	# onto just its own materials, never every box on the unit.
	material.next_pass = WorldPalette.rim_outline_material(team_color)
	box_mesh.material = material
	instance.mesh = box_mesh
	instance.transform = placement.transform.translated_local(placement.box.center)
	add_child(instance)
	if not _meshes_by_part.has(placement.part):
		_meshes_by_part[placement.part] = [] as Array[MeshInstance3D]
	(_meshes_by_part[placement.part] as Array[MeshInstance3D]).append(instance)


## docs/10 taskblock05 C: "hovering a part highlights it in the world" —
## the team-rim technique again, one more grown outline pass chained after
## the existing team rim, HulkTheme.HIGHLIGHT-toned (WorldPalette's own
## copy of it). A no-op if this unit doesn't own `part` at all (hovering a
## different unit's row/box never bleeds a glow onto this one).
func highlight_part(part: Part) -> void:
	_highlighted_part = part
	var glow: StandardMaterial3D = WorldPalette.rim_outline_material(WorldPalette.HOVER_HIGHLIGHT)
	for candidate: Part in _meshes_by_part:
		var meshes: Array[MeshInstance3D] = _meshes_by_part[candidate]
		for instance: MeshInstance3D in meshes:
			var box_mesh: BoxMesh = instance.mesh
			var material: StandardMaterial3D = box_mesh.material
			var team_rim: StandardMaterial3D = material.next_pass
			team_rim.next_pass = glow if candidate == part else null


func clear_highlight() -> void:
	highlight_part(null)


## docs/10 taskblock03 G: "a unit with no matrix docked (a shell)... needs
## to read as down." Delegates to Unit.is_downed() (taskblock05 F3: moved
## there now that being downed is a geometry fact, not just a view one).
func is_downed() -> bool:
	return unit != null and unit.is_downed()


func _marker_color() -> Color:
	var base: Color = WorldPalette.team_color(unit.squad_id)
	var color: Color = base.lerp(Color.WHITE, SELECTED_BRIGHTEN) if _selected else base
	if is_downed():
		color = Color(
			color.r * DOWNED_MARKER_DIM, color.g * DOWNED_MARKER_DIM, color.b * DOWNED_MARKER_DIM
		)
	return color


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
	# docs/09 taskblock07 Pass B1: forward_for(), not WORLD_FORWARD.rotated()
	# directly — the wedge's own POSITION and its own ROTATION
	# (Basis(Vector3.UP, orientation) just below) must agree, and only
	# forward_for() is built from that same Basis.
	var forward: Vector2 = BodyProjector.forward_for(orientation)
	var base := (
		Vector3(unit.cell.x, TEAM_MARKER_Y + TEAM_MARKER_HEIGHT, unit.cell.y)
		* UnitGeometry.CELL_SIZE
	)
	instance.position = base + Vector3(forward.x, 0.0, forward.y) * FACING_WEDGE_OFFSET
	instance.basis = Basis(Vector3.UP, orientation)
	return instance


func _display_orientation() -> float:
	return preview_orientation if preview_orientation != null else unit.orientation
