class_name UnitGeometry
extends RefCounted

## docs/10 "render is hitbox": full, unfiltered 3D placement of every living
## part's boxes for a unit, in world space — distinct from BodyProjector's
## 2D view-plane projection (which culls to visible faces for one line of
## fire). Both compose the same socket-chain transform the same way
## (Phase 12.0: `parent ∘ socket.transform ∘ ...`), so what a UnitView
## renders and what the shot plane can hit are always the same boxes.

## World units per grid cell — the ground plane's scale for both the board
## mesh and unit placement.
const CELL_SIZE := 1.0


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
## wants DOWN's geometry passes `Poses.down()` in explicitly (UnitView
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
		var socket_transform: Transform3D = socket.transform
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
	if box_placements.is_empty():
		return {"center": origin, "radius": 0.0}

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

	var center: Vector3 = (min_corner + max_corner) * 0.5
	var radius: float = (max_corner - min_corner).length() * 0.5
	return {"center": center, "radius": radius}
