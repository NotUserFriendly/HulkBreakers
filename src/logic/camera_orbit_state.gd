class_name CameraOrbitState
extends RefCounted

## Pure orbit/pan/zoom math for the Tactical camera (docs/10). Every clamp
## and delta lives here, testable with no scene tree — CameraRig (the Node)
## only ever reads this and sets Node3D properties from it.

const MIN_ZOOM := 3.0
const MAX_ZOOM := 30.0
## Kept strictly inside (-PI/2, 0): orbiting can never level into the board
## plane or flip past straight down, so there is no pole to gimbal-lock at.
const MIN_PITCH := -1.4
const MAX_PITCH := -0.1
const ORBIT_SPEED := 0.01
const PAN_SPEED := 0.02
const ZOOM_STEP := 1.0
const DEFAULT_PITCH := -0.6
const DEFAULT_ZOOM := 12.0

var yaw: float = 0.0
var pitch: float = DEFAULT_PITCH
var zoom: float = DEFAULT_ZOOM
var pan_offset: Vector3 = Vector3.ZERO


## Yaw is unbounded (a full turn is always legal); pitch is clamped so the
## rig can never orbit past level or past straight down.
func orbit(relative: Vector2) -> void:
	yaw -= relative.x * ORBIT_SPEED
	pitch = clampf(pitch - relative.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)


## `right`/`forward` are the rig's own current basis vectors — panning moves
## along the board plane as the camera currently sees it, not world axes.
func pan(relative: Vector2, right: Vector3, forward: Vector3) -> void:
	pan_offset -= right * relative.x * PAN_SPEED
	pan_offset += forward * relative.y * PAN_SPEED


func zoom_in() -> void:
	zoom = clampf(zoom - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)


func zoom_out() -> void:
	zoom = clampf(zoom + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
