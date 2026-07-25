extends GutTest

## docs/10: every camera clamp/delta lives in pure, headless-testable math —
## CameraRig (the Node) is a thin shell over this.

## taskblock-40 Pass B3: "measure before changing anything." The shared
## height-delta matrix (shooter fixed at the origin, target displaced
## vertically at a fixed horizontal offset) every Pass B test below runs
## through the REAL solver internals (`_solve_back`/`_both_fit`, the exact
## functions `attack_framing` itself calls — not a reconstruction from the
## returned {yaw, pitch, zoom} via trig round-trip, which loses enough
## precision right at the fit boundary the solver deliberately lands on to
## read as a false failure that was never real; verified against a raw
## non-reconstructed camera_pos before writing this down as the real test).
const HEIGHT_DELTAS: Array[float] = [-6.0, -3.0, -1.0, 0.0, 1.0, 3.0, 6.0]


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


## Reconstructs the rig's own look direction (the camera's OWN forward)
## from {yaw, pitch} — the exact relationship verified against a real
## Camera3D in scratchpad diag_lookat.gd (docs/10 taskblock03 C1):
## pitch alone sets the vertical component (`sin(pitch)`, independent of
## yaw, since pitch is the second rotation and always applied around the
## already-yawed frame's own horizontal local X); yaw alone sets the
## horizontal angle.
func _look_dir(yaw: float, pitch: float) -> Vector3:
	var horiz: float = cos(pitch)
	return Vector3(-sin(yaw) * horiz, sin(pitch), -cos(yaw) * horiz)


## docs/10 taskblock04 A3: the rig's camera sits at local (0,0,zoom) from
## its pivot with no rotation of its own, so its world position is always
## `pivot - zoom * (the camera's own forward)` — the offset direction is
## exactly opposite the look direction. Reconstructs the actual camera
## position from a framing Dictionary the same way CameraRig._apply_state()
## would place it, without needing a live Node3D.
func _camera_pos(framing: Dictionary) -> Vector3:
	var look: Vector3 = _look_dir(framing.yaw, framing.pitch)
	return (framing.pan_offset as Vector3) - look * (framing.zoom as float)


func _sphere(center: Vector3, radius: float) -> Dictionary:
	return {"center": center, "radius": radius}


## Independent of CameraOrbitState's own private fit check — this is the
## actual acceptance criterion (taskblock04 A4): does the sphere's whole
## silhouette (its center's angle off the look direction, plus the
## half-angle its own radius subtends) land inside the usable half-FOV.
func _fits(camera_pos: Vector3, look: Vector3, sphere: Dictionary) -> bool:
	var usable_half_fov: float = (
		deg_to_rad(CameraOrbitState.CAMERA_FOV_DEG * 0.5) * CameraOrbitState.ATTACK_MARGIN
	)
	var offset: Vector3 = (sphere.center as Vector3) - camera_pos
	var distance: float = offset.length()
	if distance <= (sphere.radius as float):
		return true
	var angle_to_centre: float = look.angle_to(offset.normalized())
	var half_angle: float = asin(clampf((sphere.radius as float) / distance, 0.0, 1.0))
	return angle_to_centre + half_angle <= usable_half_fov


## docs/10 taskblock04 A2: "show the entire shooter (or a good portion),
## while the entire target is also visible" — checked across adjacent,
## mid-range, far, and diagonal (non-coplanar) pairs, not just the one
## geometry the original hand-derived formula happened to be tested against.
func test_attack_framing_fits_both_bodies_across_a_range_of_distances_and_angles() -> void:
	var state := CameraOrbitState.new()
	var pairs := [
		[Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 6.0)],
		[Vector3(0.0, 0.0, 0.0), Vector3(14.0, 0.0, 14.0)],
		[Vector3(3.0, 0.0, 5.0), Vector3(-2.0, 0.0, -4.0)],
	]
	for pair: Array in pairs:
		var shooter: Dictionary = _sphere(pair[0], 0.4)
		var target: Dictionary = _sphere(pair[1], 0.4)

		var framing: Dictionary = state.attack_framing(shooter, target)
		var camera_pos: Vector3 = _camera_pos(framing)
		var look: Vector3 = _look_dir(framing.yaw, framing.pitch)

		assert_true(_fits(camera_pos, look, shooter), "shooter must fit: %s" % [pair])
		assert_true(_fits(camera_pos, look, target), "target must fit: %s" % [pair])


## The check that would have caught Design 2's missing "back" axis on day
## one: the shooter has to actually sit in front of the camera, not
## somewhere the lens is pointed away from.
func test_attack_framing_keeps_the_shooter_in_front_of_the_camera() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3(2.0, 0.0, 3.0), 0.4)
	var target: Dictionary = _sphere(Vector3(9.0, 0.0, 8.0), 0.4)

	var framing: Dictionary = state.attack_framing(shooter, target)
	var camera_pos: Vector3 = _camera_pos(framing)
	var look: Vector3 = _look_dir(framing.yaw, framing.pitch)

	assert_gt(
		look.dot((shooter.center as Vector3) - camera_pos),
		0.0,
		"the shooter must sit in front of the camera, not behind it"
	)


func test_attack_framing_solves_a_larger_back_for_a_giant_target() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3(0.0, 0.0, 0.0), 0.4)
	var target_pos := Vector3(0.0, 0.0, 6.0)

	var standard: Dictionary = state.attack_framing(shooter, _sphere(target_pos, 0.4))
	# Large enough that the TARGET's own radius, not the shooter's fixed
	# 0.4, is what ends up driving the solve — a modestly bigger radius
	# can still fit "for free" under whatever BACK the shooter alone
	# already forces, which would make this comparison a false pass.
	var giant: Dictionary = state.attack_framing(shooter, _sphere(target_pos, 15.0))

	assert_gt(
		_camera_pos(giant).distance_to(shooter.center),
		_camera_pos(standard).distance_to(shooter.center),
		"a giant target must push the camera back further to still fit"
	)


## "The solver returns the smallest qualifying BACK" — nudging the solved
## camera a little closer along the shot line must break the fit for at
## least one sphere, or the solve wasn't actually minimal.
func test_attack_framing_returns_the_smallest_qualifying_back() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3(0.0, 0.0, 0.0), 0.4)
	var target: Dictionary = _sphere(Vector3(0.0, 0.0, 6.0), 0.4)

	var framing: Dictionary = state.attack_framing(shooter, target)
	var camera_pos: Vector3 = _camera_pos(framing)
	assert_true(_fits(camera_pos, _look_dir(framing.yaw, framing.pitch), shooter))
	assert_true(_fits(camera_pos, _look_dir(framing.yaw, framing.pitch), target))

	var to_target := (
		Vector2(
			(target.center as Vector3).x - (shooter.center as Vector3).x,
			(target.center as Vector3).z - (shooter.center as Vector3).z
		)
		. normalized()
	)
	var closer_pos: Vector3 = camera_pos + Vector3(to_target.x, 0.0, to_target.y) * 0.05
	var closer_look: Vector3 = ((target.center as Vector3) - closer_pos).normalized()
	assert_false(
		_fits(closer_pos, closer_look, shooter) and _fits(closer_pos, closer_look, target),
		"a camera nudged closer along the shot line must break the fit — BACK was already minimal"
	)


func test_attack_framing_falls_back_when_shooter_and_target_share_a_cell() -> void:
	var state := CameraOrbitState.new()
	state.yaw = 1.75
	state.pitch = -0.4
	var same_point: Dictionary = _sphere(Vector3(4.0, 0.0, 4.0), 0.4)

	var framing: Dictionary = state.attack_framing(same_point, same_point)

	assert_almost_eq(framing.yaw, 1.75, 0.0001, "no direction to face: leave yaw where it was")
	assert_almost_eq(framing.pitch, CameraOrbitState.ATTACK_PITCH, 0.0001)


## docs/10 taskblock04 A3: "orbit around the TARGET — this kills the tween
## glitch at the source." The pivot is the target's own bounding-sphere
## center, and zoom is a real orbit distance — never Design 2's `zoom = 0`
## "camera glued to a literal point" hack.
func test_attack_framing_orbits_the_target_not_a_literal_point() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3(2.0, 0.0, 3.0), 0.4)
	var target: Dictionary = _sphere(Vector3(9.0, 0.0, 3.0), 0.4)

	var framing: Dictionary = state.attack_framing(shooter, target)

	assert_eq(framing.pan_offset, target.center, "the pivot is the target's own bounding sphere")
	assert_gt(framing.zoom, 0.0, "a real orbit distance, not the zoom=0 look-at hack")


func test_attack_framing_is_deterministic() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3(0.0, 0.0, 0.0), 0.4)
	var target: Dictionary = _sphere(Vector3(5.0, 0.0, 0.0), 0.4)

	var a: Dictionary = state.attack_framing(shooter, target)
	var b: Dictionary = state.attack_framing(shooter, target)

	assert_eq(a.yaw, b.yaw)
	assert_eq(a.pitch, b.pitch)
	assert_eq(a.zoom, b.zoom)
	assert_eq(a.pan_offset, b.pan_offset)


## tb34 Pass D: "frame the target, not shooter-over-shoulder." The
## structural reason sniper_framing always centers the target regardless
## of yaw/pitch: the pivot IS the target's own center, full stop -- no
## shooter-relative offset anywhere in it, unlike attack_framing's own
## `pan_offset == target.center` (true there too, but only PART of why
## that one centers; attack_framing's camera_pos is also shooter-relative).
func test_sniper_framing_pans_directly_on_the_targets_own_center() -> void:
	var state := CameraOrbitState.new()
	var target: Dictionary = _sphere(Vector3(9.0, 0.0, 3.0), 0.6)

	var framing: Dictionary = state.sniper_framing(target)

	assert_eq(framing.pan_offset, target.center)
	assert_gt(framing.zoom, 0.0, "a real orbit distance, not a zero-distance look-at")


## docs/10 taskblock04 A2's own acceptance criterion, reused here for the
## single-sphere case: the target's whole silhouette (its center's angle
## off the look direction -- zero here, since pan_offset IS its center --
## plus the half-angle its own radius subtends) must land inside the
## usable half-FOV, across a range of radii.
func test_sniper_framing_fits_the_targets_own_sphere_across_a_range_of_radii() -> void:
	var state := CameraOrbitState.new()
	state.yaw = 0.7
	state.pitch = -0.3
	for radius in [0.2, 0.5, 1.0, 3.0, 8.0]:
		var target: Dictionary = _sphere(Vector3(4.0, 0.0, -2.0), radius)
		var framing: Dictionary = state.sniper_framing(target)
		var camera_pos: Vector3 = _camera_pos(framing)
		var look: Vector3 = _look_dir(framing.yaw, framing.pitch)
		assert_true(
			_fits(camera_pos, look, target), "radius %.1f must fit the usable half-FOV" % radius
		)


## With no second body to keep in frame, any viewing angle already centers
## the target -- so, unlike attack_framing (which SOLVES a new yaw/pitch
## from the shooter->target line), this keeps whatever the rig's current
## orbit angle already is.
func test_sniper_framing_keeps_the_current_yaw_and_pitch() -> void:
	var state := CameraOrbitState.new()
	state.yaw = 1.23
	state.pitch = -0.8
	var target: Dictionary = _sphere(Vector3(9.0, 0.0, 3.0), 0.6)

	var framing: Dictionary = state.sniper_framing(target)

	assert_eq(framing.yaw, 1.23)
	assert_eq(framing.pitch, -0.8)


func test_sniper_framing_is_deterministic() -> void:
	var state := CameraOrbitState.new()
	var target: Dictionary = _sphere(Vector3(5.0, 0.0, 0.0), 0.4)

	var a: Dictionary = state.sniper_framing(target)
	var b: Dictionary = state.sniper_framing(target)

	assert_eq(a.yaw, b.yaw)
	assert_eq(a.pitch, b.pitch)
	assert_eq(a.zoom, b.zoom)
	assert_eq(a.pan_offset, b.pan_offset)


func test_pass_b_height_delta_matrix_always_fits_and_never_drops_below_the_lower_body() -> void:
	var state := CameraOrbitState.new()
	var to_target := Vector2(3.0, 0.0)
	var dir: Vector2 = to_target.normalized()
	var right := Vector2(-dir.y, dir.x)
	var usable_half_fov: float = (
		deg_to_rad(CameraOrbitState.CAMERA_FOV_DEG * 0.5) * CameraOrbitState.ATTACK_MARGIN
	)
	print("tb40 Pass B3 attack_framing height-delta matrix (horizontal dist 3, radius 0.4):")
	print("  delta | back    | zoom    | cam.y | vert_angle_deg | both_fit | cam_below_lower_body")
	for delta: float in HEIGHT_DELTAS:
		var shooter: Dictionary = _sphere(Vector3.ZERO, 0.4)
		var target: Dictionary = _sphere(Vector3(3.0, delta, 0.0), 0.4)
		var back: float = state._solve_back(
			shooter.center, shooter.radius, target.center, target.radius, dir, right
		)
		var both_fit: bool = state._both_fit(
			shooter.center,
			shooter.radius,
			target.center,
			target.radius,
			dir,
			right,
			back,
			usable_half_fov
		)
		var camera_pos: Vector3 = (
			(shooter.center as Vector3)
			- Vector3(dir.x, 0.0, dir.y) * back
			+ Vector3(right.x, 0.0, right.y) * CameraOrbitState.ATTACK_RIGHT_OFFSET
			+ Vector3(0.0, CameraOrbitState.ATTACK_UP_OFFSET, 0.0)
		)
		var look_dir: Vector3 = ((target.center as Vector3) - camera_pos).normalized()
		var vert_angle_deg: float = rad_to_deg(asin(clampf(look_dir.y, -1.0, 1.0)))
		var lower_y: float = minf((shooter.center as Vector3).y, (target.center as Vector3).y)
		var below_lower: bool = camera_pos.y < lower_y
		print(
			(
				"  %5.1f | %7.3f | %7.3f | %5.2f | %14.2f | %8s | %s"
				% [
					delta,
					back,
					camera_pos.distance_to(target.center),
					camera_pos.y,
					vert_angle_deg,
					both_fit,
					below_lower
				]
			)
		)
		assert_true(both_fit, "both bodies must fit at height delta %s" % delta)
		assert_false(below_lower, "camera must never sit below the lower body at delta %s" % delta)


## The regression guard taskblock-40 Pass B itself calls "the important
## one": pins the exact same-level solve so a later change to the
## height-anchoring formula (if Pass B4 ever lands one) is provably a
## no-op when shooter and target share a level — most of the game is
## still played on one level. Values captured from the real solver, not
## hand-derived.
func test_pass_b_same_level_solve_is_pinned_as_a_regression_guard() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3.ZERO, 0.4)
	var target: Dictionary = _sphere(Vector3(3.0, 0.0, 0.0), 0.4)

	var framing: Dictionary = state.attack_framing(shooter, target)

	assert_almost_eq(framing.yaw as float, -1.379556, 0.0001)
	assert_almost_eq(framing.pitch as float, -0.126046, 0.0001)
	assert_almost_eq(framing.zoom as float, 4.772782, 0.0001)
	assert_eq(framing.pan_offset as Vector3, target.center)


## taskblock-40 Pass B: `sniper_framing` never even reads a shooter, so
## `pan_offset == target.center` (Y included) holds at any height by
## construction, not by height-specific logic -- checked across the same
## matrix anyway since it's explicitly named in the taskblock's own
## acceptance, not assumed from the structural argument alone.
func test_pass_b_sniper_framing_centers_the_target_at_any_height() -> void:
	var state := CameraOrbitState.new()
	for delta: float in HEIGHT_DELTAS:
		var target: Dictionary = _sphere(Vector3(3.0, delta, 0.0), 0.4)
		var framing: Dictionary = state.sniper_framing(target)
		assert_eq(
			framing.pan_offset as Vector3, target.center, "must center target at delta %s" % delta
		)


## taskblock-40 Pass B3: continuity across the delta-crosses-zero seam --
## fine-grained sampling either side of zero must show no jump, since
## `attack_framing` has no explicit height branch (the whole solve is
## uniform 3D algebra) and shouldn't accidentally grow one.
func test_pass_b_solved_framing_is_continuous_across_the_zero_height_crossing() -> void:
	var state := CameraOrbitState.new()
	var shooter: Dictionary = _sphere(Vector3.ZERO, 0.4)
	var previous: Dictionary = {}
	var step := 0.01
	for i in range(-5, 6):
		var delta: float = i * step
		var target: Dictionary = _sphere(Vector3(3.0, delta, 0.0), 0.4)
		var framing: Dictionary = state.attack_framing(shooter, target)
		if not previous.is_empty():
			assert_almost_eq(
				framing.zoom as float,
				previous.zoom as float,
				0.05,
				"zoom must not jump crossing delta %s" % delta
			)
			assert_almost_eq(
				framing.pitch as float,
				previous.pitch as float,
				0.05,
				"pitch must not jump crossing delta %s" % delta
			)
		previous = framing
