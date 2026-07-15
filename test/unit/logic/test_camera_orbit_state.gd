extends GutTest

## docs/10: every camera clamp/delta lives in pure, headless-testable math —
## CameraRig (the Node) is a thin shell over this.


func test_orbit_accumulates_yaw() -> void:
	var state := CameraOrbitState.new()
	state.orbit(Vector2(100.0, 0.0))
	assert_almost_eq(state.yaw, -100.0 * CameraOrbitState.ORBIT_SPEED, 0.0001)


func test_pitch_clamps_and_never_reaches_a_pole() -> void:
	var state := CameraOrbitState.new()

	state.orbit(Vector2(0.0, 1000000.0))
	assert_almost_eq(state.pitch, CameraOrbitState.MIN_PITCH, 0.0001)
	assert_true(state.pitch > -PI / 2.0, "must never orbit past straight down")

	state.orbit(Vector2(0.0, -1000000.0))
	assert_almost_eq(state.pitch, CameraOrbitState.MAX_PITCH, 0.0001)
	assert_true(state.pitch < 0.0, "must never level all the way into the board plane")


func test_zoom_clamps_within_bounds() -> void:
	var state := CameraOrbitState.new()
	for i in range(1000):
		state.zoom_in()
	assert_eq(state.zoom, CameraOrbitState.MIN_ZOOM)
	for i in range(1000):
		state.zoom_out()
	assert_eq(state.zoom, CameraOrbitState.MAX_ZOOM)


func test_pan_offsets_along_the_given_axes() -> void:
	var state := CameraOrbitState.new()
	state.pan(Vector2(10.0, 0.0), Vector3.RIGHT, Vector3.FORWARD)
	assert_almost_eq(state.pan_offset.x, -10.0 * CameraOrbitState.PAN_SPEED, 0.0001)
	assert_almost_eq(state.pan_offset.z, 0.0, 0.0001)
