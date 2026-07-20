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
## optional").
const FACING_WEDGE_SIZE := Vector3(0.16, 0.10, 0.30)
const FACING_WEDGE_OFFSET := TEAM_MARKER_RADIUS * 0.85
## taskblock-26 Pass A3: the wedge USED to center on `TEAM_MARKER_Y +
## TEAM_MARKER_HEIGHT` (0.03) — with its own 0.10-tall box, that put its
## bottom face at -0.02, below the ground plane (Y=0) and co-planar with
## any ground-tier marker sitting near it (board_view.gd's own
## EXTRACTION_TILE_HEIGHT, 0.010 — the reported extract-tile/facing-
## indicator z-fight). Raised so the wedge's own bottom face (this minus
## half of FACING_WEDGE_SIZE.y) clears both the team marker disc's own
## top surface and every ground-tier board marker with real headroom, not
## just nominally "taller."
const FACING_WEDGE_Y := 0.09
## docs/10 taskblock03 G: "a unit with no matrix docked... needs to read as
## down at a glance." Darkens the team ring rather than a separate material —
## cheap, and it still reads as "this squad's, but not right."
const DOWNED_MARKER_DIM := 0.4
## taskblock-13 Pass F: "every placeholder gun box renders text on it
## stating what it is... cosmetic, dev-legibility only." Small — these
## are gun-sized boxes (a chaingun's own box is ~0.15m wide), not
## person-sized, so `board_view.gd`'s own WAYPOINT_FONT_SIZE (24, sized
## for a whole-cell waypoint marker) would dwarf one outright.
const WEAPON_LABEL_FONT_SIZE := 10
const WEAPON_LABEL_COLOR := Color(0.95, 0.95, 0.95)
## taskblock-19 Pass I3: "printed on the side of the weapon, scaled to
## fit the weapon's box face" — how much of the face's own SHORT edge
## the text's cap-height fills. Flagged, not a tuned design number; only
## "actually fitted, not a fixed size regardless of the box" is asked.
const WEAPON_LABEL_FIT_FRACTION := 0.6
## Clears the face's own surface without visibly floating off it —
## same order of magnitude as board_view.gd's own overlay-above-ground
## offsets (0.02-0.04).
const WEAPON_LABEL_SURFACE_OFFSET := 0.005
## taskblock-22 Pass G2: the isolate-camera primitive — a SECOND, real
## Camera3D (InspectPanel's own bot viewer) shares this SAME live World3D
## (never a disconnected duplicate) so it can render the actual unit at
## its actual board position, rather than rebuilding fresh geometry at
## the origin. A render layer no other node in the world is ever placed
## on — tagging JUST this unit's own visuals with it and restricting the
## isolate camera's own `cull_mask` to that one layer means nothing else
## sharing the world (terrain, cover, other units) draws through it,
## without touching any other node's `layers` or this unit's own normal
## (layer-1) visibility to the real CameraRig.
const ISOLATE_LAYER := 2

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
		var has_mesh: bool = part.mesh_scene != null
		# taskblock-10 Pass A: the primitive is the same tier as a
		# commissioned mesh — a whole-part cosmetic stand-in, drawn once,
		# never per-box. BOX (the default) isn't a stand-in at all; it IS
		# the existing box-per-placement render, so it stays on that path
		# below rather than going through this branch.
		var has_primitive: bool = not has_mesh and part.render_primitive != &"BOX"
		if has_mesh:
			_add_mesh_instance(part, part_placements[0])
		elif has_primitive:
			_add_primitive_instance(part, part_placements[0], team_color)
		# docs/09 taskblock06 Pass I2: "the view draws the mesh if present,
		# hit volumes otherwise" — the box is the ONLY representation a
		# part with neither a commissioned mesh nor a non-BOX primitive
		# has, so it always draws one regardless of the toggle; a part
		# with either only also gets boxes when show_hit_volumes
		# explicitly asks for the overlay.
		if (not has_mesh and not has_primitive) or show_hit_volumes:
			for placement: BoxPlacement in part_placements:
				_add_box_instance(placement, team_color)

	if _highlighted_part != null:
		highlight_part(_highlighted_part)


## docs/10 taskblock04 C1's own "field object" case: a bare part tree with
## no owning Unit at all — no facing, no pose, no team allegiance (a raw
## definition being edited isn't on anyone's squad). Used by the resource
## editor's own preview instead of the taskblock-11 C's original approach
## (wrapping the part under a throwaway matrix-hosting carrier purely to
## keep `refresh()`'s Unit-based `is_downed()` from reading true) — that
## carrier fought this function's own team/pose machinery instead of
## sidestepping it, and its side effects (a facing wedge with nothing to
## point at, a rim outline meant to read as "your unit" on a lone part)
## were exactly the "extraneous... faces" and offsets reported against it.
## `root == null` clears the view, same as `unit = null; refresh()`.
## Still B1: "the preview is what the game will render" for the part's own
## geometry — only the allegiance overlay is dropped, plus a single flat
## marker disc in `marker_color` centered under whatever's drawn, geometry
## re-centered on the origin so `rotate_y`ing the parent pivot spins it in
## place instead of orbiting off-center.
func show_assembly(root: Part, p_material_table: MaterialTable, marker_color: Color) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	unit = null
	_team_marker = null
	_meshes_by_part.clear()
	if root == null:
		return
	material_table = p_material_table

	_team_marker = _build_marker_disc(marker_color)
	add_child(_team_marker)

	var raw_placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(root, Vector2i.ZERO)
	# Only x/z are zeroed — the part's own authored elevation (docs/01's
	# ROOT_ELEVATION, torso's own volume boxes sitting up around y=1.5)
	# stays exactly what the game would render; only the HORIZONTAL center
	# is pulled onto the pivot's own rotation axis so a spin never drifts.
	var center: Vector3 = UnitGeometry.placements_aabb(raw_placements).get_center()
	var recenter := Transform3D(Basis.IDENTITY, Vector3(-center.x, 0.0, -center.z))

	var placements_by_part: Dictionary = {}  # Part -> Array[BoxPlacement]
	var part_order: Array[Part] = []
	for placement: BoxPlacement in raw_placements:
		placement.transform = recenter * placement.transform
		if not placements_by_part.has(placement.part):
			placements_by_part[placement.part] = [] as Array[BoxPlacement]
			part_order.append(placement.part)
		(placements_by_part[placement.part] as Array[BoxPlacement]).append(placement)

	for part: Part in part_order:
		var part_placements: Array[BoxPlacement] = placements_by_part[part]
		var has_mesh: bool = part.mesh_scene != null
		var has_primitive: bool = not has_mesh and part.render_primitive != &"BOX"
		if has_mesh:
			_add_mesh_instance(part, part_placements[0])
		elif has_primitive:
			_add_primitive_instance(part, part_placements[0], Color.WHITE, false)
		if not has_mesh and not has_primitive:
			for placement: BoxPlacement in part_placements:
				_add_box_instance(placement, Color.WHITE, false)


## docs/09 taskblock06 Pass I2: one instance per part, positioned at that
## part's own composed transform (the same one a box placement carries,
## minus the box-local center offset a box needs and a whole-part mesh
## doesn't) — never hit-tested, never read by BodyProjector/ShotPlane.
func _add_mesh_instance(part: Part, placement: BoxPlacement) -> void:
	var instance: Node3D = part.mesh_scene.instantiate() as Node3D
	instance.transform = placement.transform
	add_child(instance)


## taskblock-10 Pass A: one primitive per part, positioned at that part's
## own composed transform — same convention as `_add_mesh_instance`
## (ignores the box-local center offset; a whole-part stand-in doesn't
## have one). Registered into `_meshes_by_part`/rim-outlined exactly like
## a box instance so hover-highlight keeps working on a primitive part.
func _add_primitive_instance(
	part: Part, placement: BoxPlacement, team_color: Color, apply_rim: bool = true
) -> void:
	var instance := MeshInstance3D.new()
	var mesh: PrimitiveMesh = _primitive_mesh(part.render_primitive)
	var color: Color = (
		part.render_color_override
		if part.render_color_override.a > 0.0
		else material_table.color_for(part.material)
	)
	var material: StandardMaterial3D = WorldPalette.lit_material(color)
	if apply_rim:
		material.next_pass = WorldPalette.rim_outline_material(team_color)
	mesh.material = material
	instance.mesh = mesh
	instance.transform = placement.transform
	instance.scale = part.render_scale
	add_child(instance)
	if not _meshes_by_part.has(part):
		_meshes_by_part[part] = [] as Array[MeshInstance3D]
	(_meshes_by_part[part] as Array[MeshInstance3D]).append(instance)
	_add_weapon_label(part, instance)


## Base unit-size primitives (1.0 diameter, 1.0 height) — `render_scale`
## does the rest. Falls back to a unit BoxMesh for any StringName outside
## the authored vocabulary rather than erroring; authoring a real shape is
## opt-in, same posture as `MaterialTable.get_entry`'s unknown-material
## fallback.
func _primitive_mesh(kind: StringName) -> PrimitiveMesh:
	match kind:
		&"CYLINDER":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 1.0
			return mesh
		&"SPHERE":
			var mesh := SphereMesh.new()
			mesh.radius = 0.5
			mesh.height = 1.0
			return mesh
		&"CAPSULE":
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.3
			mesh.height = 1.0
			return mesh
		_:
			var mesh := BoxMesh.new()
			mesh.size = Vector3.ONE
			return mesh


func _add_box_instance(placement: BoxPlacement, team_color: Color, apply_rim: bool = true) -> void:
	var instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = placement.box.size
	var material: StandardMaterial3D = WorldPalette.lit_material(
		material_table.color_for(placement.part.material)
	)
	# docs/10 taskblock05 C: each box gets its OWN rim instance (never
	# shared across boxes) so a part's own highlight next_pass can chain
	# onto just its own materials, never every box on the unit.
	if apply_rim:
		material.next_pass = WorldPalette.rim_outline_material(team_color)
	box_mesh.material = material
	instance.mesh = box_mesh
	instance.transform = placement.transform.translated_local(placement.box.center)
	add_child(instance)
	if not _meshes_by_part.has(placement.part):
		_meshes_by_part[placement.part] = [] as Array[MeshInstance3D]
	(_meshes_by_part[placement.part] as Array[MeshInstance3D]).append(instance)
	_add_weapon_label(placement.part, instance, placement.box.size)


## taskblock-13 Pass F: "every placeholder gun box renders text on it
## stating what it is... fitted to the box shape." A no-op for anything
## that isn't a weapon (`weapon_def == null`) or has no `display_name`
## authored — same "cosmetic only, never touches resolution" posture as
## `mesh_scene`/`render_primitive` above: nothing here is hit-tested, and
## it draws over whatever `instance` (a box OR a primitive) already is.
##
## taskblock-19 Pass I3: "printed on the side of the weapon, scaled to
## fit... not a floating billboard." `box_size` (real, real-only for
## `_add_box_instance` — every authored weapon today renders as a box)
## drives a real surface decal: projected onto the box's own LARGEST
## face (for a typical long, thin gun that's the side — height x length
## — literally "printed on the side"), scaled to that face's own short
## edge, offset just clear of the surface instead of floating in front
## of it. `box_size == null` (a mesh/primitive weapon render — none
## exist in authored data today, but the render path itself allows one)
## keeps the OLD floating-billboard behavior as a graceful fallback —
## never worse than before this pass, just not upgraded either, since
## there's no box face to print it on.
func _add_weapon_label(part: Part, instance: MeshInstance3D, box_size: Variant = null) -> void:
	if part.weapon_def == null or part.display_name == "":
		return
	var label := Label3D.new()
	label.text = part.display_name
	label.font_size = WEAPON_LABEL_FONT_SIZE
	label.modulate = WEAPON_LABEL_COLOR

	if box_size == null:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.002
		instance.add_child(label)
		return

	var size: Vector3 = box_size
	var xy: float = size.x * size.y
	var xz: float = size.x * size.z
	var yz: float = size.y * size.z
	var short_edge: float
	var half_depth: float
	var outward: Vector3
	if yz >= xy and yz >= xz:
		short_edge = minf(size.y, size.z)
		half_depth = size.x * 0.5
		outward = Vector3.RIGHT
	elif xz >= xy:
		short_edge = minf(size.x, size.z)
		half_depth = size.y * 0.5
		outward = Vector3.UP
	else:
		short_edge = minf(size.x, size.y)
		half_depth = size.z * 0.5
		outward = Vector3.BACK

	label.pixel_size = (short_edge * WEAPON_LABEL_FIT_FRACTION) / float(WEAPON_LABEL_FONT_SIZE)
	label.position = outward * (half_depth + WEAPON_LABEL_SURFACE_OFFSET)
	# Flat against the face: local +Z (a Label3D's own readable-face
	# normal, unbillboarded) points straight out along `outward`, local
	# +Y stays world-up so the text reads right-side up — except on the
	# top/bottom face itself (outward == UP/DOWN), where UP can't serve
	# as its own cross-product reference (a zero vector); BACK stands in
	# there instead, same "any reference not parallel to outward" need.
	var reference: Vector3 = Vector3.BACK if absf(outward.y) > 0.5 else Vector3.UP
	var basis := Basis()
	basis.z = outward
	basis.x = reference.cross(outward).normalized()
	basis.y = outward.cross(basis.x).normalized()
	label.basis = basis
	instance.add_child(label)


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


func set_isolated(enabled: bool) -> void:
	for meshes: Array in _meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			mesh_instance.set_layer_mask_value(ISOLATE_LAYER, enabled)
	if _team_marker != null:
		_team_marker.set_layer_mask_value(ISOLATE_LAYER, enabled)


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


## `show_assembly`'s own flat, fixed-color marker — no squad, no
## selection-brighten, no downed-dim (none of those concepts apply to a
## bare part with no owning Unit); always sits at the origin, same as
## `raw_placements` is centered onto.
func _build_marker_disc(color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TEAM_MARKER_RADIUS
	disc.bottom_radius = TEAM_MARKER_RADIUS
	disc.height = TEAM_MARKER_HEIGHT
	instance.mesh = disc
	instance.material_override = WorldPalette.overlay_material(color)
	instance.position = Vector3(0.0, TEAM_MARKER_Y, 0.0)
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
	var base := Vector3(unit.cell.x, FACING_WEDGE_Y, unit.cell.y) * UnitGeometry.CELL_SIZE
	instance.position = base + Vector3(forward.x, 0.0, forward.y) * FACING_WEDGE_OFFSET
	instance.basis = Basis(Vector3.UP, orientation)
	return instance


func _display_orientation() -> float:
	return preview_orientation if preview_orientation != null else unit.orientation
