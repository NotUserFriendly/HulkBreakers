class_name Box
extends Resource

## A body-space volume: one or more of these per Part express its geometry
## (docs/02). PART-local space (Phase 12.0): +X right, +Y up, +Z forward,
## relative to the part's own origin — not the unit's. BodyProjector composes
## each part's Socket.transform chain from the shell root before projecting,
## so a part's boxes only need to describe its own shape, never where it
## sits on the body.

@export var center: Vector3 = Vector3.ZERO
@export var size: Vector3 = Vector3.ONE


func _init(p_center: Vector3 = Vector3.ZERO, p_size: Vector3 = Vector3.ONE) -> void:
	center = p_center
	size = p_size
