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
##
## tb32 Pass A retires the GDScript loop that called this against one
## `focal_unit` at a time (`BoardView.update_wall_legibility`, superseded
## by the per-fragment cutout shader) but Pass B's own friendly-ghost fade
## reuses this exact function unchanged (same screen-space-and-nearer
## test, just "is this friendly within R of, and nearer than, the active
## unit" instead of "is this wall...") — kept here rather than deleted.
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


## tb32 Pass A: how many screen pixels a `tiles`-wide circle spans at
## `depth` from the camera — pure trig mirroring `Camera3D`'s own
## perspective projection, so the wall-cutout shader's per-unit radius
## (fed as a uniform every frame, `BoardView.update_wall_cutout`) can be
## computed and unit-tested without a real camera node; the shader itself
## only does the per-fragment discard.
##
## `fov_deg` is `Camera3D.fov`, which this project's own camera treats as
## VERTICAL fov (`CameraOrbitState.CAMERA_FOV_DEG`'s own doc comment) — so
## `viewport_height_px` is the matching dimension, not width. Because the
## radius is tiles-at-THAT-unit's-own-depth, zoom falls out for free: zoom
## out (greater depth for the same tile count) shrinks the pixel radius
## automatically, no separate distance logic needed.
static func pixel_radius_for_tiles(
	tiles: float, depth: float, fov_deg: float, viewport_height_px: float
) -> float:
	if depth <= 0.0:
		return 0.0
	var world_radius: float = tiles * UnitGeometry.CELL_SIZE
	return world_radius / (2.0 * depth * tan(deg_to_rad(fov_deg) * 0.5)) * viewport_height_px
