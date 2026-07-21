extends GutTest

## tb31 Pass C: pure geometry, no Node/Camera3D involved — the view layer
## (test_board_view.gd) proves the REAL node reads back correctly per
## docs/10 standing rule 2; this proves the decision math itself.


func test_a_wall_directly_between_camera_and_focal_point_occludes() -> void:
	var camera := Vector3(0, 1, 0)
	var focal := Vector3(0, 1, 10)
	var wall := Vector3(0, 1, 5)
	assert_true(WallLegibility.occludes(camera, focal, wall, 1.0))


func test_a_wall_behind_the_focal_point_does_not_occlude() -> void:
	var camera := Vector3(0, 1, 0)
	var focal := Vector3(0, 1, 10)
	var wall := Vector3(0, 1, 15)
	assert_false(WallLegibility.occludes(camera, focal, wall, 1.0))


func test_a_wall_behind_the_camera_does_not_occlude() -> void:
	var camera := Vector3(0, 1, 0)
	var focal := Vector3(0, 1, 10)
	var wall := Vector3(0, 1, -5)
	assert_false(WallLegibility.occludes(camera, focal, wall, 1.0))


func test_a_wall_off_to_the_side_beyond_the_radius_does_not_occlude() -> void:
	var camera := Vector3(0, 1, 0)
	var focal := Vector3(0, 1, 10)
	var wall := Vector3(5, 1, 5)  # same depth, far off the sightline
	assert_false(WallLegibility.occludes(camera, focal, wall, 1.0))


func test_a_wall_just_inside_the_radius_occludes() -> void:
	var camera := Vector3(0, 1, 0)
	var focal := Vector3(0, 1, 10)
	var wall := Vector3(0.9, 1, 5)
	assert_true(WallLegibility.occludes(camera, focal, wall, 1.0))


func test_a_wall_at_the_exact_focal_point_does_not_occlude() -> void:
	# The wall standing where the target itself stands (e.g. the target
	# is IN cover) isn't "in the way" of reading the target — it IS the
	# target's own position.
	var camera := Vector3(0, 1, 0)
	var focal := Vector3(0, 1, 10)
	assert_false(WallLegibility.occludes(camera, focal, focal, 1.0))


func test_camera_coincident_with_focal_point_never_occludes() -> void:
	var camera := Vector3(3, 1, 3)
	assert_false(WallLegibility.occludes(camera, camera, Vector3(3, 1, 4), 1.0))
