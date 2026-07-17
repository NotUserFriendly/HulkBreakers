class_name AimView
extends Node3D

## docs/10 Phase 12.3, "the signature screen": draws exactly what
## AimController.resolve() says. Pure presentation — every number (which
## body is being read, what the reticle resolves to, how many scatter
## rings and how wide) comes from the controller; this Node only spawns
## meshes and sets label text from it (docs/08's three laws).
##
## docs/09 taskblock06 Pass H: "an image of a dartboard, projected onto a
## window... along with a light shadow of the dartboard casting across the
## actual shell's shape" — two views of one thing (ShotPlane.build/
## resolve_ray, Pass A), never a second resolution mechanism:
## - the WINDOW (_window): a transparent quad carrying the ring image, on a
##   fixed plane just in front of the currently-read layer's own frontmost
##   part — flat, crisp, what you aim WITH.
## - the SHADOW (_decal): a Godot Decal projecting that same ring image
##   along the identical shooter->target axis onto the real geometry — the
##   rings visibly wrapping the actual curved/boxy surface, proof the
##   window and the world agree.
## Scrolling the READ layer moves the window's own depth; the shadow always
## sits at the target's own fixed distance (RESOLVES, never READING) — see
## refresh() below.

## A targeting overlay, deliberately distinct from any WorldPalette material
## or team color so a ring never blends into armor or a unit's own team rim.
const RING_COLOR := Color(0.95, 0.55, 0.15)
## runNotes.md: "it also needs to be slightly transparent, so what is being
## targeted is clearer" — opaque rings used to fully hide whatever body they
## sat in front of.
const RING_ALPHA := 0.55
## docs/09 taskblock06 Pass H: how far in front of the READ layer's own
## frontmost surface the window sits — just enough that it never
## z-fights with the geometry it's reading, a flagged tuning number like
## every other visual-only constant here, not a design decision.
const WINDOW_DEPTH_EPSILON := 0.05
## How deep (along the fire axis) the shadow Decal's own projection box
## extends — generous enough to guarantee it actually reaches the target's
## real surface regardless of exactly where that surface sits relative to
## the reticle's own plane, without reaching so far it bleeds onto
## unrelated geometry further along the same line. Flagged, not tuned.
const DECAL_PROJECTION_DEPTH := 3.0
## docs/10 taskblock03 F2: "same geometry the tracer will use, so what
## you're shown is what will fire" — same TracerGeometry as
## ResolutionPlayer's own tracer, same muzzle height, but translucent and
## dim: a preview, never mistaken for an actual hit.
const TARGETING_LINE_THICKNESS := ResolutionPlayer.TRACER_THICKNESS
const TARGETING_LINE_COLOR := Color(0.95, 0.55, 0.15, 0.35)

var tactics: TacticsController
var readout: RichTextLabel

var _window: MeshInstance3D
var _decal: Decal
var _targeting_line: MeshInstance3D


func _init() -> void:
	_window = MeshInstance3D.new()
	_window.visible = false
	add_child(_window)
	_decal = Decal.new()
	_decal.visible = false
	add_child(_decal)
	_targeting_line = MeshInstance3D.new()
	_targeting_line.visible = false
	add_child(_targeting_line)


func setup(p_tactics: TacticsController, p_readout: RichTextLabel) -> void:
	tactics = p_tactics
	readout = p_readout
	tactics.aim_changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	if tactics != null and tactics.aiming_at != null:
		refresh()


func refresh() -> void:
	_window.visible = false
	_decal.visible = false
	_targeting_line.visible = false
	if tactics == null or tactics.aiming_at == null:
		readout.text = ""
		return

	# docs/10 taskblock03 D5: shooter/target/plane must all come from the
	# SAME speculative preview (tactics.aim_state()) — reading them via
	# separate calls would hand back unrelated clones whose Parts never
	# object-match each other, breaking ShotPlane.center_of below.
	var aim: Dictionary = tactics.aim_state()
	if aim.is_empty():
		readout.text = ""
		return
	var shooter: Unit = aim["shooter"]
	var target: Unit = aim["target"]
	var plane: Array[Region] = aim["plane"]
	var state: CombatState = aim["state"]
	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	if weapon == null:
		readout.text = "[UNARMED]"
		return

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + tactics.reticle_offset
	var result: AimResult = AimController.resolve(
		plane, aim_point, tactics.layer_index, weapon, shooter, target.cell, state
	)

	# docs/09 taskblock06 Pass H: the shadow (and the targeting line, the
	# same "what will actually fire" concept) always sit at the target's
	# own fixed distance — RESOLVES, never READING, exactly the invariant
	# AimController.resolve() itself already enforces for the text readout.
	var target_depth: float = Vector2(target.cell - shooter.cell).length()
	var target_point: Vector3 = AimPlaneGeometry.world_point_at_depth(
		shooter.cell, target.cell, aim_point, target_depth
	)

	# docs/09 taskblock06 Pass H: "scrolling the READ layer moves the
	# window backward through the scene" — the window's own depth is
	# whatever the CURRENTLY READ layer's frontmost surface sits at, not
	# fixed at the target's own cell like the shadow/targeting line above.
	var window_depth: float = target_depth
	if not result.layers.is_empty():
		var clamped: int = clampi(tactics.layer_index, 0, result.layers.size() - 1)
		window_depth = result.layers[clamped].frontmost_depth() - WINDOW_DEPTH_EPSILON
	var window_point: Vector3 = AimPlaneGeometry.world_point_at_depth(
		shooter.cell, target.cell, aim_point, window_depth
	)

	_draw_window(window_point, shooter.cell, target.cell, result.rings)
	_draw_decal(target_point, shooter.cell, target.cell, result.rings)
	# docs/10 taskblock03 F2 / runNotes.md: "a line from the shooter's
	# muzzle to the reticle's world point... if a pistol is what's shooting,
	# the targeting line should come from the pistol," not a generic
	# torso-height point.
	_draw_targeting_line(UnitGeometry.muzzle_point(shooter, weapon), target_point)
	readout.text = _readout_text(result)


func _readout_text(result: AimResult) -> String:
	var layer_count: int = result.layers.size()
	var clamped: int = clampi(tactics.layer_index, 0, max(layer_count - 1, 0))
	var resolves_text := "miss"
	if result.resolves != null:
		resolves_text = "%s / %s" % [_body_name(result.resolves.body), result.resolves.part.id]
	return (
		"READING: %s (layer %d of %d)\nRESOLVES: %s"
		% [_body_name(result.reading), clamped + 1, layer_count, resolves_text]
	)


func _body_name(body: Variant) -> String:
	if body is Unit:
		return "unit_%d" % (body as Unit).id
	if body is Part:
		return String((body as Part).id)
	return "none"


## docs/09 taskblock06 Pass H: "the window" — a transparent quad carrying
## the ring image, face-on to the shooter (the quad's own front face, +Z,
## ends up pointing back along -forward — see _window_basis). A no-op with
## no scatter rings resolved (an unarmed preview never reaches here anyway,
## caught earlier in refresh()).
func _draw_window(
	world_point: Vector3, shooter_cell: Vector2i, target_cell: Vector2i, rings: Array[Ring]
) -> void:
	var outer: float = rings[rings.size() - 1].radius if not rings.is_empty() else 0.0
	if outer <= 0.0:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(outer, outer) * 2.0
	quad.material = WorldPalette.translucent_textured_material(_ring_texture(rings))
	_window.mesh = quad
	_window.transform = Transform3D(_window_basis(shooter_cell, target_cell), world_point)
	_window.visible = true


## docs/09 taskblock06 Pass H: "the shadow" — a Decal projecting the same
## ring image along the identical shooter->target axis resolve_ray uses
## (docs/09 taskblock06 Pass A), so the rings visibly wrap the real
## geometry wherever it actually sits relative to the reticle's own plane.
func _draw_decal(
	world_point: Vector3, shooter_cell: Vector2i, target_cell: Vector2i, rings: Array[Ring]
) -> void:
	var outer: float = rings[rings.size() - 1].radius if not rings.is_empty() else 0.0
	if outer <= 0.0:
		return
	_decal.texture_albedo = _ring_texture(rings)
	_decal.size = Vector3(outer * 2.0, DECAL_PROJECTION_DEPTH, outer * 2.0)
	_decal.transform = Transform3D(_decal_basis(shooter_cell, target_cell), world_point)
	_decal.visible = true


func _ring_texture(rings: Array[Ring]) -> ImageTexture:
	var image: Image = DartboardTexture.build(
		rings, Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_ALPHA)
	)
	return ImageTexture.create_from_image(image)


## The window's own visible face points back at the shooter (docs/09
## taskblock06 Pass H: "this is what you aim with" — legible face-on, never
## edge-on). QuadMesh's own front face is local +Z; Basis.looking_at(dir,
## up)'s own convention makes local -Z point along `dir`, so local +Z ends
## up pointing the opposite way — exactly -forward, back toward the
## shooter — with no extra rotation needed.
static func _window_basis(shooter_cell: Vector2i, target_cell: Vector2i) -> Basis:
	return Basis.looking_at(_forward(shooter_cell, target_cell), Vector3.UP)


## docs/09 taskblock06 Pass H: "the decal must use the same axis the ray
## uses" — Godot's Decal always projects along its own local -Y, so this
## maps -Y directly onto the shooter->target direction (the identical
## direction ShotPlane.build/resolve_ray project along), never a
## camera-facing or otherwise-derived orientation. perp_axis (the same
## lateral axis the window/reticle already use) becomes local X; the
## remaining axis (X cross Y) works out to plain world-up, since both X and
## the projection direction are horizontal by construction (docs/02: shots
## travel horizontally) — that's local Z, the ring image's own vertical
## axis.
static func _decal_basis(shooter_cell: Vector2i, target_cell: Vector2i) -> Basis:
	var forward: Vector3 = _forward(shooter_cell, target_cell)
	var perp: Vector2 = AimPlaneGeometry.perp_axis(shooter_cell, target_cell)
	var x_axis := Vector3(perp.x, 0.0, perp.y)
	var y_axis: Vector3 = -forward
	var z_axis: Vector3 = x_axis.cross(y_axis)
	return Basis(x_axis, y_axis, z_axis)


static func _forward(shooter_cell: Vector2i, target_cell: Vector2i) -> Vector3:
	var direction: Vector2 = Vector2(target_cell - shooter_cell).normalized()
	return Vector3(direction.x, 0.0, direction.y)


## docs/10 taskblock03 F2: "draw a line from the shooter's muzzle to the
## reticle's world point." Reuses TracerGeometry — the exact box-mesh line
## construction the real resolution tracer uses — so what's shown is
## geometrically identical to what fires, just translucent and dim.
func _draw_targeting_line(from: Vector3, to: Vector3) -> void:
	if (to - from).length() < 0.001:
		return
	var box := BoxMesh.new()
	box.size = TracerGeometry.segment_size(from, to, TARGETING_LINE_THICKNESS)
	box.material = WorldPalette.translucent_material(TARGETING_LINE_COLOR)
	_targeting_line.mesh = box
	_targeting_line.transform = TracerGeometry.segment_transform(from, to)
	_targeting_line.visible = true
