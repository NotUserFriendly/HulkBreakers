class_name CameraFramingModule
extends ViewModule

## taskblock-56 Pass E: **point the camera at what was just loaded.**
##
## A section or map load leaves the camera wherever the last bout left it, which for an authoring
## surface means loading a board and looking at empty space beside it. `CameraRig` already solves
## framing for a set of bodies (`ease_to_framing`); this is the same solve with different input —
## the bounds of the placed content instead of a shooter and a target.
##
## ## Why the solve is here and not in `CameraRig`
##
## `CameraOrbitState` owns the trigonometry and is headless-testable; `CameraRig` owns the tween and
## the nodes. What was missing is neither: it is **which bounds to frame**, and that is a question
## about the board's content, which is this module's business. `frame_bounds` below computes a pan
## and a zoom and hands them to the rig's existing `ease_to` path — there is no second easing
## implementation, exactly as `ease_to_framing` is not one.
##
## ## The zoom solve, stated so nobody has to re-derive it
##
## The camera sits `zoom` away along its own axis with a vertical FOV of
## `CameraOrbitState.CAMERA_FOV_DEG`. A sphere of radius `r` fits when
## `zoom >= r / sin(fov / 2)`. Framing an AABB means framing its bounding sphere, so `r` is half the
## box's diagonal — which over-frames a long thin board slightly, and that is the right way to be
## wrong: too much margin shows content, too little cuts it off.
##
## `MARGIN` then pads it, and the result is clamped to the rig's own zoom range. **A board bigger
## than `MAX_ZOOM` can show cannot be framed**, and the clamp says so by simply not zooming out
## further rather than pretending — the test asserts containment only within that range.

## A little slack past the exact fit, so content is not flush against the frame edge. Flagged and
## tunable, picked to look deliberate rather than derived from anything.
const MARGIN := 1.15


func module_id() -> StringName:
	return &"camera_framing"


## Frames the loaded board on every battle load, which is exactly the "leaves the camera wherever
## the last bout left it" complaint.
func rebind() -> void:
	frame_loaded_content()


## Frames whatever the current grid actually has placed. A no-op with nothing to frame — an empty
## board has no bounds, and moving the camera to the origin of nothing is worse than leaving it.
func frame_loaded_content() -> bool:
	if context == null or context.battle == null or context.battle.combat_state == null:
		return false
	var bounds: Variant = content_bounds(context.battle.combat_state.grid)
	if bounds == null:
		return false
	return frame_bounds(bounds as AABB)


## Points the rig at `bounds`. Returns whether it actually moved the camera.
func frame_bounds(bounds: AABB) -> bool:
	if context == null or context.battle == null or context.battle.camera_rig == null:
		return false
	context.battle.camera_rig.frame_bounds(bounds, MARGIN)
	return true


## The world-space bounds of everything placed on `grid` — every surface's own real box and every
## blocker's, through the same `UnitGeometry.assembly_placements` call `BoardView` draws from and
## `RayCaster` marches. **Not a second formula**: a bounds derived independently of what is drawn
## would eventually frame something the board does not show.
##
## Null when nothing is placed at all.
static func content_bounds(grid: Grid) -> Variant:
	var bounds: Variant = null
	for surface: Surface in grid.placements():
		bounds = _absorb(
			bounds,
			UnitGeometry.assembly_placements(
				surface.part, surface.cell, surface.facing, null, surface.height
			)
		)
	for cell: Vector2i in grid.blockers:
		var part: Part = grid.blocker_part_at(cell)
		if part == null:
			continue
		bounds = _absorb(
			bounds,
			UnitGeometry.assembly_placements(
				part, cell, 0.0, null, UnitGeometry.blocker_height_for_cell(cell, grid)
			)
		)
	return bounds


static func _absorb(bounds: Variant, placements: Array[BoxPlacement]) -> Variant:
	var out: Variant = bounds
	for placement: BoxPlacement in placements:
		var centre: Vector3 = placement.transform * placement.box.center
		var box := AABB(centre - placement.box.size * 0.5, placement.box.size)
		out = box if out == null else (out as AABB).merge(box)
	return out
