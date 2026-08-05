extends GutTest

## taskblock-57 Pass H — **the gizmo's arithmetic and its state, with no screen anywhere.**
##
## *"Keep the drag math in logic. Screen delta → axis delta → snapped value is pure, so the gizmo is
## testable without a screen exactly as `EditorController` is."* This file is the proof of that
## sentence: every assertion below runs against `RefCounted`s, and the module that draws the handles
## is tested separately for the two things only a view can answer.
##
## The taskblock's own stated tests, and where each lands:
##
## - *"a drag of N pixels along an axis produces the correctly snapped value, headless"* — here.
## - *"every value lands on a 0.1 multiple"* — here, swept rather than sampled.
## - *"a second click on a claim swaps handle sets and a click elsewhere deselects"* — here.
## - *"the gizmo never changes what is selected"* — here (this class has no way to) and in the
##   module's own file (a real drag changes a value and nothing else).
## - *"resizing a claim produces a valid volume and an invalid drag is refused rather than clamped
##   silently"* — here.

## One world unit along the axis covers 100 px on screen, pointing right. A round number so the
## expected values below are readable rather than derived.
const HUNDRED_PX_RIGHT := Vector2(100.0, 0.0)
## The same, pointing up the screen — screen y grows downward, so "up" is negative.
const HUNDRED_PX_UP := Vector2(0.0, -100.0)

# ---------------------------------------------------------------- the drag arithmetic


## **THE STATED TEST**: *"a drag of N pixels along an axis produces the correctly snapped value."*
## 100 px along an axis that covers 100 px per world unit is 1.0.
func test_a_drag_along_the_axis_converts_pixels_to_world_units() -> void:
	assert_almost_eq(GizmoDrag.axis_delta(Vector2(100.0, 0.0), HUNDRED_PX_RIGHT), 1.0, 0.0001)
	assert_almost_eq(GizmoDrag.axis_delta(Vector2(50.0, 0.0), HUNDRED_PX_RIGHT), 0.5, 0.0001)
	assert_almost_eq(GizmoDrag.axis_delta(Vector2(-30.0, 0.0), HUNDRED_PX_RIGHT), -0.3, 0.0001)


## Movement across the axis contributes nothing — the drag is the projection onto the axis, which is
## what makes an arrow feel like an arrow rather than like a free move.
func test_movement_perpendicular_to_the_axis_moves_nothing() -> void:
	assert_almost_eq(GizmoDrag.axis_delta(Vector2(0.0, 90.0), HUNDRED_PX_RIGHT), 0.0, 0.0001)
	assert_almost_eq(
		GizmoDrag.axis_delta(Vector2(60.0, 90.0), HUNDRED_PX_RIGHT),
		0.6,
		0.0001,
		"only the component along the axis counts"
	)


## **THE ACCEPTANCE, as arithmetic**: *"a height is authored by dragging an arrow to 0.3."* A 30 px
## drag up an axis covering 100 px per unit, from zero, is 0.3 exactly.
func test_dragging_the_up_arrow_thirty_pixels_produces_zero_point_three() -> void:
	var value: float = GizmoDrag.value_after(0.0, Vector2(0.0, -30.0), HUNDRED_PX_UP)
	gut.p("30 px up -> %.4f" % value)
	assert_almost_eq(value, 0.3, 0.0001)


## **THE STATED TEST**: *"every value lands on a 0.1 multiple."* Swept across a range of pixel
## deltas rather than sampled at a few, because the failure this guards against is a rounding error
## that only shows at particular magnitudes.
func test_every_value_a_drag_produces_lands_on_the_grid() -> void:
	var off_grid: Array[float] = []
	for pixels: int in range(-250, 251):
		var value: float = GizmoDrag.value_after(0.0, Vector2(0.0, float(-pixels)), HUNDRED_PX_UP)
		# Multiplied up and rounded rather than compared with `fmod`: 0.1 is not representable in
		# binary, so `fmod(0.3, 0.1)` is 0.0999... and would fail every value it was handed.
		if absf(value * 10.0 - roundf(value * 10.0)) > 0.0001:
			off_grid.append(value)
	gut.p("swept 501 drags; off-grid: %d" % off_grid.size())
	# `str(off_grid)`, not `% off_grid`: `%` treats an Array as the argument LIST, so an empty one
	# is "not enough arguments for format string" — an engine error on the run that passes, which
	# GUT counts as a failure. The same shape as `%v` on a Rect2, one container over.
	assert_eq(
		off_grid.size(), 0, "a drag produced a value the grid cannot express: %s" % str(off_grid)
	)


## And a value that starts off-grid is pulled onto it rather than kept off it forever, which is why
## the snap is applied to the result and not to the delta.
func test_a_value_that_started_off_grid_is_snapped_onto_it() -> void:
	assert_almost_eq(GizmoDrag.value_after(0.37, Vector2.ZERO, HUNDRED_PX_RIGHT), 0.4, 0.0001)


## **An axis pointing at the camera is refused, not scaled to infinity.** One world unit covering
## under a pixel means a pixel of mouse movement is an unbounded number of units, and a drag that
## teleports the value is a gesture with no meaning.
func test_an_axis_pointing_at_the_camera_moves_nothing() -> void:
	assert_almost_eq(GizmoDrag.axis_delta(Vector2(500.0, 0.0), Vector2(0.2, 0.0)), 0.0, 0.0001)
	assert_almost_eq(GizmoDrag.axis_delta(Vector2(500.0, 0.0), Vector2.ZERO), 0.0, 0.0001)


## The drag is a pure function of where it started and where the pointer is — never an accumulation,
## which would make the answer depend on how many frames the gesture took.
func test_a_drag_is_measured_from_its_own_start_not_from_the_last_frame() -> void:
	var gizmo := Gizmo.new()
	gizmo.focus_placement(Vector2i(1, 1))
	gizmo.begin_drag(Gizmo.AXIS_Y, 1.0, 0.0, Vector2(500.0, 500.0))

	# Three frames of a single continuous 30 px drag, reported at three intermediate points.
	assert_almost_eq(gizmo.value_at(Vector2(500.0, 490.0), HUNDRED_PX_UP), 0.1, 0.0001)
	assert_almost_eq(gizmo.value_at(Vector2(500.0, 480.0), HUNDRED_PX_UP), 0.2, 0.0001)
	assert_almost_eq(
		gizmo.value_at(Vector2(500.0, 470.0), HUNDRED_PX_UP),
		0.3,
		0.0001,
		"the value must be the total gesture, not the sum of the reported steps"
	)


func test_polling_the_value_while_nothing_is_dragged_returns_the_start_value() -> void:
	var gizmo := Gizmo.new()
	assert_almost_eq(gizmo.value_at(Vector2(900.0, 100.0), HUNDRED_PX_UP), 0.0, 0.0001)


# ---------------------------------------------------------------- focus, and the two handle sets


## **THE STATED TEST**, first half: *"a second click on a claim swaps handle sets."*
func test_a_second_click_on_the_same_claim_swaps_to_the_resize_handles() -> void:
	var gizmo := Gizmo.new()

	gizmo.focus_claim(2)
	assert_eq(gizmo.handles, Gizmo.Handles.TRANSLATE, "the first click gives translate arrows")
	gizmo.focus_claim(2)
	assert_eq(gizmo.handles, Gizmo.Handles.RESIZE, "the second swaps to resize handles")
	gizmo.focus_claim(2)
	assert_eq(gizmo.handles, Gizmo.Handles.TRANSLATE, "and it toggles rather than sticking")


## A different claim starts over. Arriving at a new subject already in resize mode is a state nobody
## asked for, and the first drag on it would be a surprise.
func test_clicking_a_different_claim_starts_that_one_at_translate() -> void:
	var gizmo := Gizmo.new()
	gizmo.focus_claim(2)
	gizmo.focus_claim(2)
	assert_eq(gizmo.handles, Gizmo.Handles.RESIZE, "sanity: claim 2 is in resize mode")

	gizmo.focus_claim(5)

	assert_eq(gizmo.claim_index, 5)
	assert_eq(gizmo.handles, Gizmo.Handles.TRANSLATE)


## **THE STATED TEST**, second half: *"a click elsewhere deselects."*
func test_a_click_on_nothing_clears_the_gizmo() -> void:
	var gizmo := Gizmo.new()
	gizmo.focus_claim(1)
	assert_true(gizmo.has_subject())

	gizmo.clear()

	assert_false(gizmo.has_subject())
	assert_eq(gizmo.subject, Gizmo.SUBJECT_NONE)
	assert_eq(gizmo.claim_index, -1)


## A placement has one draggable value and therefore one handle set — there is no second click that
## turns a height into something else.
func test_a_placement_always_arrives_at_the_translate_arrows() -> void:
	var gizmo := Gizmo.new()
	gizmo.focus_placement(Vector2i(3, 4))
	gizmo.focus_placement(Vector2i(3, 4))
	assert_eq(gizmo.handles, Gizmo.Handles.TRANSLATE)
	assert_eq(gizmo.cell, Vector2i(3, 4))


## Focusing anything cancels a drag in progress. A handle grabbed on one subject and released over
## another would otherwise write the second subject's value from the first one's gesture.
func test_focusing_something_else_cancels_a_drag_in_progress() -> void:
	var gizmo := Gizmo.new()
	gizmo.focus_placement(Vector2i(1, 1))
	gizmo.begin_drag(Gizmo.AXIS_Y, 1.0, 0.5, Vector2.ZERO)
	assert_true(gizmo.is_dragging())

	gizmo.focus_claim(0)

	assert_false(gizmo.is_dragging(), "a drag survived the subject changing under it")


## **THE STATED TEST**: *"the gizmo never changes what is selected."* Asserted structurally,
## because the strongest form of "it cannot" is that there is nothing to call: this class has no
## reference to a selection, a controller or a battle — its surface is the handles and one drag.
func test_the_gizmo_holds_no_selection_of_its_own() -> void:
	var gizmo := Gizmo.new()
	var names: Array[String] = []
	for entry: Dictionary in gizmo.get_property_list():
		names.append(entry["name"] as String)
	gut.p("gizmo state: %s" % ", ".join(names.filter(func(n: String) -> bool: return "." not in n)))
	for forbidden: String in ["selection", "state", "battle", "units", "selected_unit"]:
		assert_false(
			names.has(forbidden),
			"the gizmo grew a '%s' -- that is the second selection system starting" % forbidden
		)


# ---------------------------------------------------------------- the handles are boxes


## *"`PartPicker.hit` and `UnitPicker.hit` are analytic ray-vs-box... gizmo handles are boxes —
## the same primitive, not a new one."* A ray down the +X arm hits the X handle and nothing else.
func test_a_ray_along_an_arm_hits_that_arms_handle() -> void:
	var handles: Array[Dictionary] = Gizmo.translate_handles(Vector3.ZERO)
	assert_eq(handles.size(), 3, "three arrows, one per axis")

	var struck: Dictionary = Gizmo.hit(handles, Vector3(10.0, 0.0, 0.0), Vector3.LEFT)

	assert_false(struck.is_empty(), "a ray down the X arm hit nothing")
	assert_eq(struck["axis"], Gizmo.AXIS_X)


func test_a_ray_into_empty_space_hits_no_handle() -> void:
	var handles: Array[Dictionary] = Gizmo.translate_handles(Vector3.ZERO)
	assert_true(Gizmo.hit(handles, Vector3(10.0, 40.0, 10.0), Vector3.UP).is_empty())


## **Six resize handles, one per face**, because dragging the top up and the bottom down are
## different edits with the same axis and the same direction.
func test_the_resize_set_offers_one_handle_per_face() -> void:
	var volume := AABB(Vector3(0.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0))
	var handles: Array[Dictionary] = Gizmo.resize_handles(volume)
	assert_eq(handles.size(), 6)

	var struck: Dictionary = Gizmo.hit(handles, Vector3(1.0, 10.0, 1.0), Vector3.DOWN)
	assert_false(struck.is_empty(), "a ray straight down must hit the top face's handle")
	assert_eq(struck["axis"], Gizmo.AXIS_Y)
	assert_almost_eq(struck["sign"] as float, 1.0, 0.0001, "the top face, not the bottom")


# ---------------------------------------------------------------- resizing a claim


## **THE STATED TEST**, first half: *"resizing a claim produces a valid volume."* The dragged face
## moves by the amount; the opposite face does not move at all.
func test_resizing_moves_the_dragged_face_and_leaves_the_opposite_one() -> void:
	var box := Box.new(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))

	var grown: Box = Gizmo.resized_box(box, Gizmo.AXIS_Y, 1.0, 0.4)

	assert_not_null(grown, "a legal drag was refused")
	assert_almost_eq(grown.size.y, 2.4, 0.0001, "the extent grew by the drag")
	assert_almost_eq(grown.center.y, 1.2, 0.0001, "so the centre moved half as far")
	# The bottom face is the invariant: centre minus half the extent, before and after.
	assert_almost_eq(
		grown.center.y - grown.size.y * 0.5,
		box.center.y - box.size.y * 0.5,
		0.0001,
		"the face nobody dragged moved"
	)


## Dragging the negative face outward grows the box the other way, which is the whole reason there
## are six handles rather than three.
func test_dragging_the_negative_face_grows_the_box_downward() -> void:
	var box := Box.new(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))

	var grown: Box = Gizmo.resized_box(box, Gizmo.AXIS_Y, -1.0, -0.5)

	assert_almost_eq(grown.size.y, 2.5, 0.0001)
	assert_almost_eq(
		grown.center.y + grown.size.y * 0.5,
		box.center.y + box.size.y * 0.5,
		0.0001,
		"the top face must not move when the bottom is dragged"
	)


## **THE STATED TEST**, second half: *"an invalid drag is refused rather than clamped silently."*
## Null, not a minimum-size box: the face stops following the pointer, which is unambiguous, where a
## clamp is indistinguishable from a laggy drag.
func test_a_resize_that_would_collapse_the_volume_is_refused() -> void:
	var box := Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))

	assert_null(Gizmo.resized_box(box, Gizmo.AXIS_Y, 1.0, -1.0), "a zero-thickness claim")
	assert_null(Gizmo.resized_box(box, Gizmo.AXIS_Y, 1.0, -2.0), "an inverted one")
	assert_not_null(
		Gizmo.resized_box(box, Gizmo.AXIS_Y, 1.0, -0.9),
		"one snap step thick is the smallest volume the grid can express, and is legal"
	)


## Every resized extent is on the grid too — the snap is not something the height path has and the
## claim path lacks.
func test_a_resized_extent_lands_on_the_grid() -> void:
	var box := Box.new(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
	var grown: Box = Gizmo.resized_box(box, Gizmo.AXIS_X, 1.0, 0.4237)
	assert_almost_eq(grown.size.x, 1.4, 0.0001)


## Translating moves the whole box and changes no extent.
func test_translating_moves_the_box_without_resizing_it() -> void:
	var box := Box.new(Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0))

	var moved: Box = Gizmo.translated_box(box, Gizmo.AXIS_X, 0.5)

	assert_almost_eq(moved.center.x, 1.5, 0.0001)
	assert_eq(moved.size, box.size, "a translate must not change the extent")
