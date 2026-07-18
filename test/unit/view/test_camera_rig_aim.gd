extends GutTest

## taskblock-08 Pass B3: orbit lock (B3a) and the aim look-at/capped lean
## (B3b/B3c) — split out of test_camera_rig.gd purely to stay under
## gdlint's max-public-methods; same conventions.


func _rig() -> CameraRig:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.state.zoom = 10.0
	rig._apply_state()
	return rig


func test_start_aiming_locks_orbit_and_disables_zoom() -> void:
	var rig := _rig()

	rig.start_aiming()

	assert_true(rig.orbit_locked)
	assert_false(rig.zoom_enabled)


func test_stop_aiming_restores_orbit_and_zoom() -> void:
	var rig := _rig()
	rig.start_aiming()

	rig.stop_aiming()

	assert_false(rig.orbit_locked)
	assert_true(rig.zoom_enabled)


## B3a's own headless-testable half: a locked rig ignores a mouse-motion
## event entirely, before it ever reaches the (unfakeable in a headless
## test) `Input.is_mouse_button_pressed` check test_camera_rig.gd's own
## drag tests already flag as out of reach here.
func test_locked_orbit_ignores_motion_events_state_never_changes() -> void:
	var rig := _rig()
	rig.orbit_locked = true
	var before_yaw: float = rig.state.yaw
	var before_pan: Vector3 = rig.state.pan_offset

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50.0, 0.0)
	rig._unhandled_input(motion)

	assert_eq(rig.state.yaw, before_yaw)
	assert_eq(rig.state.pan_offset, before_pan)


## taskblock-08 B3a: the F "reset framing" key and orbit_locked together
## remove any way to move the pivots during aim — a stale look-at lean is
## the only thing left to clear, and stop_aiming() owns that.
func test_stop_aiming_clears_a_stale_camera_lean() -> void:
	var rig := _rig()
	rig.start_aiming()
	rig.aim_at(Vector3.ZERO, Vector3(5.0, 0.0, -5.0))
	assert_ne(rig.camera().rotation, Vector3.ZERO, "sanity: aim_at must have actually rotated it")

	rig.stop_aiming()

	assert_eq(rig.camera().rotation, Vector3.ZERO)


## taskblock-08 B3b/TESTS: "the camera's forward axis passes through (or
## within epsilon of) the window centre when the reticle is centred."
func test_aim_at_with_reticle_on_centre_points_dead_on_with_no_lean() -> void:
	var rig := _rig()
	var centre := Vector3.ZERO

	rig.aim_at(centre, centre)

	var camera: Camera3D = rig.camera()
	var forward: Vector3 = -camera.global_transform.basis.z
	var to_centre: Vector3 = (centre - camera.global_position).normalized()
	assert_almost_eq(forward.angle_to(to_centre), 0.0, 0.0001)


## taskblock-08 B3c/TESTS: "with the reticle at the window edge, the lean
## is non-zero but never exceeds MAX_LEAN_DEG."
func test_aim_at_caps_the_lean_toward_a_far_off_reticle() -> void:
	var rig := _rig()
	var centre := Vector3.ZERO
	# Camera sits near (0, 0, 10) (see _rig()); a reticle well off to the
	# side subtends an angle from centre far larger than the cap.
	var reticle := Vector3(5.0, 0.0, 0.0)

	rig.aim_at(centre, reticle)

	var camera: Camera3D = rig.camera()
	var forward: Vector3 = -camera.global_transform.basis.z
	var to_centre: Vector3 = (centre - camera.global_position).normalized()
	var to_reticle: Vector3 = (reticle - camera.global_position).normalized()
	var lean: float = forward.angle_to(to_centre)

	assert_gt(lean, 0.0, "the reticle must have tugged the look direction at all")
	assert_lte(
		lean, deg_to_rad(CameraRig.MAX_LEAN_DEG) + 0.0001, "the lean must never exceed the cap"
	)
	assert_lt(
		forward.angle_to(to_reticle),
		to_centre.angle_to(to_reticle),
		"the lean must move the forward axis TOWARD the reticle, not away from it"
	)


## taskblock-08 B3c/TESTS: "the lean is a pure function of reticle
## position (same reticle -> same lean, regardless of how the cursor got
## there)" — recomputed fresh from `centre` every call, never accumulated.
func test_aim_at_is_a_pure_function_of_centre_and_reticle() -> void:
	var rig := _rig()
	var centre := Vector3.ZERO
	var reticle := Vector3(3.0, 1.0, -1.0)

	rig.aim_at(centre, reticle)
	var first: Vector3 = rig.camera().rotation

	rig.aim_at(centre, Vector3(-4.0, 2.0, 0.5))  # a different reticle in between
	rig.aim_at(centre, reticle)  # back to the original
	var second: Vector3 = rig.camera().rotation

	assert_true(
		first.is_equal_approx(second), "same (centre, reticle) must always land on the same lean"
	)


## taskblock-08 B3b/TESTS: "framing position is the solved attack framing
## throughout" — aim_at() only ever touches the `_camera` node's own
## rotation, never `state`/the pivot chain the orbit solver owns.
func test_aim_at_never_touches_the_solved_pivot_state() -> void:
	var rig := _rig()
	var before_yaw: float = rig.state.yaw
	var before_pitch: float = rig.state.pitch
	var before_zoom: float = rig.state.zoom
	var before_pan: Vector3 = rig.state.pan_offset

	rig.aim_at(Vector3.ZERO, Vector3(2.0, 0.5, -3.0))

	assert_eq(rig.state.yaw, before_yaw)
	assert_eq(rig.state.pitch, before_pitch)
	assert_eq(rig.state.zoom, before_zoom)
	assert_eq(rig.state.pan_offset, before_pan)
