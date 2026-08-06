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


## **How a Scale drag changes a placement's size and offset.** taskblock-59 Pass C.
##
## The tool's definition, as the supervisor stated it: *"the handle perpendicular to the face
## grabbed affects only that face, moving it regardless of its opposite. The handles parallel to the
## face grow the mirrored way. Clicking a world X aligned face, and then dragging along Z, would
## grow the object in both +Z and -Z in the mirrored fashion."*
##
## So `struck_axis` — the axis the grabbed face faces — decides which of two behaviours a drag is,
## and the dragged axis alone never does:
##
## | drag axis vs struck face | extent | what holds still |
## |---|---|---|
## | perpendicular (same axis) | `+amount` | the opposite face |
## | parallel (a different axis) | `+2*amount` | the centre |
##
## **The offset is computed, not assumed, and that is the whole subtlety here.**
## `PlacedVolume.boxes_for` scales every box about the **part's origin**, so where a face lands
## after a scale depends on where the content authored its boxes — `wall` has its base at y=0 and so
## already grows upward on its own, while its X boxes straddle zero and already mirror. A tool that
## added a fixed `amount/2` on top of that would double-count exactly the axes the content already
## anchored, which is what the first cut of this did: a top-face drag lifted the wall off its own
## floor by half the drag.
##
## So this works out **where the faces should be** and solves for the offset that puts them there:
## `offset = desired_low - (scale x natural_low)`. Content-independent by construction, and the test
## that catches a regression is the one that reads the base back rather than re-deriving it.
##
## `natural` is the part's own bounds in part-local space (`PlacedVolume.natural_bounds`). A
## `struck_axis` of -1 means the click never resolved off geometry, so everything mirrors — the
## honest default, because there is no face to be perpendicular to.
##
## Snapped on the way out, so an authored size is always a number an author can reproduce. Returns
## `{size, offset}`; a drag that would collapse the axis returns both unchanged, which is
## `Gizmo.resized_box`'s own rule — refuse rather than clamp, because an author can tell a refusal
## from a laggy drag and cannot tell a clamp from one.
static func grow(
	natural: AABB,
	size: Vector3,
	offset: Vector3,
	axis: int,
	sign_of: float,
	amount: float,
	struck_axis: int
) -> Dictionary:
	if natural.size[axis] <= 0.0:
		return {"size": size, "offset": offset}
	var old_size: Vector3 = size if not size.is_zero_approx() else natural.size
	var perpendicular: bool = axis == struck_axis
	# The handle's own sign is what makes dragging the far face outward grow rather than shrink:
	# `amount` is measured along the axis, and that face moves the other way.
	var along: float = amount * sign_of
	var extent: float = snap(old_size[axis] + (along if perpendicular else along * 2.0))
	if extent <= 0.0:
		return {"size": size, "offset": offset}

	# Where the faces are right now, as drawn.
	var old_scale: float = old_size[axis] / natural.size[axis]
	var low: float = natural.position[axis] * old_scale + offset[axis]
	var high: float = low + old_size[axis]

	# Where they should be after the drag.
	var wanted_low: float = low
	if perpendicular and sign_of < 0.0:
		wanted_low = high - extent
	elif not perpendicular:
		wanted_low = (low + high) * 0.5 - extent * 0.5

	var grown: Vector3 = old_size
	grown[axis] = extent
	var moved: Vector3 = offset
	moved[axis] = snap(wanted_low - natural.position[axis] * (extent / natural.size[axis]))
	return {"size": grown, "offset": moved}
