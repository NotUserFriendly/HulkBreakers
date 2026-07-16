extends GutTest

## docs/10 taskblock03 F2: pure box-mesh line geometry shared by
## ResolutionPlayer's real tracer and AimView's ghost targeting line.


func test_segment_size_is_square_and_as_long_as_the_segment() -> void:
	var size: Vector3 = TracerGeometry.segment_size(
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 4.0), 0.05
	)
	assert_eq(size, Vector3(0.05, 0.05, 4.0))


func test_segment_transform_centers_on_the_segments_midpoint() -> void:
	var transform: Transform3D = TracerGeometry.segment_transform(
		Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)
	)
	assert_eq(transform.origin, Vector3(1.0, 0.0, 0.0))


func test_segment_transform_orients_local_z_along_the_segment() -> void:
	var from := Vector3(0.0, 0.0, 0.0)
	var to := Vector3(3.0, 0.0, 0.0)
	var transform: Transform3D = TracerGeometry.segment_transform(from, to)

	# A box's local +Z end, carried through the transform, must land
	# exactly on `to` — the segment's own far end.
	var local_far_end: Vector3 = transform * Vector3(0.0, 0.0, (to - from).length() * 0.5)
	assert_almost_eq(local_far_end.x, to.x, 0.001)
	assert_almost_eq(local_far_end.z, to.z, 0.001)


func test_a_degenerate_segment_returns_identity_at_from_rather_than_crash() -> void:
	var point := Vector3(5.0, 1.0, 5.0)
	var transform: Transform3D = TracerGeometry.segment_transform(point, point)
	assert_eq(transform.origin, point)
