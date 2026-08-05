class_name GizmoDrag
extends RefCounted

## taskblock-57 Pass H: **screen delta → axis delta → snapped value, and nothing else.**
##
## The taskblock: *"Keep the drag math in logic. Screen delta → axis delta → snapped value is
## pure, so the gizmo is testable without a screen exactly as `EditorController` is. The scene
## reads and draws; it decides nothing."* This is that arithmetic, and it is the whole of what
## a drag means.
##
## ## The one thing the view must supply
##
## `axis_on_screen` is **the screen-space vector that one world unit along the axis covers**,
## at the gizmo's own position. Only a camera can answer that — `unproject_position(origin +
## axis)` minus `unproject_position(origin)` — so the view computes it and hands it over.
## Everything downstream is a dot product.
##
## **Why one world unit rather than a "pixels per unit" scalar.** A perspective camera
## foreshortens differently per axis and per position: dragging the up arrow on a distant
## object covers fewer pixels per unit than on a near one, and the X arrow seen almost end-on
## covers almost none. A single scalar cannot express that; a vector per axis can, and it falls
## out of the projection the view already does to draw the handle.
##
## ## Snapping is the point, not a tidy-up
##
## *"Snap to 0.1 — the precision authored maps were always intended to have."* So the snap is
## applied to the **resulting value**, never to the delta: snapping the delta lets a drag of
## 0.04 twice accumulate to 0.0 while the handle has visibly moved, and lets a value that
## started off-grid stay off-grid forever. Snapping the result means every value this function
## ever returns is a multiple of the step, which is the property the acceptance asks for.

## The authoring grid. **0.1 from the taskblock**, and expressed as a constant because the
## readout, the tests and the resize path all have to agree about it.
const SNAP := 0.1

## Below this, the axis is pointing so nearly at (or away from) the camera that a pixel of
## mouse movement means an unbounded number of world units. **Refused rather than clamped**: a
## drag that would teleport the value is not a small error to correct, it is a gesture with no
## meaning. In pixels, squared-length compared, so a handle whose whole world unit projects to
## under a pixel is out.
const MIN_AXIS_PIXELS := 1.0


## `value` rounded to the nearest `SNAP` multiple. **Every value the gizmo produces goes
## through here**, which is what makes "every value lands on a 0.1 multiple" true by
## construction rather than by each call site remembering.
##
## `snappedf` rather than hand-rolled rounding: 0.1 is not representable in binary, and
## `round(v / 0.1) * 0.1` produces 0.30000000000000004 for a value the author will read as 0.3.
static func snap(value: float) -> float:
	return snappedf(value, SNAP)


## How far along the axis, in world units, a mouse movement of `screen_delta` reaches.
##
## The scalar projection of the mouse movement onto the axis's own screen direction, divided by
## how many pixels one world unit covers — both of which `axis_on_screen` carries, so this is
## `dot / length_squared` and not two separate steps.
##
## **Zero for a degenerate axis**, see `MIN_AXIS_PIXELS`. Zero is the honest answer: the drag
## did not move along this axis, so the value does not change.
static func axis_delta(screen_delta: Vector2, axis_on_screen: Vector2) -> float:
	var pixels_squared: float = axis_on_screen.length_squared()
	if pixels_squared < MIN_AXIS_PIXELS:
		return 0.0
	return screen_delta.dot(axis_on_screen) / pixels_squared


## The value a drag lands on: where it started, plus how far the drag reached along the axis,
## snapped.
##
## **Measured from the drag's own start, never from the last frame's answer.** Accumulating
## per-frame deltas makes the result depend on how many frames the drag took, which is a value
## that differs between a fast machine and a slow one for the same gesture — and it lets
## rounding error walk. The caller holds the value the handle was grabbed at and the screen
## position it was grabbed at, and this is a pure function of both.
static func value_after(
	start_value: float, screen_delta: Vector2, axis_on_screen: Vector2
) -> float:
	return snap(start_value + axis_delta(screen_delta, axis_on_screen))
