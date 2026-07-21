class_name WallLegibility
extends RefCounted

## tb31 Pass C: "walls must not block the player's read of the action
## behind them." Pure geometry — screen positions/depths in, a fade
## decision out, zero SceneTree dependency (the view layer reads the real
## `Camera3D.unproject_position()`/`global_position` and hands in plain
## `Vector2`/`float`s, never the node itself, so this stays
## headless-testable the way `CameraRig`'s own solver math already is
## elsewhere).
##
## SCREEN-space on purpose, not world-space: the tactical camera sits
## well above and back from the board (`CameraOrbitState.DEFAULT_PITCH`/
## `DEFAULT_ZOOM`), so a straight 3D line from camera to a ground-level
## unit spends almost its whole length far above wall height — "is this
## wall within N world units of that 3D ray" almost never fires in
## practice, regardless of N, for any wall more than a cell or two from
## the unit. Screen-space asks the question a player would actually
## answer by eye instead: does the wall's own projected position sit
## close to the unit's on screen, AND is it nearer to the camera (in
## front of, not behind, the thing it would be hiding)?


## True if a wall projecting to `wall_screen_position` (at `wall_depth`
## from the camera) should fade so a player can still read a focal point
## projecting to `focal_screen_position` (at `focal_depth`).
static func occludes_on_screen(
	wall_screen_position: Vector2,
	wall_depth: float,
	focal_screen_position: Vector2,
	focal_depth: float,
	screen_radius: float
) -> bool:
	if wall_depth >= focal_depth:
		return false
	return wall_screen_position.distance_to(focal_screen_position) <= screen_radius
