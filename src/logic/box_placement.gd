class_name BoxPlacement
extends RefCounted

## One box, fully placed in world space (docs/10: "render is hitbox"). The
## Node layer never computes this itself — it just spawns a BoxMesh sized
## `box.size` at `transform.translated_local(box.center)`.

var part: Part
var box: Box
## The owning PART's own composed transform (unit facing + board position +
## the socket chain down from the shell root) — box.center is still a local
## offset within it, not yet applied.
var transform: Transform3D


func _init(
	p_part: Part = null, p_box: Box = null, p_transform: Transform3D = Transform3D.IDENTITY
) -> void:
	part = p_part
	box = p_box
	transform = p_transform
