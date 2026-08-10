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
## taskblock-36 Pass D: world units per `Grid.level` step — docs/PLAN.md's
## own multi-level math ("22.5 degree ramps rise 0.5/cell -> two ramps
## make one full level") makes one level exactly 1.0 world unit, not a
## number invented for this pass.
const LEVEL_HEIGHT := 1.0
## docs/09 taskblock07 Pass A: muzzle_point()'s own fallback when a weapon
## somehow has no placement at all (defensive: an operable weapon always
## has one) — roughly chest-height on the reference humanoid, the same
## value the view layer's own tracer/targeting-line fallback already used
## before this became a logic-layer concern too.
const DEFAULT_MUZZLE_HEIGHT := 1.25
## taskblock-63 Pass B: the socket type a leg attaches at, and therefore the
## one `standing_offset` measures from. An open `StringName` the way every
## socket type is — the same shape `shoulder_height` already reads `&"SHOULDER"`
## by. A body that authors no socket of this type simply has no legs to stand
## on, which is an answer rather than an error (a wall, a scrap pile, a
## legless ally in a seat).
const LEG_SOCKET_TYPE := &"HIP"


## taskblock-38 Pass C: a cell's own real, continuous world height now
## resolves against the placed `Surface` a unit standing there would
## actually be on (`GridPlacement`/`Surface`, docs/PLAN.md's floors-become-
## parts model) — never re-derived from terrain/level directly (taskblock-
## 39 Pass D retired that field/enum pair outright). `MapGen` (the one
## remaining place that still computes a height FROM its own scratch
## terrain/level, since it's what AUTHORS the surface in the first place)
## already bakes the ramp's own corrected +0.25 offset
## (`RampGeometry.STANDING_OFFSET`) into `Surface.height` at placement
## time — this just reads it back.
##
## taskblock-39 Pass C: the legacy fallback (the migration bridge's own
## pre-placement terrain/level formula, for a hand-built fixture Grid
## that never went through `GridPlacement`/`MapGen`) is gone — every
## fixture in this codebase now places real surfaces (`GridFixture`), so
## this reads the Surface path unconditionally.
static func true_height_for_cell(cell: Vector2i, grid: Grid) -> float:
	var surface: Surface = Surface.first_walkable(grid.surfaces_at(cell))
	return surface.height if surface != null else 0.0


## **The world height a blocker at `cell` actually sits at** — the tile it rests on,
## plus whatever its own placement says. taskblock-63 Pass D3.
##
## Every consumer of a blocker's geometry read `true_height_for_cell` directly, which was
## correct while a blocker had no height of its own to carry — and there were seven of
## them (`ShotPlane`, `RayCaster` in four places, `SightSpans`, `PartPicker`,
## `Detonation`, `BoardView`, the camera framing module). **Seven places re-deriving a
## height the moment one of them could disagree is the shape this project keeps paying
## for**, so it is one call now.
##
## `Blocker.height` defaults to `0.0`, which reads as "resting on the tile" — every
## blocker on every board authored before the record existed, unchanged.
static func blocker_height_for_cell(cell: Vector2i, grid: Grid) -> float:
	var blocker: Blocker = grid.blocker_at(cell)
	var placed: float = blocker.height if blocker != null else 0.0
	return true_height_for_cell(cell, grid) + placed


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
## taskblock-52 Pass B: `include_joints` — default `false`, which is every
## caller that existed before it — additionally emits one small synthetic box
## per occupied socket, at that socket's own composed transform, carrying the
## socket on the placement. Exactly what `BodyProjector._project_joint` already
## projects into the plane, so a joint is the same target to a ray march as it
## is to a projection rather than a second, nearby one. The view layer never
## asks for them: a joint is aimable, not drawn.
static func placements(
	unit: Unit,
	orientation_override: Variant = null,
	pose_override: Variant = null,
	include_joints: bool = false
) -> Array[BoxPlacement]:
	if unit.shell.root == null:
		return []
	var orientation: float = (
		orientation_override if orientation_override != null else unit.orientation
	)
	var pose: Pose = pose_override if pose_override != null else unit.pose
	return assembly_placements(
		unit.shell.root, unit.cell, orientation, pose, unit.height, include_joints
	)


## docs/10 taskblock04 C1: the same tree-walk `placements()` gives a real
## Unit's shell, generalized to any bare part tree sitting at a cell — a
## field object (a dropped assembly, a scrap pile) has no owning Unit and
## no facing of its own (orientation 0.0 by default: it doesn't face
## anything) and no pose of its own (null: it isn't posed at all).
## `placements()` is just this with a Unit's own cell/orientation/pose
## unpacked for it.
##
## taskblock-36 Pass D: `height` (0.0 by default — a field object doesn't
## sit on a `Grid.level` cell of its own the way a `Unit` does) is this
## root's own real elevation in world units. Applied to the Y translation
## ALONE, never scaled by `CELL_SIZE` (a genuinely separate axis with its
## own scale, even though both happen to equal 1.0 today).
## taskblock-37 Pass D: renamed from `level: int` (always `level *
## LEVEL_HEIGHT` at the one call site that composed it) to `height: float`
## — the resolved world height directly, since a ramp cell's real height
## is no longer a whole multiple of `LEVEL_HEIGHT` (`Unit.height`/
## `true_height_for_cell`'s own doc comment).
static func assembly_placements(
	root: Part,
	cell: Vector2i,
	orientation: float = 0.0,
	pose: Pose = null,
	height: float = 0.0,
	include_joints: bool = false
) -> Array[BoxPlacement]:
	var result: Array[BoxPlacement] = []
	_walk(
		root,
		Transform3D.IDENTITY,
		unit_transform(root, cell, orientation, height, pose),
		result,
		pose,
		include_joints
	)
	return result


## **The transform that puts an assembled body at a cell** — board position, the
## cell's real height, the body's own standing height, the facing, and the pose's
## root override, composed in that order. taskblock-63 Pass B.
##
## **Extracted because there were three copies and they are about to disagree.**
## `assembly_placements`, `shoulder_height` and `bounding_box`'s empty-body origin
## each built this expression by hand, which was harmless while it was two
## multiplications and stops being harmless the moment a term is added to it — the
## shoulder would sit at one height and the shoulder's rendered socket at another.
static func unit_transform(
	root: Part, cell: Vector2i, orientation: float, height: float, pose: Pose = null
) -> Transform3D:
	var composed := Transform3D(
		Basis(Vector3.UP, orientation),
		Vector3(cell.x * CELL_SIZE, height + standing_offset(root), cell.y * CELL_SIZE)
	)
	if pose != null and pose.overrides.has(Poses.ROOT_SOCKET_ID):
		composed = composed * (pose.overrides[Poses.ROOT_SOCKET_ID] as Transform3D)
	return composed


## **How far above the floor plane this body's own root sits, because of its legs.**
## taskblock-63 Pass B, `PLAN` NEXT 1.
##
## Before this, `assembly_placements` pinned the root at the cell's floor and the
## legs hung down from the torso's own `HIP` socket — so **a longer leg put its foot
## below the floor** instead of raising the hip, and no leg part whose length
## differed from `leg.tres`'s could be authored at all. The socket transform lives on
## the torso and is shared between every leg that ever attaches there, so the leg
## itself had nowhere to say "this body stands taller".
##
## The rule is the obvious one stated the other way round: **the feet rest on the
## floor and the body sits wherever that puts it.** So this is the negation of the
## lowest point any leg reaches in the body's own rest frame — `0.0` for the
## reference humanoid, whose 0.9-long leg hangs from a hip socket at 0.9 and whose
## cladding bottoms out at exactly the same plane. **That zero is why no existing
## unit's assembly moves**, and it is asserted directly rather than assumed.
##
## Four cases worth naming, because each is a decision:
##
## - **No legs at all** (a wall, a scrap pile, a dropped assembly, a legless ally) —
##   `0.0`. Nothing is claiming to stand, so the root stays on the floor exactly as
##   it does today.
## - **A leg shorter than its hip socket is high** — a *negative* offset, and the
##   body sinks. Deliberately not clamped at zero: "the feet rest on the floor" has
##   to hold in both directions or a short leg renders a unit hovering.
## - **Legs of different lengths** — the *deepest* one sets the height, so **no foot
##   ever passes through the floor and the shorter leg dangles.** That is the honest
##   rendering of a body with nowhere to bend: `torso.tres` carries `HIP_L`/`HIP_R`
##   but no hip *segment*, and a leg has no knee, so there is no joint that could
##   take up the difference. Making mismatched legs mean something is `PLAN`'s own
##   *legs must match* item and needs a part-tree addition, not a formula here.
## - **A destroyed leg contributes nothing**, the same `hp > 0` test `_walk` applies
##   to boxes. Lose one of a matched pair and the height is unchanged; lose both and
##   the body settles onto the floor.
##
## **Pose is deliberately not consulted.** A standing height is a fact about the
## assembly, not about what the body is currently doing, and reading the pose here
## would move a downed unit vertically the moment its root override tipped it — a
## change to every existing unit, for a case nobody asked about.
static func standing_offset(root: Part) -> float:
	if root == null:
		return 0.0
	var lowest: float = _lowest_leg_y(root, Transform3D.IDENTITY)
	if is_inf(lowest):
		return 0.0
	# **The reference humanoid measures -2.98e-8, not 0.** `Transform3D` is
	# single-precision, so composing a hip at 0.9 with a leg reaching -0.9 leaves
	# about a 30-nanometre residue — and without this, every body in the game would
	# have moved by that much on the day this landed. Snapped against the same 0.001
	# `Unit.STEP_EPSILON` every other height comparison in this codebase uses, so
	# "no existing unit's assembly changes" is exactly true rather than nearly true.
	# The cost is that a leg authored a *sub-millimetre* longer than its neighbour
	# stands the same as it — which is not a length anyone can author on purpose in a
	# game whose cells are one metre across.
	if absf(lowest) < Unit.STEP_EPSILON:
		return 0.0
	return -lowest


## The lowest world-Y any leg subtree reaches in the body's own rest frame, or `INF`
## when this body has no leg at all. `INF` rather than `0.0` because "no legs" and
## "legs that happen to bottom out at the floor" are different facts and only one of
## them should move a body.
static func _lowest_leg_y(part: Part, part_transform: Transform3D) -> float:
	var lowest: float = INF
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		var child_transform: Transform3D = part_transform * socket.current_transform()
		if socket.socket_type == LEG_SOCKET_TYPE:
			lowest = minf(lowest, _lowest_box_y(socket.occupant, child_transform))
		else:
			lowest = minf(lowest, _lowest_leg_y(socket.occupant, child_transform))
	return lowest


## The lowest world-Y any living box in `part`'s subtree reaches. All eight corners,
## not `center.y - size.y * 0.5`: a socket may carry a rotation, and the cheap
## version is right only while every joint in the chain happens to be a pure
## translation — which is true of today's authored parts and is not a rule.
static func _lowest_box_y(part: Part, part_transform: Transform3D) -> float:
	var lowest: float = INF
	if part.hp > 0:
		for box: Box in part.volume:
			var half: Vector3 = box.size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var corner: Vector3 = (
							box.center + Vector3(sx * half.x, sy * half.y, sz * half.z)
						)
						lowest = minf(lowest, (part_transform * corner).y)
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		lowest = minf(
			lowest, _lowest_box_y(socket.occupant, part_transform * socket.current_transform())
		)
	return lowest


static func _walk(
	part: Part,
	part_transform: Transform3D,
	unit_transform: Transform3D,
	result: Array[BoxPlacement],
	pose: Pose,
	include_joints: bool = false
) -> void:
	# tb61 Pass B (`BR60.02`): **left as `hp > 0`, and the attempt to unify it is why.**
	#
	# `BodyProjector.projects` returns `hp > 0 or is_mangled or is_disabled` and calls itself
	# "the *only* answer", so making this defer to it looks obviously right. It is not.
	# `Part.failure_mode` **defaults to `MANGLE`** and `wall.tres` authors none, so a destroyed
	# wall is `is_mangled` — and deferring here put its boxes back, so it went on blocking line
	# of sight and shots. `test_los.gd::test_destroying_a_wall_with_a_real_shot_clears_los_
	# through_it` caught it, and `docs/02`'s settled rule is explicit that a destroyed wall
	# clears to fully passable ground.
	#
	# **So these were never two answers to one question.** They are two different questions
	# applied in series, and the series is load-bearing: the projector asks *may this part be
	# considered at all*, and this asks *does it still have volume*. Collapsing them resurrects
	# every destroyed blocker on the board.
	#
	# The real disagreement is upstream of both — `MANGLE` as a default failure mode means
	# "almost everything is mangled at 0 hp", which is not what `Part.is_mangled`'s own
	# description ("the wreckage look", "isn't simply gone") is describing. See `BR60.02`.
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
		var child_transform: Transform3D = part_transform * socket_transform
		if include_joints:
			# taskblock-09 D's own placement, in world space: the joint sits
			# exactly where the child's local origin composes to — the same
			# transform the child's own boxes use, with a small synthetic box
			# instead of real volume. `part` is the socket's `joint_handle()`
			# placeholder, never the occupant, matching `BodyProjector`.
			result.append(
				BoxPlacement.new(
					socket.joint_handle(),
					Box.new(Vector3.ZERO, BodyProjector.JOINT_BOX_SIZE),
					unit_transform * child_transform,
					socket
				)
			)
		_walk(socket.occupant, child_transform, unit_transform, result, pose, include_joints)


## docs/10 taskblock04 A2: "compute each unit's bounding sphere from its
## ACTUAL geometry... do NOT hardcode humanoid dimensions: giant enemies are
## coming, and that is the whole reason a solver exists." Built from every
## living box's own world-space corners (`placements()` already composes
## the full unit-facing + socket-chain transform) — never a fixed torso
## height or body size. `{center, radius}`: center is the world-space AABB
## center of every corner; radius is half that AABB's diagonal. Not the
## tightest possible enclosing sphere, but simple, correct for arbitrarily
## rotated boxes, and tight enough for a framing margin check.
## **The cell a world point stands over**, the inverse of the `cell.x * CELL_SIZE` every position
## in this class is built with. taskblock-61 Pass C1.
##
## Added because a third hand-rolled copy was about to be written: `BoardPicker` already did this
## and `WallLegibility` needed it for the camera's own ground cell — and the copy CC drafted had
## quietly dropped the `/ CELL_SIZE`, which is right only while a cell happens to be 1.0 across.
## Y is ignored on purpose: a cell is a ground-plane address and carries no elevation
## (`Grid.level` was retired for saying otherwise).
static func cell_of(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / CELL_SIZE), roundi(world.z / CELL_SIZE))


static func bounding_sphere(unit: Unit, orientation_override: Variant = null) -> Dictionary:
	return sphere_of_box(bounding_box(unit, orientation_override))


## **The world-space AABB enclosing `unit`'s whole assembled body**, and the walk `bounding_sphere`
## is now derived from rather than a second opinion about.
##
## taskblock-61 Pass C1. Exposed because a caller that wants both the body's centre *and* its real
## extent had no way to ask once: `BoardView.update_wall_cutout` took `bounding_sphere(unit).center`
## and the wall-cutout sight gate took the AABB, so a real 48-box shell paid for two full
## `placements()` walks and two `placements_aabb()` passes (eight corner transforms per box) **per
## unit per frame** on a `_process` path. Measured at **181 usec of the gate's 212**, and it took
## the whole feed from 3 020 to 5 281 usec a frame for a 16-unit roster.
##
## An empty body reports a zero-size box at the unit's own origin — the same honest answer
## `_sphere_from_placements` gives, rather than an AABB assembled from infinities.
static func bounding_box(unit: Unit, orientation_override: Variant = null) -> AABB:
	var box_placements: Array[BoxPlacement] = placements(unit, orientation_override)
	if box_placements.is_empty():
		return AABB(
			unit_transform(unit.shell.root, unit.cell, unit.orientation, unit.height).origin,
			Vector3.ZERO
		)
	return placements_aabb(box_placements)


## The `{center, radius}` a box encloses. Split out so a caller holding an AABB already does not
## rebuild it to ask for the sphere.
static func sphere_of_box(box: AABB) -> Dictionary:
	return {"center": box.get_center(), "radius": box.size.length() * 0.5}


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
	# taskblock-63 Pass B: chest height above the BODY's own origin, not above the
	# cell's floor — on a long-legged shell those are no longer the same plane.
	var body: Vector3 = (
		unit_transform(unit.shell.root, unit.cell, unit.orientation, unit.height).origin
	)
	return Vector3(body.x, body.y + DEFAULT_MUZZLE_HEIGHT, body.z)


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
	# taskblock-63 Pass B: the SAME transform `assembly_placements` puts the body at,
	# standing height included — a shoulder that read the floor while the rendered
	# shoulder socket read the legs is the visual/logic disagreement taskblock-59
	# spent a block removing. Pose is not composed here, which is unchanged: this
	# answers "how high is the shoulder on this body", and `shouldered_muzzle_point`
	# is the only caller.
	return _find_shoulder(
		unit.shell.root,
		Transform3D.IDENTITY,
		unit_transform(unit.shell.root, unit.cell, unit.orientation, unit.height)
	)


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
