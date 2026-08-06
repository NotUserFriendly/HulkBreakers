extends GutTest

## taskblock-59 Pass C — **the Scale tool's own definition, as arithmetic.**
##
## The supervisor stated it: *"the handle perpendicular to the face grabbed affects only that face,
## moving it regardless of its opposite. The handles parallel to the face grow the mirrored way.
## Clicking a world X aligned face, and then dragging along Z, would grow the object in both +Z and
## -Z in the mirrored fashion."*
##
## Pure, so the rule is testable with no gizmo, no camera and no board.

## A part shaped like `wall`: straddling zero on X and Z, standing on its own base on Y. **The two
## anchorings in one fixture**, because that difference is exactly what the offset has to absorb.
const NATURAL := AABB(Vector3(-0.5, 0.0, -0.25), Vector3(1.0, 2.0, 0.5))


## The example from the definition, verbatim: an X-aligned face grabbed, a Z drag, mirrored growth.
func test_a_z_drag_on_an_x_face_grows_both_ways_and_does_not_move_it() -> void:
	var grown: Dictionary = GizmoDrag.grow(
		NATURAL, Vector3.ZERO, Vector3.ZERO, Gizmo.AXIS_Z, 1.0, 0.3, Gizmo.AXIS_X
	)

	gut.p("size %s offset %s" % [grown["size"], grown["offset"]])
	assert_almost_eq((grown["size"] as Vector3).z, 1.1, 0.0001, "0.5 + 0.3 both ways")
	assert_almost_eq((grown["offset"] as Vector3).z, 0.0, 0.0001, "mirrored growth moves nothing")
	assert_almost_eq(
		(grown["size"] as Vector3).x, NATURAL.size.x, 0.0001, "and no other axis changed"
	)


## The perpendicular half: the face you grabbed moves and its opposite does not, which is what the
## offset is for.
func test_a_y_drag_on_a_top_face_moves_that_face_alone() -> void:
	var grown: Dictionary = GizmoDrag.grow(
		NATURAL, Vector3.ZERO, Vector3.ZERO, Gizmo.AXIS_Y, 1.0, 0.4, Gizmo.AXIS_Y
	)

	gut.p("size %s offset %s" % [grown["size"], grown["offset"]])
	assert_almost_eq((grown["size"] as Vector3).y, 2.4, 0.0001, "2.0 + 0.4, one face only")
	# **Zero, and that is the finding.** `wall` authors its boxes with the base at y=0, so scaling
	# already grows it upward and leaves the base put — an offset here would lift it off its own
	# floor by half the drag, which is precisely what the first cut of this did.
	assert_almost_eq(
		(grown["offset"] as Vector3).y, 0.0, 0.0001, "the wall was lifted off its own floor"
	)
	assert_almost_eq(_low(NATURAL, grown, Gizmo.AXIS_Y), 0.0, 0.0001, "the base did not hold")


## **The spec sentence, reconciled.** *"A top face scales X and Y mirrored"* — a top face's
## perpendicular axis is Y, so its parallel pair is the grid's X and Y, which are the world's X and
## Z. Both mirror; the height does not.
func test_a_top_face_mirrors_the_two_grid_axes() -> void:
	for axis: int in [Gizmo.AXIS_X, Gizmo.AXIS_Z]:
		var grown: Dictionary = GizmoDrag.grow(
			NATURAL, Vector3.ZERO, Vector3.ZERO, axis, 1.0, 0.25, Gizmo.AXIS_Y
		)
		assert_almost_eq(
			(grown["size"] as Vector3)[axis],
			NATURAL.size[axis] + 0.5,
			0.0001,
			"axis %d did not mirror under a top face" % axis
		)
		var centre: float = _low(NATURAL, grown, axis) + (grown["size"] as Vector3)[axis] * 0.5
		assert_almost_eq(centre, 0.0, 0.0001, "axis %d moved off centre" % axis)


## Dragging the far face outward grows rather than shrinks — the handle's own sign is what says so.
func test_the_negative_face_grows_outward_too() -> void:
	var grown: Dictionary = GizmoDrag.grow(
		NATURAL, Vector3.ZERO, Vector3.ZERO, Gizmo.AXIS_Y, -1.0, -0.4, Gizmo.AXIS_Y
	)

	gut.p("size %s offset %s" % [grown["size"], grown["offset"]])
	assert_almost_eq((grown["size"] as Vector3).y, 2.4, 0.0001, "dragging the base down grows it")
	assert_almost_eq(
		_low(NATURAL, grown, Gizmo.AXIS_Y), -0.4, 0.0001, "the base is what should have moved"
	)
	assert_almost_eq(
		_low(NATURAL, grown, Gizmo.AXIS_Y) + 2.4, 2.0, 0.0001, "and the top should have held"
	)


## Snapped to the grid the whole editor is authored on, so a size is always reproducible.
func test_every_authored_size_is_snapped() -> void:
	var grown: Dictionary = GizmoDrag.grow(
		NATURAL, Vector3.ZERO, Vector3.ZERO, Gizmo.AXIS_Y, 1.0, 0.37, Gizmo.AXIS_Y
	)
	var size: Vector3 = grown["size"]
	gut.p("0.37 of drag became %s" % size)
	assert_almost_eq(size.y, GizmoDrag.snap(size.y), 0.00001, "an unsnapped size is unreproducible")


## *"An invalid drag is refused rather than clamped silently"* — `Gizmo.resized_box`'s own rule,
## applied to a placement. An author can tell a refusal from a laggy drag and cannot tell a clamp.
func test_a_drag_that_would_collapse_the_axis_is_refused() -> void:
	var grown: Dictionary = GizmoDrag.grow(
		NATURAL, Vector3.ZERO, Vector3.ZERO, Gizmo.AXIS_Z, 1.0, -9.0, Gizmo.AXIS_Z
	)

	assert_eq(
		grown["size"], Vector3.ZERO, "the placement was clamped to something nobody asked for"
	)
	assert_eq(grown["offset"], Vector3.ZERO)


## No struck face — a click that resolved off the ground plane rather than off geometry — mirrors,
## because there is no face to be perpendicular to.
func test_no_struck_face_mirrors() -> void:
	var grown: Dictionary = GizmoDrag.grow(
		NATURAL, Vector3.ZERO, Vector3.ZERO, Gizmo.AXIS_Y, 1.0, 0.5, -1
	)
	assert_almost_eq((grown["size"] as Vector3).y, 3.0, 0.0001, "2.0 + 0.5 both ways")
	assert_almost_eq(_low(NATURAL, grown, Gizmo.AXIS_Y), -0.5, 0.0001, "mirrored about the centre")


## The face a normal names, shared with `FacePlacement` rather than given a second epsilon.
func test_a_normal_names_the_axis_it_points_along() -> void:
	assert_eq(Gizmo.axis_of(Vector3.UP), Gizmo.AXIS_Y)
	assert_eq(Gizmo.axis_of(Vector3.DOWN), Gizmo.AXIS_Y, "a face is an axis, not a direction")
	assert_eq(Gizmo.axis_of(Vector3.RIGHT), Gizmo.AXIS_X)
	assert_eq(Gizmo.axis_of(Vector3.BACK), Gizmo.AXIS_Z)
	assert_eq(Gizmo.axis_of(Vector3.ZERO), -1, "nothing was struck")


## Where the low face of the result actually lands, worked out the way `PlacedVolume.boxes_for`
## does it — scale about the origin, then shift. **Read forward from the result rather than
## asserted against the offset**, because the offset is a means and the face position is the claim.
static func _low(natural: AABB, grown: Dictionary, axis: int) -> float:
	var size: Vector3 = grown["size"]
	var scale: float = size[axis] / natural.size[axis]
	return natural.position[axis] * scale + (grown["offset"] as Vector3)[axis]
