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


## docs/10 taskblock03 C1: "ease (don't cut)."
func test_ease_to_attack_framing_starts_a_tween_not_an_instant_cut() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var zoom_before: float = rig.state.zoom

	rig.ease_to_attack_framing(Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))

	assert_not_null(rig._active_tween)
	assert_eq(rig.state.zoom, zoom_before, "the state itself doesn't jump on the same frame")


## docs/10 taskblock03 C2: "orbit/pan/zoom stay live... any of them kills
## the tween outright so live input always wins immediately." The actual
## orbit/pan/zoom handlers read live hardware state via
## Input.is_mouse_button_pressed (pre-existing, not something this pass
## changed), which a headless test can't fake — this covers the shared
## primitive all three call, `_kill_active_tween` itself.
func test_kill_active_tween_clears_an_active_attack_framing_tween() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.ease_to_attack_framing(Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	assert_not_null(rig._active_tween)

	rig._kill_active_tween()

	assert_null(rig._active_tween)


func test_wheel_zoom_kills_an_active_attack_framing_tween() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.ease_to_attack_framing(Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	assert_not_null(rig._active_tween)

	rig._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_null(rig._active_tween, "the scroll-wheel path is fakeable headlessly, unlike drag")


func test_ease_to_attack_framing_targets_the_attack_defaults() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var shooter := Vector3(2.0, 0.0, 2.0)
	var target := Vector3(8.0, 0.0, 2.0)

	rig.ease_to_attack_framing(shooter, target)
	# Fast-forward past the tween's own duration so the eased values land.
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)

	# The pure math is CameraOrbitState's own contract, covered exactly in
	# test_camera_orbit_state.gd — this only needs to confirm the tween
	# actually lands ON that computed target, not redo the geometry by hand.
	var expected: Dictionary = CameraOrbitState.new().attack_framing(shooter, target)
	assert_almost_eq(rig.state.pitch, expected.pitch, 0.0001)
	assert_almost_eq(rig.state.zoom, expected.zoom, 0.0001)
	assert_almost_eq(rig.state.pan_offset.x, (expected.pan_offset as Vector3).x, 0.01)
	assert_almost_eq(rig.state.pan_offset.y, (expected.pan_offset as Vector3).y, 0.01)
	assert_almost_eq(rig.state.pan_offset.z, (expected.pan_offset as Vector3).z, 0.01)


## runNotes.md follow-up: "point the camera at the torso of the targeted
## unit" — an end-to-end check against the REAL Camera3D transform, not
## just CameraOrbitState's own math (which test_camera_orbit_state.gd
## already verifies against a reconstructed direction — this is the same
## claim, checked the other way, against a live rig).
func test_ease_to_attack_framing_actually_points_the_real_camera_at_the_targets_torso() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var shooter := Vector3(2.0, 0.0, 3.0)
	var target := Vector3(9.0, 0.0, 8.0)  # diagonal, not sharing a row or column

	rig.ease_to_attack_framing(shooter, target)
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)

	var camera: Camera3D = rig.camera()
	var target_torso: Vector3 = target + Vector3(0.0, CameraOrbitState.ATTACK_TORSO_HEIGHT, 0.0)
	var expected_look: Vector3 = (target_torso - camera.global_transform.origin).normalized()
	var actual_look: Vector3 = -camera.global_transform.basis.z
	assert_almost_eq(actual_look.x, expected_look.x, 0.001)
	assert_almost_eq(actual_look.y, expected_look.y, 0.001)
	assert_almost_eq(actual_look.z, expected_look.z, 0.001)


## runNotes.md: "third person camera needs to be locked" — while `locked`,
## no live input may move the camera at all. Orbit/pan read live hardware
## state via Input.is_mouse_button_pressed (unfakeable headlessly, per the
## existing convention in this file); wheel-zoom is the one branch a
## dispatched event alone can exercise.
func test_locked_blocks_wheel_zoom() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.locked = true
	var zoom_before: float = rig.state.zoom

	rig._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_almost_eq(rig.state.zoom, zoom_before, 0.0001, "wheel must not zoom the locked camera")


func test_locked_does_not_prevent_the_easing_tween_itself() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.locked = true

	rig.ease_to_attack_framing(Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))

	assert_not_null(rig._active_tween, "locking input must not block the ease itself")
