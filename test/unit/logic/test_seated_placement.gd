extends GutTest

## **A placement is seated against the face it was clicked on, not hung from its own origin.**
## taskblock-59 follow-up.
##
## > *"Clicking the side of a floor places the newly placed floor down by 0.2 again. Clicking the
## > top face of a floor places the new floor inside the clicked floor, which would be another -0.2
## > offset."*
##
## One cause. `FacePlacement.target_for` answers **where the face is**, and the caller used that as
## the placement's `height` — but `height` is the placement's *origin* and a part's geometry is not
## centred on it. `ship_floor` authors its box at `center.y = -0.1, size.y = 0.2`, so it hangs
## entirely below its own height, and a floor placed at the struck plane occupies the 0.2 under it:
## the space the clicked floor is already in.

## Where a `ship_floor` at `height` actually spans, as the board draws it.
const FLOOR_THICKNESS := 0.2


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _floor_at(height: float) -> Array[MapPlacement]:
	return [MapPlacement.new(Vector2i(2, 2), MapPlacement.KIND_SURFACE, &"ship_floor", height)]


## The world extent of a `ship_floor` authored at `height`, read off the part rather than assumed.
func _spans(height: float) -> Vector2:
	var bounds: AABB = PlacedVolume.natural_bounds(DataLibrary.get_part(&"ship_floor"))
	return Vector2(height + bounds.position.y, height + bounds.position.y + bounds.size.y)


func test_the_fixture_matches_the_authored_part() -> void:
	var span: Vector2 = _spans(0.0)
	gut.p("a ship_floor at 0.0 spans %.2f to %.2f" % [span.x, span.y])
	assert_almost_eq(span.y, 0.0, 0.001, "its top is its own height")
	assert_almost_eq(span.x, -FLOOR_THICKNESS, 0.001, "and it hangs entirely below it")


# ---------------------------------------------------------------- the top face


## **A floor clicked on its top gets a floor standing ON it**, not one occupying the same space.
func test_a_floor_on_a_floor_s_top_face_sits_on_top_of_it() -> void:
	var clicked: Vector2 = _spans(0.0)

	var target: Dictionary = FacePlacement.target_from(
		_floor_at(0.0), Vector2i(2, 2), Vector3.UP, 0.0, DataLibrary.get_part(&"ship_floor")
	)
	var placed: Vector2 = _spans(float(target["height"]))

	gut.p("clicked %.2f..%.2f, placed %.2f..%.2f" % [clicked.x, clicked.y, placed.x, placed.y])
	assert_almost_eq(placed.x, clicked.y, 0.001, "the new floor's underside must meet the old top")
	assert_gt(placed.x, clicked.x + 0.001, "it is inside the floor that was clicked")


# ---------------------------------------------------------------- the side face


## **A floor clicked on its side gets a floor level with it**, not one 0.2 below.
func test_a_floor_beside_a_floor_is_level_with_it() -> void:
	var clicked: Vector2 = _spans(0.0)

	var target: Dictionary = FacePlacement.target_from(
		_floor_at(0.0), Vector2i(2, 2), Vector3.RIGHT, 0.0, DataLibrary.get_part(&"ship_floor")
	)
	var placed: Vector2 = _spans(float(target["height"]))

	gut.p("clicked %.2f..%.2f, placed %.2f..%.2f" % [clicked.x, clicked.y, placed.x, placed.y])
	assert_eq(target["cell"], Vector2i(3, 2), "a side face steps into the neighbour")
	assert_almost_eq(placed.y, clicked.y, 0.001, "their walking surfaces must be level")


## At elevation too, so what is asserted is "level with what was struck" rather than "zero".
func test_it_holds_at_elevation() -> void:
	var clicked: Vector2 = _spans(2.5)

	var target: Dictionary = FacePlacement.target_from(
		_floor_at(2.5), Vector2i(2, 2), Vector3.RIGHT, 0.0, DataLibrary.get_part(&"ship_floor")
	)

	assert_almost_eq(_spans(float(target["height"])).y, clicked.y, 0.001, "levels must match")


# ---------------------------------------------------------------- what must not move


## **A wall is unaffected**, which is why this only ever showed up on floors: its box starts at its
## own origin, so seating it against a face is the identity.
func test_a_wall_is_seated_exactly_where_it_always_was() -> void:
	var placements: Array[MapPlacement] = _floor_at(0.0)

	var seated: Dictionary = FacePlacement.target_from(
		placements, Vector2i(2, 2), Vector3.RIGHT, 0.0, DataLibrary.get_part(&"wall")
	)
	var bare: Dictionary = FacePlacement.target_from(placements, Vector2i(2, 2), Vector3.RIGHT, 0.0)

	assert_almost_eq(float(seated["height"]), float(bare["height"]), 0.0001)


## **`target_for` is untouched** — it still answers where the *face* is, which is what the
## taskblock-58 tests assert and what the seating is applied on top of.
func test_the_face_itself_is_still_reported_unadjusted() -> void:
	var at: Dictionary = FacePlacement.target_for(Vector2i(2, 2), Vector3.UP, 1.5, -0.5)
	assert_almost_eq(float(at["height"]), 1.5, 0.0001, "a top face is the struck top, plainly")


## A bottom face hangs the new part **under** what was clicked, so its top meets the plane.
func test_a_bottom_face_hangs_the_part_underneath() -> void:
	var clicked: Vector2 = _spans(0.0)

	var target: Dictionary = FacePlacement.target_from(
		_floor_at(0.0), Vector2i(2, 2), Vector3.DOWN, 0.0, DataLibrary.get_part(&"ship_floor")
	)
	var placed: Vector2 = _spans(float(target["height"]))

	gut.p("clicked %.2f..%.2f, placed %.2f..%.2f" % [clicked.x, clicked.y, placed.x, placed.y])
	assert_almost_eq(placed.y, clicked.x, 0.001, "its top must meet the clicked floor's underside")
