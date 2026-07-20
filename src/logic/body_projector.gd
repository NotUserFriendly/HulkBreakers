class_name BodyProjector
extends RefCounted

## Body-space projection (docs/02). No facings, no snap: a part's local Box
## volumes are rotated by the continuous angle between the unit's orientation
## and the line of fire, then flattened onto the view plane. `view_dir` is
## always "direction of travel" — the same direction a shot moving from the
## shooter into the world would take — so depth increases the farther a
## point sits from the shooter, and per-unit Regions compose directly with
## ShotPlane's inter-unit depth offsets by simple addition.
##
## A box projects one Region PER VISIBLE FACE, not one region guessed for
## the whole box (docs/03): surface_normal belongs to the specific face that
## was hit. A face is visible when its rotated normal points at least partly
## toward the shooter; an edge-on face projects to near-zero width and is
## dropped. This lets incidence span the full 0-90 degree range — a box
## viewed corner-on shows two adjacent faces, one near head-on and one
## near-grazing, in non-overlapping screen spans.

## World-space ground direction a unit with orientation == 0.0 faces.
const WORLD_FORWARD := Vector2(0.0, 1.0)

## Below this projected width (world units), a face is edge-on enough to
## drop rather than emit a degenerate sliver region.
const _MIN_FACE_WIDTH := 0.001

## A box's four in-plane side faces (top/bottom ignored — shots travel
## horizontally in this abstraction), as parallel arrays: each face's local
## normal and the two +/-1 corner multipliers (of the box's half-extents)
## spanning it.
const _FACE_NORMALS: Array[Vector2] = [
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)
]
const _FACE_CORNERS_A: Array[Vector2] = [
	Vector2(1.0, -1.0), Vector2(-1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)
]
const _FACE_CORNERS_B: Array[Vector2] = [
	Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, -1.0)
]

## taskblock-09 D: a joint's own aimable footprint — small enough that
## hitting it takes a placed shot, not a stray one (docs/03: "a stray shot
## hits the big arm, a placed shot hits the elbow"), big enough to project
## a real, non-degenerate rect at ordinary combat ranges.
const _JOINT_BOX_SIZE := Vector3(0.12, 0.12, 0.12)

## taskblock-09 D: pushes a joint's own depth a hair behind its
## attachment point, so a part whose own box sits at that exact same
## point (a flush-mounted plate, zero local offset — common in this
## codebase's own fixtures) always wins a depth-sort tie. "Occluded by a
## plate isn't hittable until the plate is gone" applies to a joint's own
## flush occupant, not only to something else standing in front of it.
const _JOINT_DEPTH_BIAS := 0.001


## docs/09 taskblock07 Pass B1: THE one rotation convention — turns a
## body-local ground-plane point (x,z) into its world-relative-to-cell
## position by a unit's own `orientation`, exactly matching
## `Basis(Vector3.UP, orientation)` (UnitGeometry.assembly_placements'
## own `unit_transform`, the actual rendered model every HitVolumeView box
## obeys). Deliberately NOT `Vector2.rotated(orientation)`: that rotates
## the opposite way (mirrored — the algebra is `(x cosθ - z sinθ, x sinθ +
## z cosθ)` vs. the Basis's own `(x cosθ + z sinθ, -x sinθ + z cosθ)`),
## and every call site that used it directly was silently computing the
## shot plane, the facing arc, or the facing wedge on the WRONG side of an
## asymmetric unit. `test_body_projector.gd`'s own mirror test
## (`test_an_asymmetric_part_projects_on_the_same_side_it_renders`) is the
## load-bearing proof.
static func rotate_by_orientation(local: Vector2, orientation: float) -> Vector2:
	var world: Vector3 = Basis(Vector3.UP, orientation) * Vector3(local.x, 0.0, local.y)
	return Vector2(world.x, world.z)


## World-space forward direction for a unit facing `orientation` —
## `WORLD_FORWARD` rotated the one authoritative way above. The single
## source every facing-direction call site reads now (HitVolumeView's own
## facing wedge, Overwatch's own arc check) instead of each separately
## calling `WORLD_FORWARD.rotated(orientation)` (the other, mirrored
## convention this pass deletes).
static func forward_for(orientation: float) -> Vector2:
	return rotate_by_orientation(WORLD_FORWARD, orientation)


## taskblock-17 Pass B: the exact inverse of `forward_for` — the
## `orientation` a unit needs so its forward points at `direction`.
## Solving `forward_for(orientation) == direction` (i.e.
## `(sin(orientation), cos(orientation)) == (direction.x, direction.y)`,
## `forward_for`'s own algebra with `WORLD_FORWARD == (0, 1)` substituted
## in) gives `atan2(direction.x, direction.y)` directly — never
## `WORLD_FORWARD.angle_to(direction)`, which is `Vector2.rotated()`'s own
## STANDARD rotation convention, the one `rotate_by_orientation`'s own doc
## comment deliberately departs from. `FaceAction.orientation_toward`
## used exactly that mirrored-convention shortcut and was consequently up
## to 180 degrees off depending on the target's own direction (0 degrees
## error dead ahead, 90-180 degrees off the further the target sat from
## world-forward) — confirmed live: build a real AI unit, fire at a real
## target, read the resolved `Unit.orientation` back, and compare
## `forward_for` against the real geometric direction, not against
## `orientation_toward`'s own formula (the class of bug CLAUDE.md itself
## flags: "a test that re-derives it agrees with itself and nothing
## else"). This is the one place that inverse gets computed now.
static func orientation_for(direction: Vector2) -> float:
	return atan2(direction.x, direction.y)


## Projects every living part of `unit`'s shell into view-plane Regions,
## composing each part's Socket.transform chain from the shell root first
## (Phase 12.0) so a part attached deep in the tree — or twice, at mirrored
## sockets, even the exact same Part resource in both — projects at its own
## composed position, never the root's or a sibling occurrence's.
## docs/10 taskblock05 F2: composes `unit.pose` by default — never a
## computed override like DOWN automatically (see UnitGeometry.placements'
## own doc comment for why: most headless fixtures never dock a matrix for
## reasons unrelated to piloting status).
static func project(unit: Unit, view_dir: Vector2) -> Array[Region]:
	var regions: Array[Region] = []
	if unit.shell.root == null:
		return regions
	# taskblock-20 Pass H: the ROOT override (DOWN, PRONE) finally has a
	# live consumer here — the same "no analogue here... a later problem"
	# gap docs/10 taskblock05 F2 flagged and deferred, closed now that a
	# LIVE, still-acting unit's own reaction (dive prone) needs its altered
	# silhouette to actually change what a shot resolves against, not just
	# what the view renders. Composed BEFORE `orientation` applies (the
	# same order UnitGeometry.assembly_placements already uses: pose tips
	# the body in its own local space, orientation then turns the tipped
	# body to face wherever the unit is currently facing) — orientation
	# itself still applies separately, per-region, in 2D below; it was
	# never baked into a Transform3D here and doesn't start now.
	var root_transform := Transform3D.IDENTITY
	if unit.pose != null and unit.pose.overrides.has(Poses.ROOT_SOCKET_ID):
		root_transform = unit.pose.overrides[Poses.ROOT_SOCKET_ID] as Transform3D
	_project_tree(unit.shell.root, root_transform, view_dir, unit.orientation, regions, unit.pose)
	return regions


## docs/10 taskblock04 C1/C2: projects every living part of a bare part
## TREE — a field object (a dropped assembly, a scrap pile) sitting at a
## cell, no owning Unit — the same tree-walk `project()` gives a real
## Unit's shell, just rooted anywhere and always world-aligned
## (orientation 0.0: a field object doesn't face anything). This is what
## makes a dropped assembly "shootable... a pile of scrap stops rounds":
## `project_part` alone (ShotPlane's old cover path) only ever saw the
## root's own boxes, never an attached plate or weapon still riding along.
static func project_assembly(root: Part, view_dir: Vector2) -> Array[Region]:
	var regions: Array[Region] = []
	_project_tree(root, Transform3D.IDENTITY, view_dir, 0.0, regions, null)
	return regions


## Depth-first walk composing `world = parent ∘ socket.current_transform()
## ∘ ...` as it descends. Deliberately walks the tree directly rather than
## building a Part -> Transform3D map first: a Dictionary keyed by Part
## identity would collapse two sockets sharing one Part resource down to a
## single (last-write-wins) transform. Each occurrence gets its own
## transform, computed once here and reused across all of that
## occurrence's boxes in `project_part` — never recomputed per box.
##
## docs/10 taskblock05 F2: `pose`'s overrides compose onto each socket's
## own transform (null for a field object/cover part — those aren't
## posed) — the same mechanism UnitGeometry.assembly_placements uses, so
## the shot plane and the hitbox a player sees always agree. The reserved
## ROOT override (DOWN, taskblock-20 Pass H's PRONE) is handled by
## `project()`'s own caller seeding `part_transform` with it before this
## first runs — this function itself only ever composes PER-SOCKET
## overrides, same as always.
static func _project_tree(
	part: Part,
	part_transform: Transform3D,
	view_dir: Vector2,
	orientation: float,
	regions: Array[Region],
	pose: Pose
) -> void:
	regions.append_array(project_part(part, view_dir, orientation, part_transform))
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		# docs/09 taskblock06 Pass B: the seam a future rig posing system
		# slots into (Socket.current_transform() — today just `transform`).
		var socket_transform: Transform3D = socket.current_transform()
		if pose != null and pose.overrides.has(socket.id):
			socket_transform = socket_transform * (pose.overrides[socket.id] as Transform3D)
		var child_transform: Transform3D = part_transform * socket_transform
		# taskblock-09 D: the joint sits exactly where the child's own
		# local origin composes to — the same transform the child's own
		# regions use below, just with a small synthetic box instead of
		# real volume. Depth-sorts and occludes like any other region, so
		# a plate in front of the joint protects it the same way it
		# protects anything else at that depth.
		regions.append_array(_project_joint(socket, child_transform, view_dir, orientation))
		_project_tree(socket.occupant, child_transform, view_dir, orientation, regions, pose)


## taskblock-09 D: one small aimable region for `socket`'s own connection,
## at its composed world transform — reuses `_project_box` verbatim (same
## face-visibility/edge-on pruning every real box gets) against a tiny
## synthetic box, so a joint depth-sorts and occludes exactly like any
## other region. `region.part` is the socket's own `joint_handle()` — a
## placeholder identity, deliberately NOT the occupant part itself, so
## code that filters "every region belonging to part X" (existing tests,
## `_body_of`) never silently picks up a joint alongside that part's real
## geometry. `region.socket` is the actual discriminator resolve_shot
## reads to know this is a joint at all.
static func _project_joint(
	socket: Socket, world_transform: Transform3D, view_dir: Vector2, orientation: float
) -> Array[Region]:
	var dir: Vector2 = view_dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var box := Box.new(Vector3.ZERO, _JOINT_BOX_SIZE)
	var regions: Array[Region] = _project_box(
		box, dir, perp, orientation, socket.joint_handle(), world_transform
	)
	# Pin every joint region to the socket's own true attachment-point
	# depth, not whatever depth its own synthetic box's face happens to
	# compute — the box exists for a screen-space footprint only. Without
	# this, a joint box thicker than a thin flush-mounted plate would
	# protrude in FRONT of that plate's own face and wrongly win the
	# depth-sort.
	var point_2d := Vector2(world_transform.origin.x, world_transform.origin.z)
	var anchor_depth: float = rotate_by_orientation(point_2d, orientation).dot(dir)
	for region: Region in regions:
		region.socket = socket
		region.depth = anchor_depth + _JOINT_DEPTH_BIAS
	return regions


## Projects a single part's own boxes, rotated by `orientation` (a unit's
## facing, or 0.0 for a static, world-aligned cover/obstacle part) relative
## to `view_dir`. `local_transform` is the part's composed position/rotation
## within its own shell (identity for a standalone part, or when called
## directly outside a socket tree — the common case in tests and for
## ShotPlane's cover placement, both of which go through identical math).
static func project_part(
	part: Part,
	view_dir: Vector2,
	orientation: float = 0.0,
	local_transform: Transform3D = Transform3D.IDENTITY
) -> Array[Region]:
	# taskblock-09 A1/A2: a part at 0 hp still projects — still occludes,
	# still hittable — if it failed under MANGLE or DISABLE (both stay
	# fully attached, docs/03). A part that failed under
	# DETONATE/FRAGMENT/MELTDOWN really is "consumed in place" (taskblock-
	# 09 C2) and correctly vanishes here exactly like the old blanket
	# hp<=0 check always meant.
	if part.hp <= 0 and not (part.is_mangled or part.is_disabled):
		return []
	var dir: Vector2 = view_dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var regions: Array[Region] = []
	for box: Box in part.volume:
		regions.append_array(_project_box(box, dir, perp, orientation, part, local_transform))
	return regions


static func _project_box(
	box: Box,
	dir: Vector2,
	perp: Vector2,
	orientation: float,
	part: Part,
	local_transform: Transform3D
) -> Array[Region]:
	var half := box.size * 0.5
	var toward_shooter: Vector2 = -dir
	var regions: Array[Region] = []
	var center_in_frame: Vector3 = local_transform * box.center

	for i in range(_FACE_NORMALS.size()):
		var local_normal := Vector3(_FACE_NORMALS[i].x, 0.0, _FACE_NORMALS[i].y)
		var normal_in_frame: Vector3 = local_transform.basis * local_normal
		# taskblock-23 Pass A: "parts must project with their real vertical
		# position retained." `normal_in_frame` already CAN have a real
		# vertical component whenever `local_transform` tilts off pure yaw
		# (a pose/socket rotation about a horizontal axis — Poses.aiming()
		# rotates a shoulder -45° about local RIGHT) — only the horizontal
		# half needs the unit's own yaw applied (rotate_by_orientation is
		# 2D by construction, and yaw never touches height anyway); the
		# vertical half passes straight through unrotated.
		var world_lateral: Vector2 = rotate_by_orientation(
			Vector2(normal_in_frame.x, normal_in_frame.z), orientation
		)
		# taskblock-20 Pass C3: a `hollow` part (an empty-inside shell, not a
		# solid slab) is struck entering AND exiting — its own far face, which
		# a solid part's single near-face silhouette would normally never
		# need, projects too, at that face's own (deeper) depth. A solid
		# part still shows only whichever face(s) actually face the shooter.
		# The facing test itself stays purely horizontal — shots are still
		# level in this pass (Pass C is where a ray itself gains a vertical
		# component) — a tilted face's own horizontal-facing component is
		# still the right question for "does this face the shooter."
		if world_lateral.dot(toward_shooter) <= 0.0 and not part.hollow:
			continue  # facing away from the shooter

		var corner_a_local := Vector3(
			box.center.x + _FACE_CORNERS_A[i].x * half.x,
			box.center.y,
			box.center.z + _FACE_CORNERS_A[i].y * half.z
		)
		var corner_b_local := Vector3(
			box.center.x + _FACE_CORNERS_B[i].x * half.x,
			box.center.y,
			box.center.z + _FACE_CORNERS_B[i].y * half.z
		)
		var corner_a_in_frame: Vector3 = local_transform * corner_a_local
		var corner_b_in_frame: Vector3 = local_transform * corner_b_local
		var corner_a := Vector2(corner_a_in_frame.x, corner_a_in_frame.z)
		var corner_b := Vector2(corner_b_in_frame.x, corner_b_in_frame.z)

		var screen_a: float = rotate_by_orientation(corner_a, orientation).dot(perp)
		var screen_b: float = rotate_by_orientation(corner_b, orientation).dot(perp)

		# taskblock-23 Pass A: a face's real world footprint under a TILTED
		# `local_transform` isn't just "this lateral span at one shared
		# height" any more — the SAME lateral corners at the box's OTHER
		# vertical extreme can project to a different lateral position too,
		# once a rotation mixes height into it (and vice versa: the real
		# vertical extent can differ from a flat `box.size.y` once tilted).
		# Widen both axes across all 4 real corners (both lateral corners,
		# both vertical extremes) rather than assuming an untilted box's
		# shortcuts still hold. For any Y-axis-only rotation (every existing
		# socket in this codebase — mirrored SHOULDER_L/R, identity), height
		# is provably unaffected by the rotation and this reduces to exactly
		# the old `center_in_frame.y +/- half.y` / unchanged screen_a/screen_b
		# — this is a strict generalization, not a behavior change, for
		# every fixture that existed before this pass.
		var corner_a_low: Vector3 = (
			local_transform * Vector3(corner_a_local.x, box.center.y - half.y, corner_a_local.z)
		)
		var corner_a_high: Vector3 = (
			local_transform * Vector3(corner_a_local.x, box.center.y + half.y, corner_a_local.z)
		)
		var corner_b_low: Vector3 = (
			local_transform * Vector3(corner_b_local.x, box.center.y - half.y, corner_b_local.z)
		)
		var corner_b_high: Vector3 = (
			local_transform * Vector3(corner_b_local.x, box.center.y + half.y, corner_b_local.z)
		)
		var min_x: float = minf(screen_a, screen_b)
		var max_x: float = maxf(screen_a, screen_b)
		var min_y: float = INF
		var max_y: float = -INF
		for corner: Vector3 in [corner_a_low, corner_a_high, corner_b_low, corner_b_high]:
			var lateral: float = (
				rotate_by_orientation(Vector2(corner.x, corner.z), orientation).dot(perp)
			)
			min_x = minf(min_x, lateral)
			max_x = maxf(max_x, lateral)
			min_y = minf(min_y, corner.y)
			max_y = maxf(max_y, corner.y)
		if max_x - min_x < _MIN_FACE_WIDTH:
			continue  # edge-on: a vanishing sliver, not a real target

		# Every one of the 4 vertical corners above shares this SAME local
		# x/z (only y differs) — so this face's own depth-axis center is
		# already exactly right regardless of tilt; nothing about widening
		# the rect above changes it.
		var face_center_local: Vector2 = (corner_a + corner_b) * 0.5
		var depth: float = rotate_by_orientation(face_center_local, orientation).dot(dir)
		var rect := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
		var normal3 := Vector3(world_lateral.x, normal_in_frame.y, world_lateral.y)
		var region := Region.new(rect, depth, part, normal3)
		# taskblock-09 E: "the through axis a shot crosses" — the box's own
		# minimum dimension, regardless of which face got hit (a plate
		# authored thin along local Z stays thin no matter which of its
		# faces is visible).
		region.thickness = minf(box.size.x, minf(box.size.y, box.size.z))
		regions.append(region)

	return regions
