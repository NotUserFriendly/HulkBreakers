class_name WallLegibility
extends RefCounted

## tb31 Pass C: "walls must not block the player's read of the action
## behind them." Pure geometry — camera/focal-point/wall positions in,
## a fade decision out, zero SceneTree dependency (the view layer reads
## the real `Camera3D.global_position` and hands it in as a plain
## `Vector3`, never the node itself, so this stays headless-testable
## the way `CameraRig`'s own solver math already is elsewhere).
##
## A wall "occludes" the focal point when it sits geometrically BETWEEN
## the camera and the focal point (nearer to camera along the view ray,
## not past it) AND within `radius` of that ray — a wall off to the side
## that merely happens to share a rough direction must not fade; only one
## actually standing in the sightline should.


## True if a wall at `wall_position` should fade so a player can still
## read `focal_position` behind it, as seen from `camera_position`.
static func occludes(
	camera_position: Vector3, focal_position: Vector3, wall_position: Vector3, radius: float
) -> bool:
	var to_focal: Vector3 = focal_position - camera_position
	var focal_distance: float = to_focal.length()
	if focal_distance <= 0.0001:
		return false
	var view_dir: Vector3 = to_focal / focal_distance
	var to_wall: Vector3 = wall_position - camera_position
	var along: float = to_wall.dot(view_dir)
	# At or past the focal point itself (along >= focal_distance) isn't
	# "in the way" — it's beside or behind the thing the player is trying
	# to read. Behind the camera (along <= 0) obviously isn't either.
	if along <= 0.0 or along >= focal_distance:
		return false
	var closest_point_on_ray: Vector3 = camera_position + view_dir * along
	return wall_position.distance_to(closest_point_on_ray) <= radius
