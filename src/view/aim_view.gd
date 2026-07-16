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

var tactics: TacticsController
var readout: RichTextLabel

var _rings: Node3D


func _init() -> void:
	_rings = Node3D.new()
	add_child(_rings)


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
	if tactics == null or tactics.aiming_at == null:
		readout.text = ""
		return

	var shooter: Unit = tactics.selection.selected_unit
	var target: Unit = tactics.aiming_at
	var weapon: Part = DeepStrike.find_operable_weapon(shooter)
	if weapon == null:
		readout.text = "[UNARMED]"
		return

	var plane: Array[Region] = tactics.aim_plane()
	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + tactics.reticle_offset
	var result: AimResult = AimController.resolve(plane, aim_point, tactics.layer_index, weapon)

	_draw_rings(shooter, target, aim_point, result.rings)
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


## `aim_point` is in shot-plane coordinates (x lateral, y vertical); rings
## sit on the target's cell, nudged by that same offset in world space
## (docs/10 doesn't pin down the exact 3D placement — a flagged
## simplification, not a design decision).
func _draw_rings(shooter: Unit, target: Unit, aim_point: Vector2, rings: Array[Ring]) -> void:
	var direction: Vector2 = Vector2(target.cell - shooter.cell).normalized()
	var perp := Vector2(-direction.y, direction.x)
	var world_center: Vector3 = (
		Vector3(target.cell.x, 0.0, target.cell.y) * UnitGeometry.CELL_SIZE
		+ Vector3(perp.x, 0.0, perp.y) * aim_point.x
		+ Vector3(0.0, aim_point.y, 0.0)
	)

	for i in range(rings.size()):
		var ring: Ring = rings[i]
		var inner: float = 0.0 if i == 0 else rings[i - 1].radius
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(inner, 0.001)
		torus.outer_radius = maxf(ring.radius, inner + 0.01)
		# WARN, not HIGHLIGHT: rings must read as a targeting overlay distinct
		# from armor color bands, which already use HIGHLIGHT for steel-tier DT.
		torus.material = HulkTheme.flat_material(HulkTheme.WARN)
		var instance := MeshInstance3D.new()
		instance.mesh = torus
		instance.position = world_center
		instance.rotation.x = PI / 2.0  # lay flat, hole facing up
		_rings.add_child(instance)


func _clear_rings() -> void:
	for child: Node in _rings.get_children():
		_rings.remove_child(child)
		child.queue_free()
