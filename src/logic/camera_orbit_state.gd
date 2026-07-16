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

## docs/10 taskblock03 C1: the attack camera's own default framing —
## shallower (closer to eye-level, "over the shoulder") and closer than
## the tactical default. Flagged placeholders, same as RETICLE_SENSITIVITY
## elsewhere — docs/10 asks for the framing, not exact numbers.
const ATTACK_PITCH := -0.25
const ATTACK_ZOOM := 6.0

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


## docs/10 taskblock03 C1: pure math for "ease to a third-person
## over-the-shoulder framing of the shooter with the target framed" — a
## Dictionary of the {yaw, pitch, zoom, pan_offset} CameraRig eases toward,
## never applied directly here (this class holds the CURRENT state; a
## caller tweens toward this as the TARGET). Centers on the shooter (the
## shoulder the shot is framed over). The rig's camera sits at local +Z from
## its pivot and looks down its own -Z, so pointing that -Z at the target is
## exactly `yaw = angle_to(to_target)` with no extra offset — verified
## against the real Camera3D transform, not hand-derived, since this sign is
## exactly the kind of thing that's easy to get backwards on paper (see
## scratchpad diag_yaw.gd). That same yaw places the camera's own position
## on the opposite side of the pivot from the target, i.e. behind the
## shooter — the "over the shoulder" part falls out for free.
func attack_framing(shooter_pos: Vector3, target_pos: Vector3) -> Dictionary:
	var to_target := Vector2(target_pos.x - shooter_pos.x, target_pos.z - shooter_pos.z)
	var framing_yaw: float = yaw
	if to_target != Vector2.ZERO:
		framing_yaw = Vector2(0.0, 1.0).angle_to(to_target.normalized())
	return {
		"yaw": framing_yaw,
		"pitch": ATTACK_PITCH,
		"zoom": ATTACK_ZOOM,
		"pan_offset": shooter_pos,
	}
