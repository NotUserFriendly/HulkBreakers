extends GutTest

## taskblock-25 Pass C: a slash's own payload shape — N adjacent points
## along a line, centered on the aim point.


func test_zero_length_is_a_single_point_at_the_aim_point() -> void:
	var points: Array[Vector2] = MeleeLine.sample(Vector2(1.0, 2.0), 0.0, &"horizontal")
	assert_eq(points, [Vector2(1.0, 2.0)])


func test_horizontal_line_spans_the_lateral_axis_centered_on_the_aim_point() -> void:
	var points: Array[Vector2] = MeleeLine.sample(Vector2(0.0, 1.0), 1.0, &"horizontal")

	assert_true(points.size() >= 2)
	assert_almost_eq(points[0].x, -0.5, 0.01)
	assert_almost_eq(points[0].y, 1.0, 0.01, "horizontal never moves the height axis")
	assert_almost_eq(points[-1].x, 0.5, 0.01)


## docs/PLAN.md Pass C: "a vertical slash uses the 3D plane to spread
## up/down a body" — `Region.rect`'s own Y axis IS real world height
## since taskblock-23, so this falls out of the axis choice alone.
func test_vertical_line_spans_the_real_height_axis_centered_on_the_aim_point() -> void:
	var points: Array[Vector2] = MeleeLine.sample(Vector2(2.0, 1.0), 1.0, &"vertical")

	assert_almost_eq(points[0].x, 2.0, 0.01, "vertical never moves the lateral axis")
	assert_almost_eq(points[0].y, 0.5, 0.01)
	assert_almost_eq(points[-1].y, 1.5, 0.01)


func test_diagonal_line_moves_both_axes_equally() -> void:
	var points: Array[Vector2] = MeleeLine.sample(Vector2(0.0, 0.0), 1.0, &"diagonal")

	var first: Vector2 = points[0]
	var last: Vector2 = points[-1]
	assert_almost_eq(absf(first.x), absf(first.y), 0.01)
	assert_almost_eq(absf(last.x), absf(last.y), 0.01)
	assert_gt(last.x, first.x)


## The line's own real span end to end must equal `slash_length`, not just
## "roughly" — this is the taskblock's own literal claim ("length =
## weapon's slash_length").
func test_the_lines_own_span_matches_slash_length_exactly() -> void:
	var points: Array[Vector2] = MeleeLine.sample(Vector2(0.0, 0.0), 2.0, &"horizontal")
	assert_almost_eq(points[-1].x - points[0].x, 2.0, 0.001)


func test_an_unrecognized_orientation_falls_back_to_horizontal_never_crashes() -> void:
	var points: Array[Vector2] = MeleeLine.sample(Vector2(0.0, 0.0), 1.0, &"nonsense")
	assert_almost_eq(points[0].y, 0.0, 0.01)
	assert_ne(points[0].x, points[-1].x)
