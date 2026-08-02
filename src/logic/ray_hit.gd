class_name RayHit
extends RefCounted

## taskblock-52 Pass B: one struck surface, as a ray march reports it.
##
## Deliberately **not** a second `HitResult`. `HitResult` is what a *screen* ray
## cast answers with (docs/09 taskblock06) and is consumed by the aim UI; this is
## what a *shot* march answers with, and it carries the two things resolution
## needs that the aim UI never did — the struck face's real world normal and the
## struck box's thickness. Those are exactly what the shot plane threw away.
##
## `to_region()` is what keeps this from forking the damage pipeline.
## `DamageResolver.resolve_impact`, `ImpactResult`, and every logging consumer in
## `ShotResolution` speak `Region`, and none of them needs to learn a second
## vocabulary for a hit to arrive by a different route. The taskblock is explicit
## that this changes *how* an outcome is determined, never what the outcomes are.

## What the ray met. An open `StringName` vocabulary (CLAUDE.md), not an enum:
## the collections a board holds are content, and a designer adding a fifth is a
## table row rather than a code edit.
const KIND_UNIT: StringName = &"unit"
const KIND_JOINT: StringName = &"joint"
const KIND_BLOCKER: StringName = &"blocker"
const KIND_FIELD_ITEM: StringName = &"field_item"
const KIND_SURFACE: StringName = &"surface"

## The specific part struck — for a joint, the socket's `joint_handle()`
## placeholder, matching `Region.part`'s own convention exactly.
var part: Part
## The whole object that part belongs to: a `Unit`, or the root `Part` of a
## blocker / field item / surface. Same meaning as `Region.body`.
var body: Variant = null
## Non-null only for a joint hit — the discriminator that sends resolution into
## joint damage instead of the part/DT path, exactly as `Region.socket` does.
var socket: Socket = null
## Distance along the **normalised** ray direction. Always a true 3D distance,
## unlike `Region.depth`, which is a ground-plane measurement.
var t: float = 0.0
var point: Vector3 = Vector3.ZERO
## The struck face's real world normal. **The whole reason this type exists** —
## `docs/03` measures incidence against a real surface angle, and a projected
## `Region` could only ever offer the angle of the face that happened to survive
## projection.
var normal: Vector3 = Vector3.ZERO
## The struck box's minimum dimension — "the through axis a shot crosses"
## (taskblock-09 E), which is what `MaterialEntry.dt_at` reads. Same quantity
## `BodyProjector` stamps on a `Region`, from the same box.
var thickness: float = 0.0
## Which cell this belongs to. A unit's own cell, or the blocker/field-item/
## surface cell. Used for attribution and logging, never for resolution.
var cell: Vector2i = Vector2i.ZERO
var kind: StringName = KIND_UNIT
## The world origin of this hit's whole object — its root, not the struck box.
## Pass C's third tie stage measures root-to-root distance against it, so it is
## recorded when the hit is built rather than reconstructed afterwards from a
## `body` whose type would have to be re-tested.
var root_origin: Vector3 = Vector3.ZERO
## True when the ray's own origin was already inside the struck box, so there is
## no genuine entry face. Carried rather than hidden: a caller that cares can
## tell it apart from an ordinary hit.
var inside: bool = false
## Where the ray **leaves** the struck box, and through which face.
##
## A penetrating round has to resume beyond what it just cleared; resuming a hair
## past the *entry* face leaves it inside the box, which strikes the same plate
## again on the next segment. That is not hypothetical — the first version of the
## chain logged six impacts on one plate from one round before the damage ran out.
## It is also what a `hollow` part's exit face is: the second, deeper impact the
## shot plane emits as its own `Region` (taskblock-20 Pass C3).
var exit_t: float = 0.0
var exit_point: Vector3 = Vector3.ZERO
var exit_normal: Vector3 = Vector3.ZERO
## The exact box this hit came from. Carried so `RayTiebreak`'s box-cast stage can
## re-probe **the boxes the raycast already found** rather than re-deriving a
## candidate set of its own — which is what keeps that stage an arbiter over a tie
## instead of a second, wider cast.
var placement: BoxPlacement = null


## The same hit expressed as a `Region`, so it flows through
## `DamageResolver.resolve_impact` and `ShotResolution.log_impact_result`
## untouched.
##
## **`rect` is deliberately empty.** A ray hit is a point; it never projected a
## silhouette, and inventing a plausible rect would be a number nobody measured.
## Its position carries the real hit height so anything reading a height off a
## region gets the truth rather than a zero, and its size stays zero because
## there is no width to report. Nothing on the resolution path reads the size —
## `resolve_impact` reads `part`, `surface_normal` and `thickness`; the logging
## path reads `part`, `body` and `socket`.
##
## **`depth` is the 3D distance, not a ground-plane one.** The plane's `depth`
## means "distance downrange along the ground", because that is the axis it
## sorted on. Nothing in the impact or logging path divides by it or compares it
## against a plane's, so carrying the honest quantity is safe; a consumer that
## ever needs the ground distance should ask for it rather than assume.
func to_region() -> Region:
	return _region_at(point, t, normal)


## The same hit expressed from its **exit** face — a `hollow` part's second,
## deeper strike, which the plane emits as its own `Region` and which the
## lodged-bullet mechanic is defined against (taskblock-20 Pass C4: entered and
## never cleared the far face).
func to_exit_region() -> Region:
	return _region_at(exit_point, exit_t, exit_normal)


## The same hit as a `HitResult` — what a *screen* ray cast answers with, and what
## the aim UI consumes (`AimResult.resolves`).
##
## taskblock-52 Pass E: this is what lets the aim preview and resolution share one
## query. `AimController._resolve_hit` used to call `ShotPlane.resolve_ray`, which
## built a whole second plane and did its own point-in-rect lookup — a second
## resolver sitting behind the number the UI shows, which is precisely what
## `docs/08`'s pillar forbids ("the tooltip and the damage must come from the same
## call").
func to_hit_result() -> HitResult:
	return HitResult.new(part, point, normal, t, body, socket)


func _region_at(at: Vector3, distance: float, face_normal: Vector3) -> Region:
	var region := Region.new(Rect2(0.0, at.y, 0.0, 0.0), distance, part, face_normal)
	region.thickness = thickness
	region.body = body
	region.socket = socket
	return region
