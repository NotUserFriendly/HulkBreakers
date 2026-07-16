class_name AimView
extends Node3D

## docs/10 Phase 12.3, "the signature screen": draws exactly what
## AimController.resolve() says. Pure presentation — every number (which
## body is being read, what the reticle resolves to, how many scatter
## rings and how wide) comes from the controller; this Node only spawns
## meshes and sets label text from it (docs/08's three laws).
##
## Ghosting nearer layers and highlighting the read layer in 3D (the full
## docs/10 visual) is deferred — like ragdolls and the CRT shader pass, a
## later polish layer, not part of Phase 12.3's graded acceptance (all of
## which is headless, on AimController itself). The rings + READING/
## RESOLVES readout below are the load-bearing, functional core.

## A targeting overlay, deliberately distinct from any WorldPalette material
## or team color so a ring never blends into armor or a unit's own team rim.
const RING_COLOR := Color(0.95, 0.55, 0.15)
## runNotes.md: "it also needs to be slightly transparent, so what is being
## targeted is clearer" — opaque rings used to fully hide whatever body they
## sat in front of.
const RING_ALPHA := 0.55
## docs/10 taskblock03 F2: "same geometry the tracer will use, so what
## you're shown is what will fire" — same TracerGeometry as
## ResolutionPlayer's own tracer, same muzzle height, but translucent and
## dim: a preview, never mistaken for an actual hit.
const TARGETING_LINE_THICKNESS := ResolutionPlayer.TRACER_THICKNESS
const TARGETING_LINE_COLOR := Color(0.95, 0.55, 0.15, 0.35)

var tactics: TacticsController
var readout: RichTextLabel

var _rings: Node3D
var _targeting_line: MeshInstance3D


func _init() -> void:
	_rings = Node3D.new()
	add_child(_rings)
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
	_clear_rings()
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
	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	if weapon == null:
		readout.text = "[UNARMED]"
		return

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + tactics.reticle_offset
	var result: AimResult = AimController.resolve(plane, aim_point, tactics.layer_index, weapon)
	var world_point: Vector3 = _world_point(shooter, target, aim_point)

	_draw_rings(world_point, result.rings)
	# docs/10 taskblock03 F2 / runNotes.md: "a line from the shooter's
	# muzzle to the reticle's world point... if a pistol is what's shooting,
	# the targeting line should come from the pistol," not a generic
	# torso-height point.
	_draw_targeting_line(_muzzle_point(shooter, weapon), world_point)
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


## `aim_point` is in shot-plane coordinates (x lateral, y vertical) — the
## world point it corresponds to. AimPlaneGeometry (logic/) owns the actual
## plane math now, shared with TacticsController's own cursor->aim_point
## raycast (runNotes.md: the two must agree exactly, or the reticle drawn
## here would visibly disagree with where the cursor put it).
func _world_point(shooter: Unit, target: Unit, aim_point: Vector2) -> Vector3:
	return AimPlaneGeometry.world_point(shooter.cell, target.cell, aim_point)


## runNotes.md: "if a pistol is what's shooting, then the targeting line
## should come from the pistol" — the weapon's own living box center, in
## the exact placement space UnitView renders from (unit facing + board
## position + socket chain), not a generic torso-height point. Falls back
## to the old torso-height point only if the weapon somehow has no
## placement at all (defensive: an operable weapon always has one).
func _muzzle_point(shooter: Unit, weapon: Part) -> Vector3:
	for placement: BoxPlacement in UnitGeometry.placements(shooter):
		if placement.part == weapon:
			return placement.transform.translated_local(placement.box.center).origin
	return (
		Vector3(shooter.cell.x, ResolutionPlayer.TRACER_MUZZLE_HEIGHT, shooter.cell.y)
		* UnitGeometry.CELL_SIZE
	)


func _draw_rings(world_center: Vector3, rings: Array[Ring]) -> void:
	for i in range(rings.size()):
		var ring: Ring = rings[i]
		var inner: float = 0.0 if i == 0 else rings[i - 1].radius
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(inner, 0.001)
		torus.outer_radius = maxf(ring.radius, inner + 0.01)
		torus.material = WorldPalette.translucent_material(
			Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_ALPHA)
		)
		var instance := MeshInstance3D.new()
		instance.mesh = torus
		instance.position = world_center
		instance.rotation.x = PI / 2.0  # lay flat, hole facing up
		_rings.add_child(instance)


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


func _clear_rings() -> void:
	for child: Node in _rings.get_children():
		_rings.remove_child(child)
		child.queue_free()
