extends GutTest

## docs/10: CameraRig is a thin shell — it only builds the two-pivot rig and
## applies CameraOrbitState to it. The math itself is covered headlessly in
## test_camera_orbit_state.gd.


func test_ready_builds_a_two_pivot_rig_with_a_camera() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)

	assert_eq(rig.get_child_count(), 1, "one yaw pivot")
	var yaw: Node3D = rig.get_child(0)
	assert_eq(yaw.get_child_count(), 1, "one pitch pivot")
	var pitch: Node3D = yaw.get_child(0)
	assert_eq(pitch.get_child_count(), 1, "one camera")
	assert_true(pitch.get_child(0) is Camera3D)


func test_applying_state_moves_the_camera_to_the_current_zoom() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)

	rig.state.zoom = 20.0
	rig._apply_state()

	var camera: Camera3D = rig.get_child(0).get_child(0).get_child(0)
	assert_almost_eq(camera.position.z, 20.0, 0.0001)


func test_applying_state_sets_yaw_and_pitch_on_their_own_pivots() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)

	rig.state.yaw = 1.2
	rig.state.pitch = -0.5
	rig._apply_state()

	var yaw: Node3D = rig.get_child(0)
	var pitch: Node3D = yaw.get_child(0)
	assert_almost_eq(yaw.rotation.y, 1.2, 0.0001)
	assert_almost_eq(pitch.rotation.x, -0.5, 0.0001)


func _wheel_event(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


func test_wheel_zooms_when_zoom_enabled() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var before: float = rig.state.zoom

	rig._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_lt(rig.state.zoom, before, "scrolling up must zoom in while zoom is enabled")


func test_wheel_does_nothing_when_zoom_disabled() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.zoom_enabled = false
	var before: float = rig.state.zoom

	rig._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_eq(rig.state.zoom, before, "docs/10: in the aim UI, scroll steps layers, not zoom")
