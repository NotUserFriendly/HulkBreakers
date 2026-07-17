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

var state := CameraOrbitState.new()
## docs/10: in the aim UI, scroll steps the dartboard layer instead of
## zooming (TacticsController clears this while aiming). Orbit/pan stay
## live either way — only wheel-zoom is gated.
var zoom_enabled: bool = true

var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D
var _active_tween: Tween


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


## docs/10 taskblock04 A3: "keep orbit/pan/zoom live during aim" — now that
## the attack camera orbits a stable pivot (the target, `attack_framing()`)
## instead of sitting at a literal computed point, live orbiting during aim
## just swings the same inspection camera taskblock-03 C2 already wants,
## rather than breaking anything. The old `locked` flag existed only
## because the reticle's screen-to-shot-plane mapping used to assume a
## fixed camera angle (docs/10 taskblock04's own aim-plane raycast fixed
## that separately) — removed as dead weight once that reason was gone.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
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
## solved framing — on entering aim, and again on the F "reset framing"
## key, which is the identical target framing, just a different trigger.
## Live input can still interrupt the EASE itself via `_kill_active_tween`
## (a stray orbit/pan mid-tween doesn't fight it for the rest of its
## duration) — orbiting after it settles is expected now (A3: "keep
## orbit/pan/zoom live during aim"), not something to block.
##
## `shooter`/`target` are `Unit`s, not raw positions — the solver needs
## each unit's ACTUAL bounding sphere (UnitGeometry.bounding_sphere()),
## never a hardcoded body size, so a giant enemy still gets a correct
## framing with no special-casing here.
func ease_to_attack_framing(shooter: Unit, target: Unit) -> void:
	var framing: Dictionary = state.attack_framing(
		UnitGeometry.bounding_sphere(shooter), UnitGeometry.bounding_sphere(target)
	)
	var from_yaw: float = state.yaw
	var from_pitch: float = state.pitch
	var from_zoom: float = state.zoom
	var from_pan: Vector3 = state.pan_offset

	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.tween_method(
		func(t: float) -> void:
			state.yaw = lerp_angle(from_yaw, framing.yaw, t)
			state.pitch = lerpf(from_pitch, framing.pitch, t)
			state.zoom = lerpf(from_zoom, framing.zoom, t)
			state.pan_offset = from_pan.lerp(framing.pan_offset, t)
			_apply_state(),
		0.0,
		1.0,
		ATTACK_TWEEN_DURATION
	)


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
