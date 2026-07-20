extends GutTest

## docs/10: CameraRig is a thin shell — it only builds the two-pivot rig and
## applies CameraOrbitState to it. The math itself is covered headlessly in
## test_camera_orbit_state.gd.


func _make_unit(
	cell: Vector2i, box_center: Vector3 = Vector3.ZERO, box_size: Vector3 = Vector3(0.5, 0.7, 0.28)
) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(box_center, box_size)]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func test_ready_builds_a_two_pivot_rig_with_a_camera() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)

	assert_eq(rig.get_child_count(), 1, "one yaw pivot")
	var yaw: Node3D = rig.get_child(0)
	assert_eq(yaw.get_child_count(), 1, "one pitch pivot")
	var pitch: Node3D = yaw.get_child(0)
	assert_eq(pitch.get_child_count(), 1, "one camera")
	assert_true(pitch.get_child(0) is Camera3D)


## docs/10 taskblock05 B1: "the real Camera3D never sets fov" — the solver's
## whole framing budget (CameraOrbitState.CAMERA_FOV_DEG) is meaningless
## unless the live camera actually uses it.
func test_ready_sets_the_cameras_fov_from_the_solvers_constant() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)

	assert_eq(rig.camera().fov, CameraOrbitState.CAMERA_FOV_DEG)


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

	rig.ease_to_attack_framing(_make_unit(Vector2i(0, 0)), _make_unit(Vector2i(5, 0)))

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
	rig.ease_to_attack_framing(_make_unit(Vector2i(0, 0)), _make_unit(Vector2i(5, 0)))
	assert_not_null(rig._active_tween)

	rig._kill_active_tween()

	assert_null(rig._active_tween)


func test_wheel_zoom_kills_an_active_attack_framing_tween() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.ease_to_attack_framing(_make_unit(Vector2i(0, 0)), _make_unit(Vector2i(5, 0)))
	assert_not_null(rig._active_tween)

	rig._unhandled_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))

	assert_null(rig._active_tween, "the scroll-wheel path is fakeable headlessly, unlike drag")


func test_ease_to_attack_framing_targets_the_solved_framing() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var shooter := _make_unit(Vector2i(2, 2))
	var target := _make_unit(Vector2i(8, 2))

	rig.ease_to_attack_framing(shooter, target)
	# Fast-forward past the tween's own duration so the eased values land.
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)

	# The pure math is CameraOrbitState's own contract, covered exactly in
	# test_camera_orbit_state.gd — this only needs to confirm the tween
	# actually lands ON that computed target, not redo the geometry by hand.
	var expected: Dictionary = CameraOrbitState.new().attack_framing(
		UnitGeometry.bounding_sphere(shooter), UnitGeometry.bounding_sphere(target)
	)
	assert_almost_eq(rig.state.pitch, expected.pitch, 0.0001)
	assert_almost_eq(rig.state.zoom, expected.zoom, 0.0001)
	assert_almost_eq(rig.state.pan_offset.x, (expected.pan_offset as Vector3).x, 0.01)
	assert_almost_eq(rig.state.pan_offset.y, (expected.pan_offset as Vector3).y, 0.01)
	assert_almost_eq(rig.state.pan_offset.z, (expected.pan_offset as Vector3).z, 0.01)


## taskblock-27 Pass D4: "the camera doesn't reset after aiming." Nothing
## snapshotted the pre-aim framing at all before this fix — `stop_aiming`
## only ever cleared the look-at lean, leaving yaw/pitch/zoom/pan at
## wherever the attack framing eased them to. `start_aiming` must
## snapshot the REAL pre-aim state, and `stop_aiming` must ease back to
## it, not merely restore control flags.
func test_stop_aiming_eases_the_camera_back_to_its_pre_aim_framing() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.state.yaw = 0.4
	rig.state.pitch = -0.2
	rig.state.zoom = 15.0
	rig.state.pan_offset = Vector3(3.0, 0.0, 7.0)
	var pre_aim_yaw: float = rig.state.yaw
	var pre_aim_pitch: float = rig.state.pitch
	var pre_aim_zoom: float = rig.state.zoom
	var pre_aim_pan: Vector3 = rig.state.pan_offset

	rig.start_aiming()
	rig.ease_to_attack_framing(_make_unit(Vector2i(2, 2)), _make_unit(Vector2i(8, 2)))
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)
	assert_ne(rig.state.pan_offset, pre_aim_pan, "sanity: the attack framing actually moved it")

	rig.stop_aiming()
	assert_not_null(
		rig._active_tween, "stop_aiming must start a real ease back, not an instant cut"
	)
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)

	assert_almost_eq(rig.state.yaw, pre_aim_yaw, 0.0001)
	assert_almost_eq(rig.state.pitch, pre_aim_pitch, 0.0001)
	assert_almost_eq(rig.state.zoom, pre_aim_zoom, 0.0001)
	assert_almost_eq(rig.state.pan_offset.x, pre_aim_pan.x, 0.0001)
	assert_almost_eq(rig.state.pan_offset.y, pre_aim_pan.y, 0.0001)
	assert_almost_eq(rig.state.pan_offset.z, pre_aim_pan.z, 0.0001)


## A `stop_aiming` with no matching `start_aiming` must never crash or
## snap to a stale zero-value snapshot — the defensive guard.
func test_stop_aiming_without_start_aiming_never_crashes_or_eases_anywhere() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.state.yaw = 0.4
	rig.state.zoom = 15.0

	rig.stop_aiming()

	assert_null(rig._active_tween, "no snapshot to restore -- must not start a bogus ease")
	assert_almost_eq(rig.state.yaw, 0.4, 0.0001)
	assert_almost_eq(rig.state.zoom, 15.0, 0.0001)


## docs/10 taskblock04 A3: "the rig looks at its pivot by construction" —
## the target's screen-projected centre must land dead-center in the
## viewport, an orbit-pivot property Design 2's explicit look-at solve
## never guaranteed by itself.
func test_ease_to_attack_framing_centers_the_target_on_screen() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var shooter := _make_unit(Vector2i(2, 3))
	var target := _make_unit(Vector2i(9, 8))  # diagonal, not sharing a row or column

	rig.ease_to_attack_framing(shooter, target)
	rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION)

	var camera: Camera3D = rig.camera()
	var target_center: Vector3 = UnitGeometry.bounding_sphere(target).center
	var screen_pos: Vector2 = camera.unproject_position(target_center)
	var viewport_size: Vector2 = Vector2(rig.get_viewport().size)
	assert_almost_eq(screen_pos.x, viewport_size.x * 0.5, 1.0)
	assert_almost_eq(screen_pos.y, viewport_size.y * 0.5, 1.0)


## docs/10 taskblock04 A4: "mid-tween... the camera stays at least
## MIN_CLEARANCE from the shooter's bounding sphere for the whole
## transition" — orbiting a stable pivot (the target) can't sweep through
## the shooter the way lerping toward a point glued to the shooter's own
## position (Design 2) did.
func test_mid_tween_the_camera_never_gets_close_to_the_shooter() -> void:
	const MIN_CLEARANCE := 0.5
	var shooter := _make_unit(Vector2i(3, 1))
	var target := _make_unit(Vector2i(9, 5))
	var shooter_sphere: Dictionary = UnitGeometry.bounding_sphere(shooter)

	# A fresh rig per fraction (the tactical default is its own real
	# starting point) — `custom_step` advances a tween cumulatively from
	# wherever it already is, so a single rig stepped repeatedly would
	# measure the SUM of the fractions, not each one on its own.
	for fraction in [0.1, 0.25, 0.5, 0.75, 0.9]:
		var rig := CameraRig.new()
		add_child_autofree(rig)
		rig.ease_to_attack_framing(shooter, target)
		rig._active_tween.custom_step(CameraRig.ATTACK_TWEEN_DURATION * fraction)

		var camera_pos: Vector3 = rig.camera().global_transform.origin
		var clearance: float = (
			camera_pos.distance_to(shooter_sphere.center) - (shooter_sphere.radius as float)
		)
		assert_gt(
			clearance,
			MIN_CLEARANCE,
			"clearance %.2f at t=%.2f must not sweep through the shooter" % [clearance, fraction]
		)
