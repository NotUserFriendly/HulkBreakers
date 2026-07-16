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
## runNotes.md: "third person camera needs to be locked" while aiming — the
## live-orbit default (docs/10 taskblock03 C2) let the player rotate the
## camera away from the shot direction, at which point the reticle drag's
## screen-space -> shot-plane mapping (a fixed assumption that screen-right
## is shot-plane-lateral-right) silently stopped matching what was on
## screen — the actual cause of "lost the dartboard, can't aim at
## anything." Set by TacticsController on entering/leaving aim; while true,
## every live input branch below is ignored outright.
var locked: bool = false

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
	_pitch_pivot.add_child(_camera)

	_apply_state()


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
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


## docs/10 taskblock03 C1 (runNotes.md follow-up): eases (never cuts) to the
## attack camera's own over-the-shoulder framing — on entering aim, and
## again on the F "reset framing" key, which is the identical target
## framing, just a different trigger. Live input can still interrupt the
## EASE itself via `_kill_active_tween` (so a stray input mid-tween doesn't
## fight it for the rest of its duration) — but once `locked` is set
## (TacticsController does this for the whole of aim mode), `_unhandled_
## input` never reads live input again in the first place, so there is
## nothing left to interrupt with once the ease finishes.
func ease_to_attack_framing(shooter_pos: Vector3, target_pos: Vector3) -> void:
	var target: Dictionary = state.attack_framing(shooter_pos, target_pos)
	var from_yaw: float = state.yaw
	var from_pitch: float = state.pitch
	var from_zoom: float = state.zoom
	var from_pan: Vector3 = state.pan_offset

	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.tween_method(
		func(t: float) -> void:
			state.yaw = lerp_angle(from_yaw, target.yaw, t)
			state.pitch = lerpf(from_pitch, target.pitch, t)
			state.zoom = lerpf(from_zoom, target.zoom, t)
			state.pan_offset = from_pan.lerp(target.pan_offset, t)
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
