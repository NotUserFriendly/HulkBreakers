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
## taskblock-52 Pass B: non-null only for a JOINT placement — the same
## `part` / `socket` distinction `Region` already carries (region.gd), mirrored
## here so a ray march can tell a connection from ordinary geometry without a
## second vocabulary. `part` still points at the socket's `joint_handle()`
## placeholder, exactly as `BodyProjector._project_joint` sets it, so anything
## filtering "every placement belonging to part X" never picks up a joint by
## accident. Null (the default) is an ordinary part placement, which is every
## placement anything built before taskblock-52 produces.
var socket: Socket = null


func _init(
	p_part: Part = null,
	p_box: Box = null,
	p_transform: Transform3D = Transform3D.IDENTITY,
	p_socket: Socket = null
) -> void:
	part = p_part
	box = p_box
	transform = p_transform
	socket = p_socket
