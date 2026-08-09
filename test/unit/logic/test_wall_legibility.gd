extends GutTest

## tb31 Pass C: pure geometry, no Node/Camera3D involved — the view layer
## (test_board_view.gd) proves the REAL node reads back correctly per
## docs/10 standing rule 2; this proves the decision math itself.
## Screen-space, not world-space (see wall_legibility.gd's own header for
## why): a wall's projected screen position near the focal point's own,
## and nearer to the camera in depth.


func test_a_wall_near_the_focal_points_own_screen_position_and_nearer_occludes() -> void:
	var wall_screen := Vector2(100, 100)
	var wall_depth := 5.0
	var focal_screen := Vector2(105, 102)
	var focal_depth := 10.0
	assert_true(
		WallLegibility.occludes_on_screen(wall_screen, wall_depth, focal_screen, focal_depth, 20.0)
	)


func test_a_wall_far_from_the_focal_points_screen_position_does_not_occlude() -> void:
	var wall_screen := Vector2(400, 400)
	var focal_screen := Vector2(105, 102)
	assert_false(WallLegibility.occludes_on_screen(wall_screen, 5.0, focal_screen, 10.0, 20.0))


func test_a_wall_behind_the_focal_point_does_not_occlude_even_at_the_same_screen_position() -> void:
	var same_screen := Vector2(100, 100)
	# The wall is FARTHER from the camera than the focal point — it's
	# behind, not in front of, whatever it would be hiding.
	assert_false(WallLegibility.occludes_on_screen(same_screen, 12.0, same_screen, 10.0, 20.0))


func test_a_wall_at_the_exact_same_depth_as_the_focal_point_does_not_occlude() -> void:
	# Equal depth isn't "in front of" — the wall standing where the
	## target itself stands (e.g. the target is in cover) isn't in the way
	## of reading the target.
	var same_screen := Vector2(100, 100)
	assert_false(WallLegibility.occludes_on_screen(same_screen, 10.0, same_screen, 10.0, 20.0))


func test_a_wall_just_inside_the_screen_radius_occludes() -> void:
	var focal_screen := Vector2(100, 100)
	var wall_screen := Vector2(100, 119)  # 19px away
	assert_true(WallLegibility.occludes_on_screen(wall_screen, 5.0, focal_screen, 10.0, 20.0))


func test_a_wall_just_outside_the_screen_radius_does_not_occlude() -> void:
	var focal_screen := Vector2(100, 100)
	var wall_screen := Vector2(100, 121)  # 21px away
	assert_false(WallLegibility.occludes_on_screen(wall_screen, 5.0, focal_screen, 10.0, 20.0))


## tb32 Pass A: `pixel_radius_for_cells` — pure trig, no Camera3D node
## involved; `test_board_view.gd` proves the real node/shader-uniform
## wiring reads the same values back.


func test_pixel_radius_for_cells_is_positive_for_a_unit_on_screen() -> void:
	assert_gt(WallLegibility.pixel_radius_for_cells(2.5, 10.0, 75.0, 1080.0), 0.0)


func test_pixel_radius_for_cells_shrinks_as_depth_increases() -> void:
	var near_radius: float = WallLegibility.pixel_radius_for_cells(2.5, 10.0, 75.0, 1080.0)
	var far_radius: float = WallLegibility.pixel_radius_for_cells(2.5, 20.0, 75.0, 1080.0)
	assert_lt(far_radius, near_radius, "the same cell radius at twice the depth must be smaller")


func test_pixel_radius_for_cells_grows_with_more_cells() -> void:
	var small: float = WallLegibility.pixel_radius_for_cells(1.0, 10.0, 75.0, 1080.0)
	var large: float = WallLegibility.pixel_radius_for_cells(2.5, 10.0, 75.0, 1080.0)
	assert_gt(large, small)


func test_pixel_radius_for_cells_is_zero_at_zero_depth() -> void:
	assert_eq(WallLegibility.pixel_radius_for_cells(2.5, 0.0, 75.0, 1080.0), 0.0)


## `BR32.05`, taskblock-61 Pass C1: the supervisor's gate — "if a wall is detected between the
## camera and the unit, then continue doing what we're doing already, and if no wall is detected,
## then disable the cutout for that unit." World-space and real, unlike everything above it in
## this file: the *radius* is screen-space on purpose (see `wall_legibility.gd`'s own header) but
## "is a wall in the way" was never a question a screen radius could answer.


func _standing_unit(cell: Vector2i, low: float = 0.2, high: float = 1.8) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, (low + high) * 0.5, 0.0), Vector3(0.6, high - low, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


## A blocker `height` tall standing at `cell` — authored here rather than taken from
## `DataLibrary` because the leg-height case below needs a wall SHORTER than the 2.4 `wall.tres`
## authors, and a test that needs a concrete number authors it as a fixture (CLAUDE.md).
func _short_wall(grid: Grid, cell: Vector2i, height: float) -> void:
	var wall := Part.new()
	wall.id = &"short_wall"
	wall.hp = 60
	wall.max_hp = 60
	wall.volume = [Box.new(Vector3(0.0, height * 0.5, 0.0), Vector3(1.0, height, 1.0))]
	grid.blockers[cell] = wall


func test_sight_to_a_unit_in_the_open_is_not_blocked() -> void:
	var grid := GridFixture.flat(5, 12)
	var unit := _standing_unit(Vector2i(2, 6))

	assert_false(
		WallLegibility.sight_blocked_to_unit(grid, Vector3(2, 5, -5), unit),
		"nothing on the board at all — there is nothing for a cutout to see through"
	)


func test_sight_through_a_wall_between_the_camera_and_the_unit_is_blocked() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var unit := _standing_unit(Vector2i(2, 6))

	assert_true(
		WallLegibility.sight_blocked_to_unit(grid, Vector3(2, 5, -5), unit),
		"a 2.4-tall wall squarely on the camera-to-body line must keep the cutout"
	)


## **The entry's own case, and the reason this gate exists.** `BR32.05`: "looking at a unit with a
## wall BEHIND them, a chunk is cut out of the top of that wall even though it's ordered behind the
## unit." Same board as the test above, camera moved to the unit's own side of the wall — which is
## also `wall_cutout.gdshader`'s own recorded still-open symptom, "with the camera and unit on the
## SAME side of a wall... the cutout still fires."
func test_a_wall_beyond_the_unit_does_not_block_sight_to_it() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 9)] = DataLibrary.get_part(&"wall")
	var unit := _standing_unit(Vector2i(2, 6))

	assert_false(
		WallLegibility.sight_blocked_to_unit(grid, Vector3(2, 5, -5), unit),
		"a wall on the far side of the unit hides nothing and must not keep the cutout alive"
	)


## The endpoint exemption, borrowed from `LoS` — "a floor that blinded whoever stood on it would be
## a spectacular way to fail this pass." A raised unit's own surface sits directly under its
## bottom sample point, so without excluding the body's own cell every raised unit would read as
## permanently occluded and the gate would do nothing at all.
func test_the_surface_a_unit_stands_on_does_not_block_sight_to_it() -> void:
	var grid := GridFixture.flat(5, 12)
	GridFixture.place_floor(grid, Vector2i(2, 6), 2.0)
	var unit := _standing_unit(Vector2i(2, 6))
	unit.height = UnitGeometry.true_height_for_cell(Vector2i(2, 6), grid)

	assert_false(
		WallLegibility.sight_blocked_to_unit(grid, Vector3(2, 8, -5), unit),
		"the unit's own floor is the thing it stands on, never the thing hiding it"
	)


## **Three sample points, not one.** A wall low enough to clear the body's centre still hides its
## legs, and a cutout that switches off there is off exactly when it is needed. Geometry chosen so
## the centre ray misses the wall by 0.59 and the bottom ray enters it — this test fails outright
## if `body_sight_points` is ever reduced to the bounding-sphere centre.
func test_a_wall_hiding_only_the_legs_still_blocks_sight() -> void:
	var grid := GridFixture.flat(5, 12)
	_short_wall(grid, Vector2i(2, 4), 0.6)
	var unit := _standing_unit(Vector2i(2, 6))
	var camera := Vector3(2, 1.6, -2)

	var points: Array[Vector3] = WallLegibility.body_sight_points(unit)
	assert_false(
		RayCaster.obstructed(grid, camera, points[0], grid.parts_at(unit.cell)),
		"sanity: the CENTRE ray clears this wall — that is what makes the case interesting"
	)
	assert_true(
		WallLegibility.sight_blocked_to_unit(grid, camera, unit),
		"a wall hiding only the legs is still a wall in the way"
	)


## `BR51.01`'s loud miss caught two fixtures building a target with no `volume` at all. This gate
## must report an honest answer for that board state rather than an AABB assembled from infinities.
func test_a_body_with_no_geometry_reports_a_single_sample_point() -> void:
	var unit := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(2, 6), 0)

	var points: Array[Vector3] = WallLegibility.body_sight_points(unit)

	assert_eq(points.size(), 1, "no boxes to measure — one honest point, not three fabricated ones")
	assert_eq(points[0], UnitGeometry.bounding_sphere(unit).center)


## `cuts_for` gathers three unrelated reasons a unit is not worth cutting for. The view tests
## drive it through the real uniform feed; these two paths have no view route to reach them.
func test_cuts_for_refuses_an_extracted_unit_even_behind_a_wall() -> void:
	var grid := GridFixture.flat(5, 12)
	grid.blockers[Vector2i(2, 3)] = DataLibrary.get_part(&"wall")
	var unit := _standing_unit(Vector2i(2, 6))
	var camera := Vector3(2, 5, -5)
	assert_true(
		WallLegibility.cuts_for(grid, camera, unit), "sanity: this unit is genuinely behind a wall"
	)

	unit.extracted = true

	assert_false(
		WallLegibility.cuts_for(grid, camera, unit),
		"extraction never clears `.cell` — a walked-off unit must not keep cutting from it"
	)


## A `BoardView` with no board built yet has no geometry to ask. It must still answer the two
## questions it *can* answer rather than defaulting to "cut" for a corpse.
func test_cuts_for_without_a_grid_still_refuses_a_dead_unit() -> void:
	var unit := _standing_unit(Vector2i(2, 6))
	assert_true(WallLegibility.cuts_for(null, Vector3(2, 5, -5), unit), "sanity: alive, no board")

	unit.alive = false

	assert_false(
		WallLegibility.cuts_for(null, Vector3(2, 5, -5), unit),
		"no grid is no excuse for cutting a hole around a corpse"
	)
