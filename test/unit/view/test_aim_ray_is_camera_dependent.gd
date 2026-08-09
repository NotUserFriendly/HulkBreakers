extends GutTest

## tb61 (`BR51.01`): **the reproduction this entry has never had.**
##
## The entry names its mechanism — `CameraRig.aim_at` rotates the real `Camera3D` toward the
## reticle by up to `MAX_LEAN_DEG`, and `TacticsController` casts the cursor ray through that same
## camera — but nothing has ever measured the consequence, and the one measurement that was taken
## came back clean at 0.0000 cells because it compared the reticle against the *other consumer of
## the same ray*. **Two readers of one wrong ray agree with each other and with nothing else.**
##
## So this compares against the thing that actually changed: **the same screen pixel, before and
## after the camera leans.** Per `CLAUDE.md`'s view-math rule it builds the real node, applies the
## real state, and reads the result back out — it never re-derives a projection.
##
## ## The loop, for a reader who has not seen the entry
##
## 1. `TacticsController.aim_reticle_at_screen` casts `camera.project_ray_origin/normal`
## 2. `AimPlaneGeometry.aim_point_from_ray` turns that into an aim-plane point
## 3. `reticle_offset` — **what the shot resolves against** — is that point minus centre mass
## 4. `AimView` hands the resulting reticle point back to `CameraRig.aim_at`, which rotates the
##    camera toward it
##
## and the next mouse motion re-enters at (1) through the rotated camera.

const SHOOTER_CELL := Vector2i(4, 4)
const TARGET_CELL := Vector2i(12, 4)


func _rig() -> CameraRig:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.state.zoom = 12.0
	rig.state.pan_offset = Vector3(8.0, 0.0, 4.0)
	rig._apply_state()
	return rig


## The aim-plane point a given screen pixel currently resolves to, through whatever pose the
## camera is in right now. **Read off the real camera**, not computed from a stored basis.
func _aim_point_for(camera: Camera3D, screen_pos: Vector2) -> Variant:
	return AimPlaneGeometry.aim_point_from_ray(
		SHOOTER_CELL,
		TARGET_CELL,
		camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos)
	)


## **The defect, measured.** Hold the cursor perfectly still; lean the camera the way aiming does;
## ask the same pixel where it points. It answers differently — and that difference is a real
## displacement of the point the shot resolves against.
func test_the_same_pixel_resolves_elsewhere_once_the_camera_leans() -> void:
	var rig: CameraRig = _rig()
	var camera: Camera3D = rig.camera()
	var centre: Vector3 = AimPlaneGeometry.world_point(SHOOTER_CELL, TARGET_CELL, Vector2.ZERO)

	# Un-leaned: the camera simply looks at the window centre.
	camera.look_at(centre, Vector3.UP)
	var screen_pos: Vector2 = camera.unproject_position(centre)
	var before: Variant = _aim_point_for(camera, screen_pos)
	assert_true(before is Vector2, "sanity: the pixel resolves onto the aim plane at all")
	if not (before is Vector2):
		return

	# Now lean toward a reticle offset to one side, exactly as `AimView` does every frame the
	# cursor moves. The reticle point is the same geometry `AimView` feeds in.
	var reticle_point: Vector3 = AimPlaneGeometry.world_point(
		SHOOTER_CELL, TARGET_CELL, Vector2(1.5, 0.0)
	)
	rig.aim_at(centre, reticle_point)

	var after: Variant = _aim_point_for(camera, screen_pos)
	assert_true(after is Vector2, "sanity: it still resolves onto the plane after the lean")
	if not (after is Vector2):
		return

	var shift: float = (after as Vector2).distance_to(before as Vector2)
	gut.p(
		(
			"same pixel %s: before %+.4f,%+.4f  after %+.4f,%+.4f  shift %.4f cells"
			% [
				str(screen_pos),
				(before as Vector2).x,
				(before as Vector2).y,
				(after as Vector2).x,
				(after as Vector2).y,
				shift
			]
		)
	)
	assert_gt(
		shift,
		0.05,
		(
			"BR51.01: a stationary cursor resolves to a different aim point once the camera "
			+ "leans, so the shot resolves against a point the player did not choose"
		)
	)


## **It is bounded, not compounding — the open question the entry asks.**
##
## `aim_at` calls `look_at(centre)` *before* leaning, so every frame's lean is computed from the
## un-leaned pose rather than from the previous lean. Repeating the cycle therefore converges
## instead of walking away, which is what makes this a systematic offset rather than drift.
##
## **This matters for the fix, not just for the description**: a compounding error would need the
## loop broken, while a bounded one needs the cursor's meaning anchored to something the camera
## does not move.
func test_the_offset_is_bounded_rather_than_compounding() -> void:
	var rig: CameraRig = _rig()
	var camera: Camera3D = rig.camera()
	var centre: Vector3 = AimPlaneGeometry.world_point(SHOOTER_CELL, TARGET_CELL, Vector2.ZERO)
	camera.look_at(centre, Vector3.UP)
	var screen_pos: Vector2 = camera.unproject_position(centre)

	var readings: Array[Vector2] = []
	for _iteration: int in range(6):
		var point: Variant = _aim_point_for(camera, screen_pos)
		if not (point is Vector2):
			break
		readings.append(point as Vector2)
		rig.aim_at(
			centre, AimPlaneGeometry.world_point(SHOOTER_CELL, TARGET_CELL, point as Vector2)
		)

	assert_gt(readings.size(), 3, "sanity: the cycle ran")
	var last_step: float = readings[-1].distance_to(readings[-2])
	var first_step: float = readings[1].distance_to(readings[0])
	gut.p(
		(
			"first step %.5f cells, last step %.5f cells over %d iterations"
			% [first_step, last_step, readings.size()]
		)
	)
	assert_lte(
		last_step,
		first_step + 0.0001,
		"the cycle must not walk away — aim_at re-bases on look_at(centre) every call"
	)


## **The un-leaned camera is not the fix, and this records why rather than leaving it to be
## re-proposed.** Projecting through an un-leaned basis makes the numbers agree again, but the
## cursor's meaning still depends on a camera pose — so the next flourish that moves the camera
## reintroduces the same class of defect. The supervisor's specification is that the cursor should
## resolve to **a point on a part**, which does not move when the camera does.
func test_un_leaning_hides_the_symptom_without_removing_the_dependency() -> void:
	var rig: CameraRig = _rig()
	var camera: Camera3D = rig.camera()
	var centre: Vector3 = AimPlaneGeometry.world_point(SHOOTER_CELL, TARGET_CELL, Vector2.ZERO)
	camera.look_at(centre, Vector3.UP)
	var screen_pos: Vector2 = camera.unproject_position(centre)
	var before: Variant = _aim_point_for(camera, screen_pos)

	# Lean, then restore the un-leaned pose the way an "un-lean the projection" fix would.
	rig.aim_at(centre, AimPlaneGeometry.world_point(SHOOTER_CELL, TARGET_CELL, Vector2(1.5, 0.0)))
	camera.look_at(centre, Vector3.UP)
	var restored: Variant = _aim_point_for(camera, screen_pos)

	assert_true(before is Vector2 and restored is Vector2)
	if not (before is Vector2 and restored is Vector2):
		return
	assert_almost_eq(
		(restored as Vector2).distance_to(before as Vector2),
		0.0,
		0.0001,
		"un-leaning restores the old answer — which is why it looks like a fix and is not one"
	)
