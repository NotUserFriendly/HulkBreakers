class_name Poses
extends RefCounted

## docs/10 taskblock05 F: three poses, readable at a glance, snap only —
## no animation system, no interpolation between them. Data rows, no
## code: adding a fourth pose is one more static function here.

## No real part ever declares a socket with this id — reserved, composed
## onto the whole assembly's own placement (see Pose's own doc comment).
const ROOT_SOCKET_ID := &"ROOT"
## "The" weapon arm, by this project's own default_loadout() convention
## (hand_r/GRIP_R is the canonical armed hand) — a pose is shared, generic
## data, not unit-specific, so it picks one side rather than trying to
## infer which hand actually holds a weapon.
const AIMING_SHOULDER_ID := &"SHOULDER_R"


## Arms down — the authored rest position already IS this, so there's
## nothing to override.
static func idle() -> Pose:
	return Pose.new()


## The weapon arm raised toward the target. docs/10 taskblock05 F2: "it
## isn't cosmetic — a pose moves the boxes, so it moves the shot plane."
## The aim direction itself stays a RESOLUTION/TACTICS concern (docs/02),
## never sampled here; this is just the readable silhouette a unit in a
## firing stance presents.
static func aiming() -> Pose:
	var pose := Pose.new()
	pose.overrides = {
		AIMING_SHOULDER_ID: Transform3D(Basis(Vector3.RIGHT, -PI / 4.0), Vector3.ZERO)
	}
	return pose


## On its back — replaces taskblock-03 G's ad-hoc, view-only rotate.
## Composing a 90-degree rotation about local X onto the whole assembly's
## own placement, before the unit's own orientation/position apply,
## converts every part's elevation (encoded in local Y) into a horizontal
## offset — every box ends up near ground level. The same silhouette the
## old view-only hack approximated, now real geometry the shot plane and
## UnitPicker's own hit-testing agree with, not a render-only trick.
static func down() -> Pose:
	var pose := Pose.new()
	pose.overrides = {ROOT_SOCKET_ID: Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)}
	return pose


## taskblock-20 Pass H: "dive prone... alters the shot plane to a worse-
## but-different silhouette" — the DIVE_PRONE reaction (ReactionResolver).
## Reuses `down()`'s own "flat, near-ground" geometry verbatim (a diving
## unit and a downed one present the same physical silhouette) as its own
## named pose, never composed FROM `down()` at the call site — a still-
## piloted, prone unit must never be confused with `is_downed()`'s
## matrix-ejected corpse case just because they happen to share a
## transform.
static func prone() -> Pose:
	var pose := Pose.new()
	pose.overrides = {ROOT_SOCKET_ID: Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)}
	return pose


## taskblock-25 Pass A: the torso extended forward by `amount` (world
## units) along the unit's own current facing — a sub-tile position
## change, no cell move. Composes onto `ROOT_SOCKET_ID` exactly like
## `down()`/`prone()`, so `BodyProjector.project()`'s existing pose-
## override seam moves the WHOLE assembly, and the ordinary depth-sort
## exposure the overwatch torso check already runs falls out for free —
## no melee-specific exposure system (docs/PLAN.md "Phase M — Melee").
## `amount <= 0.0` returns `idle()` (nothing to lean).
static func lean(amount: float) -> Pose:
	if amount <= 0.0:
		return idle()
	var pose := Pose.new()
	pose.overrides = {ROOT_SOCKET_ID: Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, amount))}
	return pose


## docs/10 taskblock05 G5: presets address a pose by name (StringName, not
## a serialized Resource) — one more open row here covers a new pose for
## both the game and the builder's own pose dropdown at once.
static func by_id(id: StringName) -> Pose:
	match id:
		&"AIMING":
			return aiming()
		&"DOWN":
			return down()
		&"PRONE":
			return prone()
		_:
			return idle()


static func all_ids() -> Array[StringName]:
	return [&"IDLE", &"AIMING", &"DOWN", &"PRONE"]
