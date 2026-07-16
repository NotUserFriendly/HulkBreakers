extends GutTest

## docs/10 Phase 12.2: pure ray-to-cell math, no camera/viewport needed.


func test_a_ray_straight_down_hits_the_cell_below_it() -> void:
	var cell: Variant = BoardPicker.cell_at_ray(Vector3(2.0, 5.0, 3.0), Vector3(0.0, -1.0, 0.0))
	assert_eq(cell, Vector2i(2, 3))


func test_rounds_to_the_nearest_cell_not_the_floor() -> void:
	var cell: Variant = BoardPicker.cell_at_ray(Vector3(2.4, 5.0, 3.6), Vector3(0.0, -1.0, 0.0))
	assert_eq(cell, Vector2i(2, 4))


func test_an_angled_ray_still_resolves_to_the_correct_ground_point() -> void:
	# From (0, 1, 0) at a 45-degree downward angle along +x: crosses y == 0
	# at x == 1.
	var cell: Variant = BoardPicker.cell_at_ray(Vector3(0.0, 1.0, 0.0), Vector3(1.0, -1.0, 0.0))
	assert_eq(cell, Vector2i(1, 0))


func test_a_ray_parallel_to_the_ground_never_hits_it() -> void:
	var cell: Variant = BoardPicker.cell_at_ray(Vector3(0.0, 5.0, 0.0), Vector3(1.0, 0.0, 0.0))
	assert_null(cell)


func test_a_ray_pointing_away_from_the_ground_never_hits_it() -> void:
	# Below the board, aimed further down and away.
	var cell: Variant = BoardPicker.cell_at_ray(Vector3(0.0, -5.0, 0.0), Vector3(0.0, -1.0, 0.0))
	assert_null(cell)
