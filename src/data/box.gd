class_name Box
extends Resource

## A body-space volume: one or more of these per Part express its geometry
## (docs/02). Unit-local space: +X right, +Y up, +Z forward. Projection into
## a Region (rect/depth) is Phase 3 — this phase only needs the data shape so
## Part.volume can round-trip.

@export var center: Vector3 = Vector3.ZERO
@export var size: Vector3 = Vector3.ONE


func _init(p_center: Vector3 = Vector3.ZERO, p_size: Vector3 = Vector3.ONE) -> void:
	center = p_center
	size = p_size
