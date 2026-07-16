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
## the tactical default. Flagged placeholders, same status as every other
## un-pinned tuning number in this view layer — docs/10 asks for the
## framing, not exact numbers. Still the fallback when shooter and target
## share the exact same point (nothing to look at, so nothing to compute a
## real pitch from).
const ATTACK_PITCH := -0.25
## runNotes.md follow-up: "tie the third person camera to the torso of the
## AIMING unit, offset right and up... point the camera at the torso of the
## TARGETED unit" — replaced the old orbit-pivot-plus-zoom framing (camera
## potentially many units away from either body) with the camera sitting
## directly at the shooter, nudged right/up, looking straight at the
## target. `_world_pos()` callers hand this cell-ground positions (y=0,
## feet); ATTACK_TORSO_HEIGHT lifts both to roughly chest height — same
## constant status as ResolutionPlayer.TRACER_MUZZLE_HEIGHT (docs/01: the
## reference humanoid's own torso sits at ROOT_ELEVATION 1.25).
const ATTACK_TORSO_HEIGHT := 1.25
## runNotes.md: "over the shoulder camera is still very strange" —
## verified via a live render (scratchpad diagnostics, not hand-derived):
## the original 0.9/0.6 offsets were smaller than the shooter's own torso
## box, so the camera sat just outside the shooter's own bounding box,
## inside their personal space — the shooter was never actually visible in
## the final shot (no "shoulder" in the over-the-shoulder shot at all), and
## the tween's straight-line interpolation from the distant tactical
## camera swept close enough to the shooter's body mid-transition to
## balloon it across half the screen before settling. Pulled back to
## roughly 2.5x/2.5x so the shooter's own body clears the lens with real
## margin, both at rest and along the way there.
const ATTACK_RIGHT_OFFSET := 2.5
const ATTACK_UP_OFFSET := 1.5

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


## runNotes.md follow-up: pure math for "camera position = the aiming
## unit's torso, offset right and up; pointed at the targeted unit's
## torso" — a Dictionary of the {yaw, pitch, zoom, pan_offset} CameraRig
## locks to (never applied directly here — this class holds the CURRENT
## state; a caller tweens toward this as the TARGET, then holds it fixed).
##
## The rig's camera sits at LOCAL (0,0,zoom) from its pivot with no
## rotation of its own, so setting `zoom = 0` makes the pivot (`pan_offset`)
## the camera's exact world position — the rest is a standard yaw-then-
## pitch look-at solve for that position looking toward the target's torso:
## pitch only ever depends on the desired look direction's own Y component
## (`asin`, since pitch is the SECOND rotation, applied around the
## already-yawed frame's local X, which never leaves the horizontal plane
## regardless of yaw); yaw only depends on the direction's horizontal (X,Z)
## angle. Both verified against the real Camera3D transform for several
## non-coplanar (P, T) pairs, not hand-derived (see scratchpad
## diag_lookat.gd) — `atan2(-horiz.x, -horiz.y)`, specifically, NOT
## `Vector2(0,1).angle_to(horiz)` as the old formula used: the two only
## agree when the shooter and target share a row or column, which is all
## the original verification happened to test.
func attack_framing(shooter_pos: Vector3, target_pos: Vector3) -> Dictionary:
	var shooter_torso: Vector3 = shooter_pos + Vector3(0.0, ATTACK_TORSO_HEIGHT, 0.0)
	var target_torso: Vector3 = target_pos + Vector3(0.0, ATTACK_TORSO_HEIGHT, 0.0)

	var to_target := Vector2(target_pos.x - shooter_pos.x, target_pos.z - shooter_pos.z)
	var camera_pos: Vector3 = shooter_torso + Vector3(0.0, ATTACK_UP_OFFSET, 0.0)
	var framing_yaw: float = yaw
	var framing_pitch: float = ATTACK_PITCH
	# Gated on `to_target`, not on the look direction computed below: once
	# ATTACK_UP_OFFSET lifts the camera off the shooter's own torso, a
	# degenerate same-cell shooter/target pair still produces a small
	# straight-down "look direction" (camera looking down at the torso
	# right underneath it) that is NOT actually degenerate by the "is this
	# vector near zero" test — it has to be caught here instead, from the
	# one input that's genuinely ambiguous: no horizontal direction to face.
	if to_target != Vector2.ZERO:
		var dir: Vector2 = to_target.normalized()
		# The shooter's own right-hand side facing `dir`, in a Y-up world:
		# forward x up = (dir.x,0,dir.y) x (0,1,0) = (-dir.y, 0, dir.x).
		var right := Vector2(-dir.y, dir.x)
		camera_pos += Vector3(right.x, 0.0, right.y) * ATTACK_RIGHT_OFFSET

		var look_dir: Vector3 = (target_torso - camera_pos).normalized()
		framing_pitch = asin(clampf(look_dir.y, -1.0, 1.0))
		var horiz := Vector2(look_dir.x, look_dir.z)
		if horiz.length() > 0.0001:
			framing_yaw = atan2(-horiz.x, -horiz.y)

	return {
		"yaw": framing_yaw,
		"pitch": framing_pitch,
		"zoom": 0.0,
		"pan_offset": camera_pos,
	}
