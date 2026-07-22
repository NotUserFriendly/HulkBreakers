class_name UnitGeometry
extends RefCounted

## docs/10 "render is hitbox": full, unfiltered 3D placement of every living
## part's boxes for a unit, in world space — distinct from BodyProjector's
## 2D view-plane projection (which culls to visible faces for one line of
## fire). Both compose the same socket-chain transform the same way
## (Phase 12.0: `parent ∘ socket.current_transform() ∘ ...`), so what a
## HitVolumeView renders and what the shot plane can hit are always the same
## boxes.

## World units per grid cell — the ground plane's scale for both the board
## mesh and unit placement.
const CELL_SIZE := 1.0
## docs/09 taskblock07 Pass A: muzzle_point()'s own fallback when a weapon
## somehow has no placement at all (defensive: an operable weapon always
## has one) — roughly chest-height on the reference humanoid, the same
## value the view layer's own tracer/targeting-line fallback already used
## before this became a logic-layer concern too.
const DEFAULT_MUZZLE_HEIGHT := 1.25


## Every living part's boxes, each as a BoxPlacement carrying that part's
## full world transform (unit facing + board position + socket chain +
## pose).
##
## docs/10 taskblock03 E3: `orientation_override`, when not null, replaces
## `unit.orientation` for this placement pass only — TACTICS previews a
## queued-but-unresolved facing against the speculative clone, and the view
## must render that preview, never the authoritative `unit.orientation`
## itself, without needing a whole cloned Unit just to change one float.
##
## docs/10 taskblock05 F2: `pose_override`, when not null, replaces
## `unit.pose` for this placement pass only — same convention as
## `orientation_override` (taskblock03 E3). Composes `unit.pose` by
## default so a settable pose is meaningful at all, but never
## automatically substitutes a computed one (e.g. DOWN): a caller that
## wants DOWN's geometry passes `Poses.down()` in explicitly (HitVolumeView
## does, based on Unit.is_downed()) — plenty of headless fixtures never
## bother docking a matrix for reasons unrelated to piloting status, and
## must not silently start rendering sideways because of it.
static func placements(
	unit: Unit, orientation_override: Variant = null, pose_override: Variant = null
) -> Array[BoxPlacement]:
	if unit.shell.root == null:
		return []
	var orientation: float = (
		orientation_override if orientation_override != null else unit.orientation
	)
	var pose: Pose = pose_override if pose_override != null else unit.pose
	return assembly_placements(unit.shell.root, unit.cell, orientation, pose)


## docs/10 taskblock04 C1: the same tree-walk `placements()` gives a real
## Unit's shell, generalized to any bare part tree sitting at a cell — a
## field object (a dropped assembly, a scrap pile) has no owning Unit and
## no facing of its own (orientation 0.0 by default: it doesn't face
## anything) and no pose of its own (null: it isn't posed at all).
## `placements()` is just this with a Unit's own cell/orientation/pose
## unpacked for it.
static func assembly_placements(
	root: Part, cell: Vector2i, orientation: float = 0.0, pose: Pose = null
) -> Array[BoxPlacement]:
	var result: Array[BoxPlacement] = []
	var unit_transform := Transform3D(
		Basis(Vector3.UP, orientation), Vector3(cell.x, 0.0, cell.y) * CELL_SIZE
	)
	if pose != null and pose.overrides.has(Poses.ROOT_SOCKET_ID):
		unit_transform = unit_transform * (pose.overrides[Poses.ROOT_SOCKET_ID] as Transform3D)
	_walk(root, Transform3D.IDENTITY, unit_transform, result, pose)
	return result


static func _walk(
	part: Part,
	part_transform: Transform3D,
	unit_transform: Transform3D,
	result: Array[BoxPlacement],
	pose: Pose
) -> void:
	if part.hp > 0:
		for box: Box in part.volume:
			result.append(BoxPlacement.new(part, box, unit_transform * part_transform))
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		# docs/09 taskblock06 Pass B: the seam a future rig posing system
		# slots into (Socket.current_transform() — today just `transform`).
		var socket_transform: Transform3D = socket.current_transform()
		if pose != null and pose.overrides.has(socket.id):
			socket_transform = socket_transform * (pose.overrides[socket.id] as Transform3D)
		_walk(socket.occupant, part_transform * socket_transform, unit_transform, result, pose)


## docs/10 taskblock04 A2: "compute each unit's bounding sphere from its
## ACTUAL geometry... do NOT hardcode humanoid dimensions: giant enemies are
## coming, and that is the whole reason a solver exists." Built from every
## living box's own world-space corners (`placements()` already composes
## the full unit-facing + socket-chain transform) — never a fixed torso
## height or body size. `{center, radius}`: center is the world-space AABB
## center of every corner; radius is half that AABB's diagonal. Not the
## tightest possible enclosing sphere, but simple, correct for arbitrarily
## rotated boxes, and tight enough for a framing margin check.
static func bounding_sphere(unit: Unit, orientation_override: Variant = null) -> Dictionary:
	var box_placements: Array[BoxPlacement] = placements(unit, orientation_override)
	var origin: Vector3 = Vector3(unit.cell.x, 0.0, unit.cell.y) * CELL_SIZE
	return _sphere_from_placements(box_placements, origin)


## tb32 Pass C: the `bounding_sphere` counterpart for a bare blocker/
## field-item Part (no owning Unit at all) — camera framing (`CameraRig.
## ease_to_attack_framing`) needs the same `{center, radius}` shape to aim
## at a wall/cover/downed object the way it already does a live unit.
## Same "actual geometry, never a hardcoded size" reasoning as
## `bounding_sphere` above, just from `assembly_placements` (the whole
## part tree at `cell`) instead of a Unit's own oriented shell.
static func bounding_sphere_for_part(part: Part, cell: Vector2i) -> Dictionary:
	var box_placements: Array[BoxPlacement] = assembly_placements(part, cell)
	var origin: Vector3 = Vector3(cell.x, 0.0, cell.y) * CELL_SIZE
	return _sphere_from_placements(box_placements, origin)


## Shared tail of `bounding_sphere`/`bounding_sphere_for_part` — `{center,
## radius}` from a placement list's own world-space AABB, or a zero-radius
## sphere at `origin` when there's no geometry at all to measure.
static func _sphere_from_placements(
	box_placements: Array[BoxPlacement], origin: Vector3
) -> Dictionary:
	if box_placements.is_empty():
		return {"center": origin, "radius": 0.0}
	var box: AABB = placements_aabb(box_placements)
	return {"center": box.get_center(), "radius": box.size.length() * 0.5}


## The world-space AABB enclosing every placement's own box corners —
## the corner-math `bounding_sphere` above needs, factored out so a bare
## placement list with no owning Unit at all (a resource-editor preview,
## docs/10 taskblock04 C1's "field object" case) can get the same honest
## answer without fabricating one.
static func placements_aabb(box_placements: Array[BoxPlacement]) -> AABB:
	var min_corner: Vector3 = Vector3.INF
	var max_corner: Vector3 = -Vector3.INF
	for placement: BoxPlacement in box_placements:
		var half: Vector3 = placement.box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var local_corner: Vector3 = (
						placement.box.center + Vector3(sx * half.x, sy * half.y, sz * half.z)
					)
					var world_corner: Vector3 = placement.transform * local_corner
					min_corner = min_corner.min(world_corner)
					max_corner = max_corner.max(world_corner)
	return AABB(min_corner, max_corner - min_corner)


## docs/09 taskblock07 Pass A: `weapon`'s own composed world position — the
## real ray origin `ShotPlane.resolve_ray` wants (docs/09 taskblock06 Pass
## A's own docstring: "what a physics raycast will want verbatim"), not an
## idealized cell-center point. Logic-layer (Overwatch needs this
## headlessly; the view's own targeting-line cosmetic already duplicated
## this exact lookup — that duplication is gone now, AimView delegates
## here too). Falls back to DEFAULT_MUZZLE_HEIGHT above the unit's own cell
## only if the weapon somehow has no placement at all.
##
## taskblock-26 Pass A2: "the literal shoulder, not from the shoulder" —
## the weapon's own box CENTER sits inside the gun's body, still close to
## the shooter's own torso for a short weapon (a pistol's box, e.g.,
## center Z 0.2 of a 0.4-long box); a real muzzle is the FORWARD emission
## point, not the gun's own middle. `Box`'s own documented convention
## (`box.gd`: "+Z forward, relative to the part's own origin") makes the
## tip unambiguous: `center + (0, 0, size.z / 2)`, the box's own far face
## along local +Z, composed through the SAME placement transform as
## before — every other reader of this function (Overwatch, AimView,
## shouldered_muzzle_point) gets the corrected point for free, no change
## needed at any call site.
static func muzzle_point(unit: Unit, weapon: Part) -> Vector3:
	for placement: BoxPlacement in placements(unit):
		if placement.part == weapon:
			var tip: Vector3 = placement.box.center + Vector3(0.0, 0.0, placement.box.size.z * 0.5)
			return placement.transform.translated_local(tip).origin
	return Vector3(unit.cell.x, DEFAULT_MUZZLE_HEIGHT, unit.cell.y) * CELL_SIZE


## taskblock-22 Pass H1: `unit`'s own real SHOULDER socket world height —
## walked the same composed-transform way `placements()` builds every
## other world position, just stopping at the first `&"SHOULDER"`-typed
## socket found instead of descending into its occupant's own boxes (a
## socket has no box of its own to place). The real authored value (e.g.
## `data/parts/torso.tres`'s own SHOULDER_L/R, world Y 1.53 for the
## reference humanoid), never a guessed universal constant — a shell
## built with a taller/shorter torso gets its own real number for free.
## -1.0 (no SHOULDER socket anywhere in this shell) lets a caller fall
## back to something else rather than trusting a fabricated height.
static func shoulder_height(unit: Unit) -> float:
	if unit.shell.root == null:
		return -1.0
	var unit_transform := Transform3D(
		Basis(Vector3.UP, unit.orientation), Vector3(unit.cell.x, 0.0, unit.cell.y) * CELL_SIZE
	)
	return _find_shoulder(unit.shell.root, Transform3D.IDENTITY, unit_transform)


static func _find_shoulder(
	part: Part, part_transform: Transform3D, unit_transform: Transform3D
) -> float:
	if part.hp <= 0:
		return -1.0
	for socket: Socket in part.sockets:
		if socket.socket_type == &"SHOULDER":
			return (unit_transform * part_transform * socket.current_transform()).origin.y
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		var found: float = _find_shoulder(
			socket.occupant, part_transform * socket.current_transform(), unit_transform
		)
		if found >= 0.0:
			return found
	return -1.0


## taskblock-22 Pass H1: "weapons should fire from shoulder level, not
## wherever the grip sits... for now, hover the weapon at shoulder
## height when firing." The weapon's own real composed lateral/depth
## position (X/Z) stays exactly what `muzzle_point` already gives — only
## the firing HEIGHT (Y) is overridden to the shell's own real shoulder
## height. A shell with no SHOULDER socket at all keeps its natural
## muzzle_point unchanged (there's no "shoulder" to hover to). This is
## the one place the override applies — the weapon's own rendered/
## composed placement (the actual mesh position) is untouched, per the
## taskblock's own "for now" framing; a real animated shouldering pose is
## a further-out change, not this pass's.
static func shouldered_muzzle_point(unit: Unit, weapon: Part) -> Vector3:
	var natural: Vector3 = muzzle_point(unit, weapon)
	var shoulder_y: float = shoulder_height(unit)
	if shoulder_y < 0.0:
		return natural
	return Vector3(natural.x, shoulder_y, natural.z)
