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


## taskblock-37 Pass E follow-up (supervisor bug report: "mousing over a
## cell requires you to mouse over the base of the terrain, not the top"):
## a straight-down ray over a raised cell must resolve against that
## cell's own real top face, not the old fixed y == 0 plane it would sit
## on with no grid passed at all.
func test_a_ray_straight_down_hits_a_raised_cells_own_real_top_face() -> void:
	var grid := GridFixture.flat(4, 3)
	GridFixture.place_floor(grid, Vector2i(2, 1), 2)

	var cell: Variant = BoardPicker.cell_at_ray(
		Vector3(2.0, 5.0, 1.0), Vector3(0.0, -1.0, 0.0), grid
	)

	assert_eq(cell, Vector2i(2, 1))


## The same raised cell also has to win the ray at the ACTUAL, shorter
## distance to its own top face — this is the value TacticsController
## compares against a real 3D part hit to decide "nearest hit wins."
func test_plane_hit_t_reflects_a_raised_cells_own_real_height() -> void:
	var grid := GridFixture.flat(4, 3)
	GridFixture.place_floor(grid, Vector2i(2, 1), 2)

	var t: Variant = BoardPicker.plane_hit_t(Vector3(2.0, 5.0, 1.0), Vector3(0.0, -1.0, 0.0), grid)

	assert_almost_eq(t, 5.0 - 2.0 * UnitGeometry.LEVEL_HEIGHT, 0.0001)


## A ray aimed at a cell right next to a raised one must still resolve
## against the FLAT neighbor's own real (ground-level) height, not get
## dragged onto the raised cell's height by the iterative refinement.
func test_a_ray_over_a_flat_neighbor_of_a_raised_cell_stays_at_ground_level() -> void:
	var grid := GridFixture.flat(4, 3)
	GridFixture.place_floor(grid, Vector2i(2, 1), 2)

	var cell: Variant = BoardPicker.cell_at_ray(
		Vector3(0.0, 5.0, 1.0), Vector3(0.0, -1.0, 0.0), grid
	)

	assert_eq(cell, Vector2i(0, 1))


## **`BR35.02`, taskblock-61 Pass D.** `cell_at_ray` is blind plane math: it says which cell a ray
## crosses, with no notion of what stands between. That was reliable while cover was short and
## sparse; walls are 2.4m tall and dense now, so the tile-inspect click could open a cell on the
## far side of a wall — one the player has never seen.
func test_a_cell_hidden_behind_a_wall_is_not_visible_from_the_camera() -> void:
	var grid := GridFixture.flat(10, 10)
	grid.blockers[Vector2i(4, 4)] = DataLibrary.get_part(&"wall")
	# Camera low and level, so the wall is squarely between it and the cell beyond.
	var camera := Vector3(1.0, 1.2, 4.0)

	assert_false(
		BoardPicker.cell_visible_from(grid, camera, Vector2i(7, 4)),
		"the wall at (4,4) stands between the camera and (7,4)"
	)
	assert_true(
		BoardPicker.cell_visible_from(grid, camera, Vector2i(2, 4)),
		"and a cell on this side of it is plainly visible"
	)


## **The endpoint exemption, and why it is not optional.** The thing being clicked must never count
## as the thing hiding it — a wall cell has to stay inspectable by clicking the wall, and a floor
## that blinded whoever clicked it would be the failure `LoS` warns about.
func test_a_cell_is_never_hidden_by_whatever_stands_on_it() -> void:
	var grid := GridFixture.flat(10, 10)
	grid.blockers[Vector2i(4, 4)] = DataLibrary.get_part(&"wall")
	var camera := Vector3(1.0, 1.2, 4.0)

	assert_true(
		BoardPicker.cell_visible_from(grid, camera, Vector2i(4, 4)),
		"clicking the wall itself must still resolve to the wall"
	)


## A raised cell's own floor is under its surface point, not in front of it — the tile a click
## lands on cannot be what occludes that click.
func test_a_raised_cells_own_floor_does_not_hide_it() -> void:
	var grid := GridFixture.flat(10, 10)
	GridFixture.place_floor(grid, Vector2i(6, 4), 2.0)

	assert_true(
		BoardPicker.cell_visible_from(grid, Vector3(1.0, 6.0, 4.0), Vector2i(6, 4)),
		"a raised tile is visible from above, not blinded by itself"
	)
