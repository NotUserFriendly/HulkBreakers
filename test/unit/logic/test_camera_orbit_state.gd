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


## Reconstructs the rig's own look direction from {yaw, pitch} — the exact
## relationship verified against a real Camera3D in scratchpad
## diag_lookat.gd: pitch alone sets the vertical component (`sin(pitch)`,
## independent of yaw, since pitch is the second rotation and always
## applied around the already-yawed frame's own horizontal local X); yaw
## alone sets the horizontal angle. Reused here so the pure-math tests can
## check "does this framing actually look at the target" without a live
## Camera3D (that end-to-end check lives in test_camera_rig.gd instead).
func _look_dir(yaw: float, pitch: float) -> Vector3:
	var horiz: float = cos(pitch)
	return Vector3(-sin(yaw) * horiz, sin(pitch), -cos(yaw) * horiz)


## runNotes.md follow-up: "tie the third person camera to the torso of the
## aiming unit, offset right and up... point the camera at the torso of the
## targeted unit." zoom=0 makes pan_offset the camera's exact world
## position (no orbit-distance offset left); yaw/pitch must make it
## actually look at the target's torso from there.
func test_attack_framing_positions_the_camera_at_the_shooter_offset_right_and_up() -> void:
	var state := CameraOrbitState.new()
	var shooter := Vector3(2.0, 0.0, 3.0)
	var target := Vector3(9.0, 0.0, 3.0)

	var framing: Dictionary = state.attack_framing(shooter, target)
	var pos: Vector3 = framing.pan_offset

	assert_eq(framing.zoom, 0.0, "no orbit-distance offset left — pan_offset IS the camera")
	assert_almost_eq(
		pos.y,
		CameraOrbitState.ATTACK_TORSO_HEIGHT + CameraOrbitState.ATTACK_UP_OFFSET,
		0.0001,
		"torso height plus the up offset"
	)
	# Due +X shot line: "right" (forward x up, Godot's own right-handed Y-up
	# convention — verified against a real Camera3D, see diag_lookat.gd) is
	# due +Z.
	assert_almost_eq(pos.x, shooter.x, 0.0001)
	assert_almost_eq(pos.z, shooter.z + CameraOrbitState.ATTACK_RIGHT_OFFSET, 0.0001)


func test_attack_framing_actually_looks_at_the_targets_torso() -> void:
	var state := CameraOrbitState.new()
	var shooter := Vector3(2.0, 0.0, 3.0)
	var target := Vector3(9.0, 0.0, 8.0)  # diagonal, not sharing a row or column

	var framing: Dictionary = state.attack_framing(shooter, target)
	var pos: Vector3 = framing.pan_offset
	var target_torso: Vector3 = target + Vector3(0.0, CameraOrbitState.ATTACK_TORSO_HEIGHT, 0.0)
	var expected_look: Vector3 = (target_torso - pos).normalized()

	var actual_look: Vector3 = _look_dir(framing.yaw, framing.pitch)
	assert_almost_eq(actual_look.x, expected_look.x, 0.001)
	assert_almost_eq(actual_look.y, expected_look.y, 0.001)
	assert_almost_eq(actual_look.z, expected_look.z, 0.001)


func test_attack_framing_falls_back_when_shooter_and_target_share_a_cell() -> void:
	var state := CameraOrbitState.new()
	state.yaw = 1.75
	state.pitch = -0.4
	var same_point := Vector3(4.0, 0.0, 4.0)

	var framing: Dictionary = state.attack_framing(same_point, same_point)

	assert_almost_eq(framing.yaw, 1.75, 0.0001, "no direction to face: leave yaw where it was")
	assert_almost_eq(framing.pitch, CameraOrbitState.ATTACK_PITCH, 0.0001)


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
