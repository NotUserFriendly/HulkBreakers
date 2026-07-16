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

var state := CameraOrbitState.new()
## docs/10: in the aim UI, scroll steps the dartboard layer instead of
## zooming (TacticsController clears this while aiming). Orbit/pan stay
## live either way — only wheel-zoom is gated.
var zoom_enabled: bool = true

var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D


func _ready() -> void:
	_yaw_pivot = Node3D.new()
	add_child(_yaw_pivot)

	_pitch_pivot = Node3D.new()
	_yaw_pivot.add_child(_pitch_pivot)

	_camera = Camera3D.new()
	_pitch_pivot.add_child(_camera)

	_apply_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			state.orbit(motion.relative)
			_apply_state()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			state.pan(motion.relative, _yaw_pivot.transform.basis.x, _yaw_pivot.transform.basis.z)
			_apply_state()
	elif event is InputEventMouseButton and zoom_enabled:
		var button_event := event as InputEventMouseButton
		if not button_event.pressed:
			return
		if button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			state.zoom_in()
			_apply_state()
		elif button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			state.zoom_out()
			_apply_state()


## Recenters the orbit pivot on a world point (e.g. a board's center, or a
## unit's cell) without disturbing the current yaw/pitch/zoom.
func center_on(world_position: Vector3) -> void:
	state.pan_offset = world_position
	_apply_state()


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
