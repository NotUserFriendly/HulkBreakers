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

## docs/10 taskblock04 A: the attack camera's own default framing —
## shallower (closer to eye-level, "over the shoulder") than the tactical
## default. Flagged placeholder, same status as every other un-pinned
## tuning number in this view layer. Still the fallback when shooter and
## target share the exact same point (nothing to look at, so nothing to
## compute a real pitch from).
const ATTACK_PITCH := -0.25
## Lifts a unit's bounding-sphere-derived anchor point off the ground
## slightly for the RIGHT/UP offset math below — a small, fixed nudge, not
## a body-size assumption (the sphere itself, from
## UnitGeometry.bounding_sphere(), is what actually scales with the unit).
const ATTACK_UP_OFFSET := 0.6
## Lateral offset from the shooter, perpendicular to the shooter->target
## line — "a point to the right... of the aiming shell's torso" (the
## original spec). Never a distance-solving axis on its own (see
## ThirdPersonTS.md Design 2 -> 3): BACK, below, is what actually keeps the
## shooter and target both in frame.
const ATTACK_RIGHT_OFFSET := 0.9
## docs/10 taskblock04 A2: Camera3D's own default FOV (KEEP_HEIGHT, so this
## is the VERTICAL fov) — never set explicitly on the real Camera3D
## elsewhere, so this constant has to track that default rather than reading
## it from a live node this pure class has no access to.
const CAMERA_FOV_DEG := 75.0
## How much of the usable half-FOV the solver actually fills — headroom so
## a sphere's silhouette doesn't graze the literal edge of frame.
const ATTACK_MARGIN := 0.85
## Upper bound for the BACK search — large enough that even a wildly
## oversized "giant" target's bounding sphere still resolves to a finite
## answer rather than searching forever.
const ATTACK_BACK_MAX := 200.0
## Binary-search iterations for the BACK solve — each halves the residual
## interval, so 40 lands well past float precision for any ATTACK_BACK_MAX
## in this range.
const ATTACK_BACK_ITERATIONS := 40
## tb34 Pass D: beyond this many cells (Chebyshev — the same distance
## convention every range/threshold check elsewhere in this codebase
## already uses), the attack camera frames the target alone
## (`sniper_framing`) instead of over-the-shoulder (`attack_framing`).
## Supervisor-given starting point, not a tuned design number — a
## tunable, never a literal at the call site.
const SNIPER_FRAME_DISTANCE := 5
## `sniper_framing`'s own closed-form solve lands exactly on the usable-
## half-FOV boundary otherwise (no second body's own footprint to leave
## slack against, unlike `_solve_back`'s binary search) — a small backoff
## factor on the solved zoom, not a design number.
const SNIPER_ZOOM_SLACK := 1.02

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


## docs/10 taskblock04 A: "show the entire shooter (or a good portion),
## while the entire target is also visible" — a solved framing, not a
## tuned offset (see ThirdPersonTS.md for why Design 2's offsets, both
## perpendicular to the view axis, could never pull the camera far enough
## back to fit both bodies no matter how far they were pushed). Returns a
## Dictionary of the {yaw, pitch, zoom, pan_offset} CameraRig locks to
## (never applied directly here — this class holds the CURRENT state; a
## caller tweens toward this as the TARGET, then holds it fixed).
##
## `shooter`/`target` are `{center: Vector3, radius: float}` bounding
## spheres — UnitGeometry.bounding_sphere() builds these from each unit's
## ACTUAL living geometry, never a hardcoded body size, so a giant enemy
## solves its own correct BACK distance with no special-casing here.
##
## The camera orbits the TARGET (`pan_offset = target.center`) rather than
## sitting at a literal computed point (Design 2's `zoom = 0` hack) — this
## is what actually fixes the mid-tween "sweeps through the shooter"
## glitch: a pivot-plus-zoom-plus-angle lerp between two orbits around
## sensible points has no reason to pass near either body, whereas
## lerping toward a point glued to the shooter's own position does.
##
## camera_pos = shooter.center - to_target*BACK + right*RIGHT + up*UP.
## `-to_target*BACK` is the missing axis Design 2 never had: it pulls the
## camera backward along the shooter->target line, putting the shooter
## BETWEEN the camera and the target — which is the actual definition of
## "over the shoulder." BACK is solved, via binary search, as the smallest
## distance at which both spheres' angular footprint (angle to center plus
## the half-angle subtended by their own radius) fits inside the usable
## half vertical FOV.
##
## Once camera_pos is known, {yaw, pitch} are the SAME formula Design 2
## verified against a real Camera3D (see ThirdPersonTS.md /
## diag_lookat.gd) — pitch from `asin(look_dir.y)`, yaw from
## `atan2(-horiz.x, -horiz.y)` — because for this rig's topology (camera at
## local +Z*zoom from a pivot, zero rotation of its own) the camera always
## faces its pivot by construction: the same {yaw, pitch} pair that made a
## zoom=0 camera look AT the target now makes a zoom=|offset| orbit CAMERA
## sit at the right point around the target pivot. Only what `zoom`/
## `pan_offset` represent changed, not this formula.
func attack_framing(shooter: Dictionary, target: Dictionary) -> Dictionary:
	var shooter_center: Vector3 = shooter.center
	var shooter_radius: float = shooter.radius
	var target_center: Vector3 = target.center
	var target_radius: float = target.radius

	var to_target := Vector2(target_center.x - shooter_center.x, target_center.z - shooter_center.z)
	var camera_pos: Vector3 = shooter_center + Vector3(0.0, ATTACK_UP_OFFSET, 0.0)
	var framing_yaw: float = yaw
	var framing_pitch: float = ATTACK_PITCH
	# Gated on `to_target`, not on the look direction computed below: once
	# ATTACK_UP_OFFSET lifts the camera off the shooter's own center, a
	# degenerate same-point shooter/target pair still produces a small
	# straight-down "look direction" that is NOT actually degenerate by the
	# "is this vector near zero" test — it has to be caught here instead,
	# from the one input that's genuinely ambiguous: no horizontal
	# direction to face.
	if to_target != Vector2.ZERO:
		var dir: Vector2 = to_target.normalized()
		# The shooter's own right-hand side facing `dir`, in a Y-up world:
		# forward x up = (dir.x,0,dir.y) x (0,1,0) = (-dir.y, 0, dir.x).
		var right := Vector2(-dir.y, dir.x)
		var back: float = _solve_back(
			shooter_center, shooter_radius, target_center, target_radius, dir, right
		)
		camera_pos = (
			shooter_center
			- Vector3(dir.x, 0.0, dir.y) * back
			+ Vector3(right.x, 0.0, right.y) * ATTACK_RIGHT_OFFSET
			+ Vector3(0.0, ATTACK_UP_OFFSET, 0.0)
		)

		var look_dir: Vector3 = (target_center - camera_pos).normalized()
		framing_pitch = asin(clampf(look_dir.y, -1.0, 1.0))
		var horiz := Vector2(look_dir.x, look_dir.z)
		if horiz.length() > 0.0001:
			framing_yaw = atan2(-horiz.x, -horiz.y)

	return {
		"yaw": framing_yaw,
		"pitch": framing_pitch,
		"zoom": camera_pos.distance_to(target_center),
		"pan_offset": target_center,
	}


## tb34 Pass D: "frame the target, not shooter-over-shoulder" — over-the-
## shoulder framing reads well up close but degrades badly at range (both
## spheres compress toward the same screen point, and the "over the
## shoulder" offset just wastes frame on the empty middle distance). This
## rig's own topology (the camera always faces its own `pan_offset` pivot
## by construction — see `attack_framing`'s own doc comment) means setting
## `pan_offset = target.center` puts the target dead-center on screen at
## ANY yaw/pitch — no dual-sphere BACK solve needed, only the single-
## sphere distance at which the target's own angular footprint fits the
## usable half-FOV (closed-form here, unlike `_solve_back`'s binary
## search, because there is no second body's own footprint to jointly
## satisfy). Keeps the CURRENT yaw/pitch rather than solving a new viewing
## angle — with nothing else to keep in frame, any direction already
## centers the target.
func sniper_framing(target: Dictionary) -> Dictionary:
	var target_radius: float = target.radius
	var usable_half_fov: float = deg_to_rad(CAMERA_FOV_DEG * 0.5) * ATTACK_MARGIN
	# Solving the exact boundary (angular footprint == usable_half_fov, zero
	# slack beyond ATTACK_MARGIN itself) leaves the sphere grazing the
	# literal edge, at the mercy of floating-point rounding — the same
	# grazing ATTACK_MARGIN itself exists to avoid. SNIPER_ZOOM_SLACK backs
	# the solved distance off a hair further, same as `_solve_back`'s own
	# binary search always lands strictly inside the fit, never exactly on it.
	var solved_zoom: float = (
		(target_radius / sin(usable_half_fov)) * SNIPER_ZOOM_SLACK
		if target_radius > 0.0
		else DEFAULT_ZOOM
	)
	return {
		"yaw": yaw,
		"pitch": pitch,
		"zoom": clampf(solved_zoom, MIN_ZOOM, ATTACK_BACK_MAX),
		"pan_offset": target.center,
	}


## Binary search for the smallest BACK (>= 0) at which both bounding
## spheres fit inside the usable half-FOV — larger BACK moves the camera
## farther from both bodies, shrinking their angular footprint, so `_fits`
## is monotonic non-decreasing in BACK; if even ATTACK_BACK_MAX can't fit
## both (a wildly oversized target), that's the best available answer
## rather than searching forever.
func _solve_back(
	shooter_center: Vector3,
	shooter_radius: float,
	target_center: Vector3,
	target_radius: float,
	dir: Vector2,
	right: Vector2
) -> float:
	var usable_half_fov: float = deg_to_rad(CAMERA_FOV_DEG * 0.5) * ATTACK_MARGIN
	var lo := 0.0
	var hi := ATTACK_BACK_MAX
	for i in range(ATTACK_BACK_ITERATIONS):
		var mid: float = (lo + hi) * 0.5
		if _both_fit(
			shooter_center,
			shooter_radius,
			target_center,
			target_radius,
			dir,
			right,
			mid,
			usable_half_fov
		):
			hi = mid
		else:
			lo = mid
	return hi


func _both_fit(
	shooter_center: Vector3,
	shooter_radius: float,
	target_center: Vector3,
	target_radius: float,
	dir: Vector2,
	right: Vector2,
	back: float,
	usable_half_fov: float
) -> bool:
	var camera_pos: Vector3 = (
		shooter_center
		- Vector3(dir.x, 0.0, dir.y) * back
		+ Vector3(right.x, 0.0, right.y) * ATTACK_RIGHT_OFFSET
		+ Vector3(0.0, ATTACK_UP_OFFSET, 0.0)
	)
	var look_dir: Vector3 = (target_center - camera_pos).normalized()
	return (
		_sphere_fits(camera_pos, look_dir, shooter_center, shooter_radius, usable_half_fov)
		and _sphere_fits(camera_pos, look_dir, target_center, target_radius, usable_half_fov)
	)


## True if a sphere's whole silhouette (its center's angle off the look
## direction, plus the half-angle its own radius subtends at this
## distance) fits inside `usable_half_fov`. A camera literally inside the
## sphere (distance <= radius) trivially fits — nothing to project.
func _sphere_fits(
	camera_pos: Vector3, look_dir: Vector3, center: Vector3, radius: float, usable_half_fov: float
) -> bool:
	var offset: Vector3 = center - camera_pos
	var distance: float = offset.length()
	if distance <= radius:
		return true
	var angle_to_centre: float = look_dir.angle_to(offset.normalized())
	var half_angle: float = asin(clampf(radius / distance, 0.0, 1.0))
	return angle_to_centre + half_angle <= usable_half_fov
