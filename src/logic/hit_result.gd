class_name HitResult
extends RefCounted

## docs/09 taskblock06 Pass A: what casting a ray at the world actually hit.
## Built today by projecting into the existing 2D shot plane and
## reconstructing the 3D point from a Region's own rect/depth — tomorrow
## this becomes a real PhysicsServer `intersect_ray` result and no consumer
## of HitResult changes, because the shape of the answer is already right.

var part: Part
var point: Vector3
var normal: Vector3
var distance: float
## The Unit or field-object Part this hit's whole body belongs to
## (Region.body) — kept because AimResult/aim_view still need "who did the
## reticle land on," never used to affect resolution.
var body: Variant = null


func _init(
	p_part: Part = null,
	p_point: Vector3 = Vector3.ZERO,
	p_normal: Vector3 = Vector3.ZERO,
	p_distance: float = 0.0,
	p_body: Variant = null
) -> void:
	part = p_part
	point = p_point
	normal = p_normal
	distance = p_distance
	body = p_body
