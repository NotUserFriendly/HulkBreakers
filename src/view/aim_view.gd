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
##   fixed plane just in front of the TARGET's own nearest region (taskblock-
##   08 B2) — flat, crisp, what you aim WITH.
## - the SHADOW (_decal): a Godot Decal projecting that same ring image
##   along the identical shooter->target axis onto the real geometry — the
##   rings visibly wrapping the actual curved/boxy surface, proof the
##   window and the world agree.
## Both now sit at the target's own fixed position — "as close to the
## aimed-at model as possible without touching it" — regardless of which
## layer is currently READ; scrolling only ever changes the text readout
## and the shadow's own occlusion reading, never where either visual
## anchors (RESOLVES, never READING) — see refresh() below.

## A targeting overlay, deliberately distinct from any WorldPalette material
## or team color so a ring never blends into armor or a unit's own team rim.
const RING_COLOR := Color(0.95, 0.55, 0.15)
## runNotes.md: "it also needs to be slightly transparent, so what is being
## targeted is clearer" — opaque rings used to fully hide whatever body they
## sat in front of.
const RING_ALPHA := 0.55
## taskblock-08 B2: how far in front of the TARGET's own nearest region
## the window sits — just enough that it never z-fights with the geometry
## it's painted on, a flagged tuning number like every other visual-only
## constant here, not a design decision.
const WINDOW_DEPTH_EPSILON := 0.05
## docs/09 taskblock07 Pass B2, still true under taskblock-08 B2's own
## target-anchored fix: the window must never land behind the shooter. A
## body positioned "behind" the shooter along the fire line still gets a
## Region in the plane (ShotPlane.build projects every unit, not just ones
## in front), so the target's own nearest depth can be small or even
## negative, which WINDOW_DEPTH_EPSILON alone doesn't guard against
## (subtracting a small epsilon from an already-small-or-negative depth
## only makes it worse). Clamping to this minimum forward distance is what
## actually guarantees it: the window can recede as deep as the target's
## own nearest region says, but never comes back toward or past the
## shooter/camera.
const MIN_WINDOW_DEPTH := 0.3
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
	# taskblock-08 A1: "the armed action decides what a click means" applies
	# to the PREVIEW too — SAW armed must preview firing with the saw, not
	# whichever weapon DeepStrike.find_operable_weapon happened to find
	# first, or the dartboard/muzzle shown here could disagree with what
	# confirm_shot() actually queues (docs/08: tooltip and damage from the
	# same call).
	var weapon: Part = null
	if tactics.armed_action != null:
		weapon = ActionCatalog.provider_for(shooter, tactics.armed_action.id)
	if weapon == null:
		readout.text = "[UNARMED]"
		return

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + tactics.reticle_offset
	var result: AimResult = AimController.resolve(
		plane, aim_point, tactics.layer_index, weapon, shooter, target.cell, state
	)

	# docs/09 taskblock07 Pass D: "the shadow must use the same axis the ray
	# uses" — literally the same (muzzle, dir) AimController._resolve_hit()
	# itself builds for this exact aim_point, via the same
	# AimPlaneGeometry.ray_from_muzzle() bridge, never a separately
	# re-derived dead-ahead approximation (docs/02: dead-ahead and "the
	# reticle's own aim direction" only coincide when the reticle sits
	# exactly on the shooter->target line — any lateral aim offset makes
	# them different rays). Recomputed independently here rather than
	# threaded out of resolve() — the same primitives, so it can never
	# drift, and view/logic stay cleanly separated.
	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
	var ray: Dictionary = AimPlaneGeometry.ray_from_muzzle(
		shooter.cell, target.cell, aim_point, muzzle
	)
	if ray.is_empty():
		readout.text = _readout_text(result)
		return
	var dir: Vector3 = ray["dir"]

	# docs/09 taskblock06 Pass H: the shadow (and the targeting line, the
	# same "what will actually fire" concept) always sit at the target's
	# own fixed distance — RESOLVES, never READING, exactly the invariant
	# AimController.resolve() itself already enforces for the text readout.
	var target_depth: float = Vector2(target.cell - shooter.cell).length()
	var target_point: Vector3 = AimPlaneGeometry.world_point_at_depth(
		shooter.cell, target.cell, aim_point, target_depth
	)

	# taskblock-08 B2: the window's own depth is pinned to the TARGET's own
	# nearest region now — same fixed anchor as the shadow/targeting line
	# above, never the currently-READ layer (taskblock-07 B2's own anchor,
	# reversed: scrolling to inspect a body behind the target no longer
	# drags the window back through the scene with it). Clamped so it can
	# never land behind the shooter — AimController.window_depth()'s own
	# doc comment has the why.
	var depth: float = AimController.window_depth(
		result.layers, target, target_depth, WINDOW_DEPTH_EPSILON, MIN_WINDOW_DEPTH
	)
	var window_point: Vector3 = AimPlaneGeometry.world_point_at_depth(
		shooter.cell, target.cell, aim_point, depth
	)

	# taskblock-08 B3b/B3c: "camera's own rotation to point it at the center
	# of the dartboard on the window," then a capped lean toward the
	# reticle. `centre` is the honest window centre — the same real world
	# point AimPlaneGeometry already produces at aim_point (0, 0) — never a
	# fake look-at target; `reticle_point` is that identical geometry at
	# the reticle's own current aim_point, so the lean is driven by where
	# the reticle actually is, never by raw mouse motion (orbit stays
	# locked — B3a).
	var centre: Vector3 = AimPlaneGeometry.world_point(shooter.cell, target.cell, Vector2.ZERO)
	var reticle_point: Vector3 = AimPlaneGeometry.world_point(shooter.cell, target.cell, aim_point)
	tactics.camera_rig.aim_at(centre, reticle_point)

	_draw_window(window_point, dir, result.rings)
	_draw_decal(target_point, dir, result.rings)
	# docs/10 taskblock03 F2 / runNotes.md: "a line from the shooter's
	# muzzle to the reticle's world point... if a pistol is what's shooting,
	# the targeting line should come from the pistol," not a generic
	# torso-height point.
	_draw_targeting_line(muzzle, target_point)
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
## ends up pointing back along -dir — see _window_basis). A no-op with no
## scatter rings resolved (an unarmed preview never reaches here anyway,
## caught earlier in refresh()).
func _draw_window(world_point: Vector3, dir: Vector3, rings: Array[Ring]) -> void:
	var outer: float = rings[rings.size() - 1].radius if not rings.is_empty() else 0.0
	if outer <= 0.0:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(outer, outer) * 2.0
	quad.material = WorldPalette.translucent_textured_material(_ring_texture(rings))
	_window.mesh = quad
	_window.transform = Transform3D(_window_basis(dir), world_point)
	_window.visible = true


## docs/09 taskblock06 Pass H / taskblock07 Pass D: "the shadow" — a Decal
## projecting the same ring image (aiming dot included) along `dir` — the
## literal same axis `resolve_ray` casts along for this exact aim_point
## (refresh() builds `dir` via the identical AimPlaneGeometry.ray_from_
## muzzle() bridge AimController._resolve_hit() itself uses) — so the
## rings, and the dot most visibly of all, wrap the real geometry exactly
## where a shot would actually go. That's what makes this proof rather
## than decoration.
func _draw_decal(world_point: Vector3, dir: Vector3, rings: Array[Ring]) -> void:
	var outer: float = rings[rings.size() - 1].radius if not rings.is_empty() else 0.0
	if outer <= 0.0:
		return
	_decal.texture_albedo = _ring_texture(rings)
	_decal.size = Vector3(outer * 2.0, DECAL_PROJECTION_DEPTH, outer * 2.0)
	_decal.transform = Transform3D(_decal_basis(dir), world_point)
	_decal.visible = true


func _ring_texture(rings: Array[Ring]) -> ImageTexture:
	var image: Image = DartboardTexture.build(
		rings, Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_ALPHA)
	)
	return ImageTexture.create_from_image(image)


## The window's own visible face points back along `dir` (docs/09
## taskblock06 Pass H: "this is what you aim with" — legible face-on, never
## edge-on). QuadMesh's own front face is local +Z; Basis.looking_at(dir,
## up)'s own convention makes local -Z point along `dir`, so local +Z ends
## up pointing the opposite way — exactly -dir, back toward the shooter —
## with no extra rotation needed.
static func _window_basis(dir: Vector3) -> Basis:
	return Basis.looking_at(dir, Vector3.UP)


## docs/09 taskblock06 Pass H / taskblock07 Pass D: "the decal must use the
## same axis the ray uses" — Godot's Decal always projects along its own
## local -Y, so this maps -Y directly onto `dir`. The lateral axis (local
## X) is derived FROM `dir` itself (perpendicular, in the horizontal
## plane) rather than the shooter->target cell direction — `dir` can
## deviate from that dead-ahead line (a laterally offset reticle), and a
## lateral axis borrowed from the wrong line would no longer be
## perpendicular to `dir`, breaking the basis. The remaining axis (X cross
## Y) works out to plain world-up, since both X and `dir` are horizontal
## by construction (docs/02: shots travel horizontally, dir.y == 0) —
## that's local Z, the ring image's own vertical axis.
static func _decal_basis(dir: Vector3) -> Basis:
	var x_axis := Vector3(-dir.z, 0.0, dir.x)
	var y_axis: Vector3 = -dir
	var z_axis: Vector3 = x_axis.cross(y_axis)
	return Basis(x_axis, y_axis, z_axis)


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
