class_name CameraRig
extends Node3D

## docs/10: orbit + pan + zoom over the board, the default Tactical camera.
## A two-pivot rig — a yaw Node3D holding a pitch Node3D holding the
## Camera3D — so orbiting can never gimbal-lock: yaw only ever rotates
## around world Y, pitch only ever rotates around its own local X, and the
## two never combine into a single Euler triple that could flip. All the
## actual math (clamping, deltas) lives in CameraOrbitState — this Node is
## the thin shell docs/10 asks for: it only translates input events into
## state changes and state into transforms.

## docs/10 taskblock03 C1: how long easing to the attack camera's default
## framing takes — "ease (don't cut)," one constant, a flagged placeholder
## like every other un-pinned timing number in this view layer.
const ATTACK_TWEEN_DURATION := 0.4
## taskblock-08 B3c: the reticle lean's own cap, in degrees — capped in
## angle, not world distance, so the same cursor travel reads as the same
## lean regardless of how far away the target actually is. A flagged
## tuning number like every other visual-only constant here.
const MAX_LEAN_DEG := 5.0

var state := CameraOrbitState.new()
## docs/10: in the aim UI, scroll steps the dartboard layer instead of
## zooming (TacticsController clears this while aiming). Gated separately
## from `orbit_locked` below — this is about wheel meaning something else
## while aiming, not about the committed framing.
var zoom_enabled: bool = true
## taskblock-08 B3a: true while an action is armed/aiming — orbit and pan
## input are ignored outright. Reverses taskblock-04 A3's "keep orbit/pan/
## zoom live during aim": now that the camera also LOOKS at the dartboard
## (B3b/B3c), a live orbit would fight that every frame — aim is a
## committed framing now, inspection happens by backing out (Esc).
var orbit_locked: bool = false

var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D
var _active_tween: Tween

## taskblock-27 Pass D4: "the camera doesn't reset after aiming." Nothing
## snapshotted the pre-aim framing at all — `stop_aiming()` only ever
## cleared `_camera`'s own look-at lean, leaving `state.yaw/pitch/zoom/
## pan_offset` wherever `ease_to_attack_framing`'s own tween last eased
## them to. Taken the instant `start_aiming()` runs (before any framing
## change happens), so it's the real "where the player was looking right
## before this aim started," and eased back to (never a hard cut,
## matching every other camera transition in this rig) once aiming ends.
var _pre_aim_yaw: float = 0.0
var _pre_aim_pitch: float = 0.0
var _pre_aim_zoom: float = 0.0
var _pre_aim_pan_offset: Vector3 = Vector3.ZERO
var _has_pre_aim_snapshot: bool = false


func _ready() -> void:
	_yaw_pivot = Node3D.new()
	add_child(_yaw_pivot)

	_pitch_pivot = Node3D.new()
	_yaw_pivot.add_child(_pitch_pivot)

	_camera = Camera3D.new()
	# docs/10 taskblock05 B1: CameraOrbitState.CAMERA_FOV_DEG is the attack
	# solver's entire framing budget, but the real Camera3D never set `fov`
	# itself — it just relied on Godot's default happening to match. The
	# constant is authoritative now; whoever narrows the FOV for a tighter
	# shot later changes this one value and the solver stays honest instead
	# of silently drifting out of sync with a live camera nothing checked.
	_camera.fov = CameraOrbitState.CAMERA_FOV_DEG
	_pitch_pivot.add_child(_camera)

	_apply_state()


## taskblock-08 B3a: orbit and pan are ignored outright while
## `orbit_locked` (aiming). Reverses taskblock-04 A3's "keep orbit/pan/
## zoom live during aim" — now that the camera also LOOKS at the dartboard
## (B3b/B3c), live orbiting during aim would fight that every frame; aim
## is a committed framing now, inspection happens by backing out (Esc).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not orbit_locked:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_kill_active_tween()
			state.orbit(motion.relative)
			_apply_state()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_kill_active_tween()
			# docs/10 taskblock03 C3: Godot's mouse Y is down-positive; negate
			# it at this input boundary (ours to fix, not a Godot default) so
			# dragging down pans the field down instead of up. X is fine as
			# reported — left alone.
			state.pan(
				Vector2(motion.relative.x, -motion.relative.y),
				_yaw_pivot.transform.basis.x,
				_yaw_pivot.transform.basis.z
			)
			_apply_state()
	elif event is InputEventMouseButton and zoom_enabled:
		var button_event := event as InputEventMouseButton
		if not button_event.pressed:
			return
		if button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_kill_active_tween()
			state.zoom_in()
			_apply_state()
		elif button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_kill_active_tween()
			state.zoom_out()
			_apply_state()


## Recenters the orbit pivot on a world point (e.g. a board's center, or a
## unit's cell) without disturbing the current yaw/pitch/zoom.
func center_on(world_position: Vector3) -> void:
	state.pan_offset = world_position
	_apply_state()


## docs/10 taskblock04 A: eases (never cuts) to the attack camera's own
## solved framing, on entering aim. Live input can still interrupt the
## EASE itself via `_kill_active_tween` (a stray orbit/pan mid-tween
## doesn't fight it for the rest of its duration) — moot once
## `orbit_locked` is set (B3a), since nothing reaches `state.orbit`/
## `state.pan` anymore, but harmless: an already-queued ease still lands.
##
## `shooter_sphere`/`target_sphere` are `{center, radius}` Dictionaries
## (`UnitGeometry.bounding_sphere()`/`bounding_sphere_for_part()`), not raw
## Units — the solver needs each side's ACTUAL bounding sphere, never a
## hardcoded body size, so a giant enemy still gets a correct framing with
## no special-casing here; tb32 Pass C moved the sphere computation to the
## caller so a non-unit target (a wall/cover/downed object,
## `bounding_sphere_for_part`) frames exactly the same way a Unit does,
## with this function staying completely decoupled from which kind of
## thing it's framing.
func ease_to_attack_framing(shooter_sphere: Dictionary, target_sphere: Dictionary) -> void:
	var framing: Dictionary = state.attack_framing(shooter_sphere, target_sphere)
	_ease_to(framing.yaw, framing.pitch, framing.zoom, framing.pan_offset)


## tb34 Pass D: the real entry point for entering aim — picks between the
## two framings by distance (`CameraOrbitState.SNIPER_FRAME_DISTANCE`, a
## tunable, never a literal here), then eases through the exact same
## shared tween `ease_to_attack_framing` itself uses (`_ease_to`), never a
## second easing path. `ease_to_attack_framing` stays the plain, always-
## over-the-shoulder primitive underneath — every existing caller/test of
## it is unaffected; this is a new, additional entry point, not a
## replacement.
func ease_to_framing(
	shooter_sphere: Dictionary, target_sphere: Dictionary, distance_cells: int
) -> void:
	var framing: Dictionary = (
		state.sniper_framing(target_sphere)
		if distance_cells > CameraOrbitState.SNIPER_FRAME_DISTANCE
		else state.attack_framing(shooter_sphere, target_sphere)
	)
	_ease_to(framing.yaw, framing.pitch, framing.zoom, framing.pan_offset)


## taskblock-27 Pass D4: the shared tween both `ease_to_attack_framing`
## and `stop_aiming`'s own restore now drive — factored out so "ease to
## some target framing" is one real implementation, not two copies that
## could quietly drift apart.
func _ease_to(
	target_yaw: float, target_pitch: float, target_zoom: float, target_pan: Vector3
) -> void:
	var from_yaw: float = state.yaw
	var from_pitch: float = state.pitch
	var from_zoom: float = state.zoom
	var from_pan: Vector3 = state.pan_offset

	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.tween_method(
		func(t: float) -> void:
			state.yaw = lerp_angle(from_yaw, target_yaw, t)
			state.pitch = lerpf(from_pitch, target_pitch, t)
			state.zoom = lerpf(from_zoom, target_zoom, t)
			state.pan_offset = from_pan.lerp(target_pan, t)
			_apply_state(),
		0.0,
		1.0,
		ATTACK_TWEEN_DURATION
	)


## taskblock-08 B3a: locks orbit/pan/zoom the instant an action is armed —
## called once, from TacticsController.arm_action(), before the shooter's
## own attack framing starts easing in, so there's never a frame where the
## old live-orbit framing was still interactive.
func start_aiming() -> void:
	# taskblock-27 Pass D4: snapshot BEFORE anything about the framing
	# changes — the real pre-aim camera state `stop_aiming()` eases back
	# to once aiming ends.
	_pre_aim_yaw = state.yaw
	_pre_aim_pitch = state.pitch
	_pre_aim_zoom = state.zoom
	_pre_aim_pan_offset = state.pan_offset
	_has_pre_aim_snapshot = true
	orbit_locked = true
	zoom_enabled = false


## Restores full camera control and clears whatever look-at lean B3b/B3c
## left on the `_camera` node's own rotation — outside aim mode the camera
## always looks straight down the pivot chain (`_apply_state`'s own
## implicit contract: `_camera`'s rotation is never touched there), never
## a stale lean surviving from the last aimed shot.
##
## taskblock-27 Pass D4: "the camera doesn't reset after aiming" — eases
## the pivot chain itself (yaw/pitch/zoom/pan) back to whatever
## `start_aiming()` snapshotted, never leaving it at the attack framing's
## own eased-to position. `_has_pre_aim_snapshot` guards a `stop_aiming()`
## called with no matching `start_aiming()` (defensive; every real caller
## pairs them, but this is cheap insurance against reverting to a stale
## zero-value snapshot).
func stop_aiming() -> void:
	orbit_locked = false
	zoom_enabled = true
	_camera.rotation = Vector3.ZERO
	if _has_pre_aim_snapshot:
		_has_pre_aim_snapshot = false
		_ease_to(_pre_aim_yaw, _pre_aim_pitch, _pre_aim_zoom, _pre_aim_pan_offset)


## taskblock-08 B3b/B3c: "position camera with orbit, then camera's own
## rotation to point it at the center of the dartboard on the window."
## Position and look-direction live on different nodes so they can never
## fight: the pivot chain (`_yaw_pivot`/`_pitch_pivot`, `state.*`) owns
## WHERE the camera is — untouched here, still the solved attack framing —
## this owns WHERE it points, on `_camera`'s own local rotation alone.
##
## `centre` anchors the look (the window's own centre, `AimPlaneGeometry.
## world_point(shooter, target, Vector2.ZERO)` — the honest version, a
## real world point the same geometry already produces, not a fake).
## `reticle_point` then tugs it by up to `MAX_LEAN_DEG`, capped in ANGLE
## (never world distance, which would swing wildly for a near target and
## barely move for a far one for the same cursor travel) — driven by the
## reticle's own resolved position, never raw mouse motion, so `orbit_
## locked` never has a backdoor. Recomputed fresh from `centre` every
## call (never accumulated), so the lean is a pure function of where the
## reticle currently is — same reticle, same lean, regardless of how the
## cursor got there.
func aim_at(centre: Vector3, reticle_point: Vector3) -> void:
	_camera.look_at(centre, Vector3.UP)
	var to_reticle: Vector3 = reticle_point - _camera.global_position
	if to_reticle.is_zero_approx():
		return
	var forward: Vector3 = -_camera.global_transform.basis.z
	var desired: Vector3 = to_reticle.normalized()
	var angle: float = forward.angle_to(desired)
	if angle < 0.0001:
		return
	var axis: Vector3 = forward.cross(desired)
	if axis.is_zero_approx():
		return
	var lean: float = minf(angle, deg_to_rad(MAX_LEAN_DEG))
	var leaned_forward: Vector3 = forward.rotated(axis.normalized(), lean)
	_camera.look_at(_camera.global_position + leaned_forward, Vector3.UP)


func _kill_active_tween() -> void:
	if _active_tween != null:
		_active_tween.kill()
		_active_tween = null


## The actual Camera3D — for anything that needs to cast a ray through it
## (docs/10 Phase 12.2's board picking), never for anything that would
## bypass CameraOrbitState to move it directly.
func camera() -> Camera3D:
	return _camera


func _apply_state() -> void:
	_yaw_pivot.position = state.pan_offset
	_yaw_pivot.rotation.y = state.yaw
	_pitch_pivot.rotation.x = state.pitch
	_camera.position = Vector3(0.0, 0.0, state.zoom)
