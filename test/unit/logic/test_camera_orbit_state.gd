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


## docs/10 taskblock03 C1: the over-the-shoulder attack framing.
func test_attack_framing_centers_on_the_shooter_at_the_attack_defaults() -> void:
	var state := CameraOrbitState.new()
	var shooter := Vector3(2.0, 0.0, 3.0)
	var target := Vector3(9.0, 0.0, 3.0)

	var framing: Dictionary = state.attack_framing(shooter, target)

	assert_eq(framing.pan_offset, shooter, "centers on the shooter, the shoulder framed over")
	assert_eq(framing.pitch, CameraOrbitState.ATTACK_PITCH)
	assert_eq(framing.zoom, CameraOrbitState.ATTACK_ZOOM)


func test_attack_framing_falls_back_to_the_current_yaw_when_shooter_and_target_share_a_cell(
) -> void:
	var state := CameraOrbitState.new()
	state.yaw = 1.75
	var same_point := Vector3(4.0, 0.0, 4.0)

	var framing: Dictionary = state.attack_framing(same_point, same_point)

	assert_almost_eq(framing.yaw, 1.75, 0.0001, "no direction to face: leave yaw where it was")


## The exact yaw computed isn't the point (that's an implementation detail
## of which side of the pivot the rig orbits to) — what matters is that it
## responds to the actual shooter->target direction, not a constant, and
## is deterministic.
func test_attack_framing_yaw_responds_to_the_shooter_to_target_direction() -> void:
	var state := CameraOrbitState.new()
	var shooter := Vector3(0.0, 0.0, 0.0)

	var east: Dictionary = state.attack_framing(shooter, Vector3(5.0, 0.0, 0.0))
	var north: Dictionary = state.attack_framing(shooter, Vector3(0.0, 0.0, 5.0))

	assert_ne(east.yaw, north.yaw)
	assert_eq(
		state.attack_framing(shooter, Vector3(5.0, 0.0, 0.0)).yaw,
		east.yaw,
		"deterministic: same inputs, same framing"
	)
