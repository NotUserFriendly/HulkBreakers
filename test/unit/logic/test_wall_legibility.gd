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
