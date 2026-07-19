class_name InternalTargeting
extends RefCounted

## taskblock-20 Pass B: "occlusion gated by knowledge... the aim-at-known-
## position path." Occlusion itself needs no new code — ShotPlane.
## resolve_projectile/resolve_ray already return the FRONTMOST region at a
## point (docs/02), so a default, center-mass shot already can't land
## directly on a part sitting behind another one; test_internal_targeting.gd
## reconfirms this explicitly for internals rather than trusting it as an
## unstated side effect. What's missing is the other half: a KNOWING shooter
## aiming at a specific internal's own position. This reuses AttackAction's
## existing `aim_offset` (docs/02: the dartboard picks a point, not a part)
## instead of adding a second resolution path — the same depth-cascade that
## already penetrates cladding to reach whatever's behind it does the actual
## work; this class only ever computes WHERE to aim, never how a shot
## resolves once fired.

## Rect-local sample fractions, center first — the honest "aim dead center"
## point whenever nothing blocks it, only drifting off-center as a fallback.
const _SAMPLE_FRACTIONS: Array[Vector2] = [
	Vector2(0.5, 0.5),
	Vector2(0.2, 0.5),
	Vector2(0.8, 0.5),
	Vector2(0.5, 0.2),
	Vector2(0.5, 0.8),
	Vector2(0.2, 0.2),
	Vector2(0.8, 0.2),
	Vector2(0.2, 0.8),
	Vector2(0.8, 0.8),
]


## The `aim_offset` that lands AttackAction's own
## `ShotPlane.center_of(plane, target) + aim_offset` formula on a real,
## reachable point within `part`'s own region in `plane`. Null if
## `Knowledge.knows_internal` refuses, if `part` has no region of its own
## anywhere in `plane` (destroyed, or genuinely not present), or if every
## sampled point within its footprint sits behind a nearer JOINT (below).
##
## The naive "region rect center" isn't always usable: `part`'s own
## silhouette can overlap a nearer part's own MOUNTING JOINT — a discrete
## connector, not armor, that `DamageResolver.resolve_shot` always treats as
## a hard stop regardless of damage ("a connection has no material... there's
## no concept of penetrating a connection") — so a point dead-center can sit
## permanently unreachable even at any weapon's max damage (confirmed live:
## the torso's own reactor, mounted at BACK, has its own rect center sitting
## squarely behind torso_cladding's own attachment joint). An ordinary
## occluding PART (cladding, a strut) is not the same problem — a real
## weapon punches through it via the SAME damage-vs-DT cascade every other
## shot already uses, no special-casing needed here — so only joints are
## searched around; sampling several points across the footprint (center
## first, then off-center) finds a real, joint-clear line to it wherever one
## exists.
static func aim_offset_for(
	state: CombatState, shooter: Unit, target: Unit, part: Part, plane: Array[Region]
) -> Variant:
	if not Knowledge.knows_internal(state, shooter, target, part):
		return null
	var part_region: Region = null
	for region: Region in plane:
		if region.part == part and region.body == target:
			part_region = region
			break
	if part_region == null:
		return null

	var clear_point: Variant = _clear_point_in(plane, part_region)
	if clear_point == null:
		return null
	return clear_point - ShotPlane.center_of(plane, target)


static func _clear_point_in(plane: Array[Region], part_region: Region) -> Variant:
	for frac: Vector2 in _SAMPLE_FRACTIONS:
		var point: Vector2 = part_region.rect.position + part_region.rect.size * frac
		if not _blocked_by_nearer_joint(plane, part_region, point):
			return point
	return null


## True if some JOINT region strictly nearer than `part_region` (a smaller
## depth — the shot reaches it first) also covers `point`. Depth ties never
## occur for a real joint/occupant pair (a joint's own depth always sits at
## its socket's transform, distinct from the part mounted there), so `<`
## alone is enough — no epsilon needed.
static func _blocked_by_nearer_joint(
	plane: Array[Region], part_region: Region, point: Vector2
) -> bool:
	for region: Region in plane:
		if region.socket == null or region.depth >= part_region.depth:
			continue
		if region.rect.has_point(point):
			return true
	return false
