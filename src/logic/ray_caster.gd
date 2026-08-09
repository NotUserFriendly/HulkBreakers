class_name RayCaster
extends RefCounted

## taskblock-52 Pass B/D: **the one "what does this ray meet" query.**
##
## `ShotPlane.build` enumerated two of the board's collections (`state.units` and
## `grid.blockers`) and `PartPicker` enumerated a different two (`state.units`
## and `grid.blockers` plus `grid.field_items`), which is how floors came to be
## in neither and how `BR34.05`'s "a shot should nearly always hit something"
## became unsatisfiable. A march does not enumerate a silhouette of the world; it
## meets whatever is in the way, so membership becomes a property of the query
## rather than a list maintained per caller.
##
## **Analytic ray-vs-box, no scene tree, no physics server.** `UnitPicker.
## ray_box_hit` is the one slab test, already running on every mouse move.
## A `PhysicsDirectSpaceState` raycast would need a live `SceneTree` and would
## move shot resolution into the view layer, breaking the golden rule outright —
## it is not the swap-in this codebase's older comments describe it as.
##
## Cost is linear in what is on the board, with `PartPicker.near_ray`'s cheap
## perpendicular reject in front of the per-box test (`BR35.01`). That is a
## mitigation and not a spatial index, exactly as it is for the picker.

## How close two hits' `t` must be to count as the same distance. Ties are a
## real geometric case here rather than a numerical accident: adjacent wall cells
## share a face plane exactly, so a ray crossing that plane meets both at the
## identical `t`. Sized well below any real geometry (a cell is 1.0 across) and
## well above float noise on distances of tens of units.
const TIE_EPSILON := 0.0001

## How far short of the far endpoint a sight query stops. Sized like `TIE_EPSILON` — well below
## any real geometry, well above float noise — and load-bearing for the same reason the endpoint
## exemption is: the thing at the far end is what you are looking at, never what is in the way.
const _ENDPOINT_MARGIN := 0.0001


## The nearest thing the ray meets, or null.
##
## `exclude_parts` skips those parts entirely — the shooter's own body on a first
## hop, the body just bounced off on a ricochet. Same convention, and the same
## reason, `DamageResolver.resolve_shot` already uses: the ray's origin sits at
## or inside the shooter, so without it a shot resolves against its own chest.
##
## `log` is optional and is only ever written to by the tie stages
## (`RayTiebreak`), because a stage that fires once in ten thousand shots is a
## path nobody ever sees run.
static func cast(
	state: CombatState,
	from: Vector3,
	dir: Vector3,
	exclude_parts: Array[Part] = [],
	max_distance: float = INF,
	log: CombatLog = null
) -> RayHit:
	var tied: Array[RayHit] = tied_candidates(state, from, dir, exclude_parts, max_distance)
	if tied.is_empty():
		return null
	if tied.size() == 1:
		return tied[0]
	return RayTiebreak.resolve(tied, from, dir.normalized(), log)


## Every hit sharing the nearest `t`, nearest-first-and-only. Usually one; more
## than one exactly when the ray crosses a shared face plane. Exposed so the tie
## stages can be tested against a real tie rather than a constructed list, and so
## a caller that wants to reason about ties itself can.
static func tied_candidates(
	state: CombatState,
	from: Vector3,
	dir: Vector3,
	exclude_parts: Array[Part] = [],
	max_distance: float = INF
) -> Array[RayHit]:
	var dir_n: Vector3 = dir.normalized()
	if dir_n.is_zero_approx():
		return []
	var best: Array[RayHit] = []
	var best_t: float = INF

	for unit: Unit in state.units:
		if not unit.alive:
			continue
		var root := Vector3(
			unit.cell.x * UnitGeometry.CELL_SIZE, unit.height, unit.cell.y * UnitGeometry.CELL_SIZE
		)
		for placement: BoxPlacement in UnitGeometry.placements(unit, null, null, true):
			best_t = _consider(
				best,
				best_t,
				placement,
				from,
				dir_n,
				exclude_parts,
				max_distance,
				unit,
				unit.cell,
				root,
				RayHit.KIND_JOINT if placement.socket != null else RayHit.KIND_UNIT
			)

	_geometry_into(best, best_t, state.grid, from, dir_n, exclude_parts, max_distance)
	return best


## Everything the ray meets that is **not a unit** — blockers, placed surfaces, loose field
## items. taskblock-58 Pass C.
##
## Sight is a question about the world, not about who is standing in it: a body does not make a
## cell opaque, and `LoS` asking the full march would have every unit blocking vision through
## itself. This is the same march with the unit loop left off, **not a second one** — the reject,
## the per-box slab test and the placement enumeration are literally the same calls, so the thing
## `LoS` sees and the thing a round meets cannot drift apart.
##
## Takes a `Grid` rather than a `CombatState` for the same reason: a query with no units in it
## has no business being handed the unit list.
static func geometry_candidates(
	grid: Grid,
	from: Vector3,
	dir: Vector3,
	exclude_parts: Array[Part] = [],
	max_distance: float = INF
) -> Array[RayHit]:
	var dir_n: Vector3 = dir.normalized()
	if dir_n.is_zero_approx():
		return []
	var best: Array[RayHit] = []
	_geometry_into(best, INF, grid, from, dir_n, exclude_parts, max_distance)
	return best


## The nearest piece of world geometry along the ray, or null. No tie stages: a tie between two
## wall cells sharing a face plane is a real geometric case, but nothing asking *"is anything in
## the way"* cares which of them it was.
static func cast_geometry(
	grid: Grid,
	from: Vector3,
	dir: Vector3,
	exclude_parts: Array[Part] = [],
	max_distance: float = INF
) -> RayHit:
	var candidates: Array[RayHit] = geometry_candidates(
		grid, from, dir, exclude_parts, max_distance
	)
	return null if candidates.is_empty() else candidates[0]


## True when world geometry stands between `from` and `to`. **The sight predicate**, and the one
## thing `LoS` is built on.
##
## `exclude_parts` is how the endpoint exemption is expressed: a wall cell can always see out of
## and be seen into, which used to be `LoS` skipping the first and last cell of its supercover
## walk and is now the two endpoints' own parts being taken off the board for this one query.
## Stating it as an exclusion rather than as an index range is what lets it survive a world where
## a line is not a list of cells.
## ## An any-hit loop, not the nearest-hit one
##
## `cast_geometry` builds a `RayHit` per candidate and tracks the nearest. **A boolean needs
## neither**: a nearest hit exists exactly when any hit does, so stopping at the first one is the
## same answer arrived at sooner. Measured on a generated board, the nearest-hit form cost
## **999 usec** per sight line — a `RayHit` allocated per hit, every candidate tested even after a
## wall had already been found, and `UnitGeometry.true_height_for_cell` paid for all 218 blockers
## before any of them were rejected.
##
## **This is the same geometry, not a second model.** `PartPicker.near_ray`, `UnitGeometry.
## assembly_placements` and `UnitPicker.ray_box_hit` are the identical calls `cast_geometry`
## makes; only the bookkeeping differs.
## `test_sight_geometry.gd::test_the_any_hit_loop_agrees_with_the_nearest_hit_march` sweeps the two
## against each other, because "it is the same test with less bookkeeping" is exactly the kind of
## claim that should be checked rather than asserted in a comment.
static func obstructed(
	grid: Grid, from: Vector3, to: Vector3, exclude_parts: Array[Part] = []
) -> bool:
	var span: Vector3 = to - from
	var distance: float = span.length()
	if distance <= 0.0001:
		return false
	var dir: Vector3 = span / distance
	# **Short of the destination, not up to it.** A ray that ends exactly on the far endpoint
	# meets whatever geometry sits at that endpoint, which is the thing being looked at rather
	# than something in the way.
	var limit: float = distance - _ENDPOINT_MARGIN

	for cell: Vector2i in grid.blockers:
		if _blocker_in_the_way(grid, cell, from, dir, limit, exclude_parts):
			return true

	var y_low: float = minf(from.y, to.y)
	var y_high: float = maxf(from.y, to.y)
	for surface: Surface in grid.placements():
		if surface.part == null or exclude_parts.has(surface.part):
			continue
		if not BodyProjector.projects(surface.part):
			continue
		if not PartPicker.near_ray(surface.cell, from, dir, surface.height):
			continue
		if _below_or_above(surface, y_low, y_high):
			continue
		if _any_box_hit(
			UnitGeometry.assembly_placements(
				surface.part, surface.cell, surface.facing, null, surface.height
			),
			from,
			dir,
			limit
		):
			return true

	for cell: Vector2i in grid.field_items:
		if not PartPicker.near_ray_flat(cell, from, dir):
			continue
		var item_height: float = UnitGeometry.true_height_for_cell(cell, grid)
		if not PartPicker.near_ray(cell, from, dir, item_height):
			continue
		for item: Variant in grid.field_items[cell]:
			# A loose Matrix has no volume, so nothing for a sight line to meet either.
			if item is Part and not exclude_parts.has(item) and BodyProjector.projects(item):
				if _any_box_hit(
					UnitGeometry.assembly_placements(item, cell, 0.0, null, item_height),
					from,
					dir,
					limit
				):
					return true
	return false


## True when a placed surface sits entirely clear of the sight line's own vertical band, so there
## is no need to build its box placements at all.
##
## **The cheapest reject there is for the commonest case.** A board is mostly floor, so a sight
## line's `near_ray` filter admits a hundred-odd floor tiles it then builds placements for and
## misses — measured at 1.82 usec of allocation each. A near-horizontal line at eye height clears
## every one of them by more than a metre.
##
## **Only taken when it is exact.** The Y extent is read off the part's own `volume` boxes, which
## is the whole story for a part with nothing socketed onto it — a yaw `facing` cannot change a Y
## extent. A part with an occupied socket has geometry this does not account for, so it falls
## through to the full test rather than guessing about it.
static func _below_or_above(surface: Surface, y_low: float, y_high: float) -> bool:
	for socket: Socket in surface.part.sockets:
		if socket.occupant != null:
			return false
	var lowest: float = INF
	var highest: float = -INF
	for box: Box in surface.part.volume:
		lowest = minf(lowest, box.center.y - box.size.y * 0.5)
		highest = maxf(highest, box.center.y + box.size.y * 0.5)
	if is_inf(lowest):
		return true
	return surface.height + highest < y_low or surface.height + lowest > y_high


## **One blocker, tested against one ray** — the body of `obstructed`'s own first loop, lifted so a
## caller can supply its own candidate cells instead of the whole `grid.blockers` collection.
##
## The cheap tests first, in cost order: an excluded or destroyed part costs a lookup, the
## ground-plane reject costs no height, and only what survives both pays for one.
static func _blocker_in_the_way(
	grid: Grid,
	cell: Vector2i,
	from: Vector3,
	dir: Vector3,
	limit: float,
	exclude_parts: Array[Part]
) -> bool:
	var part: Part = grid.blockers.get(cell)
	if part == null or exclude_parts.has(part) or not BodyProjector.projects(part):
		return false
	if not PartPicker.near_ray_flat(cell, from, dir):
		return false
	var height: float = UnitGeometry.true_height_for_cell(cell, grid)
	if not PartPicker.near_ray(cell, from, dir, height):
		return false
	return _any_box_hit(
		UnitGeometry.assembly_placements(part, cell, 0.0, null, height), from, dir, limit
	)


## **Is a blocker standing in any of `cells` in the way between `from` and `to`?** taskblock-61
## Pass C1 — the same per-blocker test `obstructed` runs, over a candidate set the caller chose.
##
## `RayCaster`'s own header: *"membership becomes a property of the query rather than a list
## maintained per caller."* This is that, taken one step further — the candidate *cells* are the
## query's business too. `obstructed` asks about every blocker on the board because a shot has to;
## the wall cutout's sight gate (`WallLegibility.sight_blocked_to_unit`) knows the ray's own
## supercover line and has to answer three times per unit per frame on a `_process` path.
##
## **Measured, because the first shape of this was shipped on an assumption and the assumption was
## wrong.** Walking all 217 blockers of a real 32x24 board cost **629 usec** for the gate's three
## rays — over 10 ms a frame for a 16-unit roster, a framerate defect manufactured by a
## correctness fix. `PartPicker.SKIP_RADIUS` is 3.0 and deliberately generous, so the cheap
## ground-plane reject admits a six-cell-wide strip of the whole board and every blocker is
## iterated regardless. Handing in the line's own cells is what makes the gate affordable; see
## `test_cutout_gate_cost_probe.gd` for the current numbers.
##
## **Conservative in one direction only, stated so it is not mistaken for exact:** a caller passing
## a supercover line gets the cells the ray's ground track crosses. A part whose boxes overhang its
## own cell (`SKIP_RADIUS`'s own reason for existing) could in principle be missed. Walls are
## exactly one cell across and cannot; authored cover could.
## **The cell of the first blocker in the way, or `null`.** Returns the cell rather than a bool so
## the wall cutout can log *which* wall it blamed — the `BR32.05` diagnostic, since a gate that
## disagrees with what the supervisor sees is only settleable by naming the geometry it found.
##
## **Several rays from one origin, one walk.** `to_points` are all tested against each candidate
## cell before moving to the next — not one full walk per point. The cutout gate casts three rays
## at one body (centre, feet, head) and the per-cell work they share is most of the cost: the
## `grid.blockers` lookup, the null/exclude/destroyed checks, the cell's own height, and
## `assembly_placements`' allocation.
static func blocker_obstructed_among(
	grid: Grid,
	cells: Array[Vector2i],
	from: Vector3,
	to_points: Array[Vector3],
	exclude_parts: Array[Part] = []
) -> Variant:
	var dirs: Array[Vector3] = []
	var limits: Array[float] = []
	for to: Vector3 in to_points:
		var span: Vector3 = to - from
		var distance: float = span.length()
		if distance <= 0.0001:
			continue
		dirs.append(span / distance)
		limits.append(distance - _ENDPOINT_MARGIN)
	if dirs.is_empty():
		return null

	for cell: Vector2i in cells:
		var part: Part = grid.blockers.get(cell)
		if part == null or exclude_parts.has(part) or not BodyProjector.projects(part):
			continue
		var height: float = UnitGeometry.true_height_for_cell(cell, grid)
		# Built at most once per cell, and only for a cell some ray actually reaches — the
		# allocation is what made this worth sharing rather than the arithmetic.
		var box_placements: Array[BoxPlacement] = []
		for i in range(dirs.size()):
			if not PartPicker.near_ray_flat(cell, from, dirs[i]):
				continue
			if not PartPicker.near_ray(cell, from, dirs[i], height):
				continue
			if box_placements.is_empty():
				box_placements = UnitGeometry.assembly_placements(part, cell, 0.0, null, height)
			if _any_box_hit(box_placements, from, dirs[i], limits[i]):
				return cell
	return null


static func _any_box_hit(
	placements: Array[BoxPlacement], from: Vector3, dir: Vector3, limit: float
) -> bool:
	for placement: BoxPlacement in placements:
		var hit: Dictionary = UnitPicker.ray_box_hit(placement, from, dir)
		if not hit.is_empty() and float(hit["t"]) <= limit:
			return true
	return false


static func _geometry_into(
	best: Array[RayHit],
	best_t: float,
	grid: Grid,
	from: Vector3,
	dir_n: Vector3,
	exclude_parts: Array[Part],
	max_distance: float
) -> float:
	var result: float = best_t
	for cell: Vector2i in grid.blockers:
		if not PartPicker.near_ray(
			cell, from, dir_n, UnitGeometry.true_height_for_cell(cell, grid)
		):
			continue
		var part: Part = grid.blockers[cell]
		result = _consider_assembly(
			best,
			result,
			part,
			cell,
			grid,
			from,
			dir_n,
			exclude_parts,
			max_distance,
			RayHit.KIND_BLOCKER
		)

	# taskblock-52 Pass D: **floors.** `ShotPlane.build` never looked at
	# `grid.surfaces`, which is the whole of `BR34.05`'s "or the floor" half —
	# a round angled slightly down had nothing to intersect, so "miss" was not a
	# wrong branch being taken, it was the only branch that existed. `Surface`
	# already carries a real `Part` (taskblock-38 made floor and terrain into
	# parts), so this needs no stand-in type and no new outcome.
	#
	# **A cell can hold several surfaces** — a catwalk over a floor is the stated
	# case — so every one is marched, not just the first walkable.
	#
	# taskblock-58 Pass B: **one flat walk of the store**, since a placement now carries
	# its own cell. The old form asked the index for a cell list and then asked it again
	# per cell for that cell's surfaces — a dictionary lookup per cell, per ray cast,
	# to rebuild a list the store already holds in order.
	for surface: Surface in grid.placements():
		if not PartPicker.near_ray(surface.cell, from, dir_n, surface.height):
			continue
		result = _consider_surface(
			best, result, surface, surface.cell, from, dir_n, exclude_parts, max_distance
		)

	for cell: Vector2i in grid.field_items:
		if not PartPicker.near_ray(
			cell, from, dir_n, UnitGeometry.true_height_for_cell(cell, grid)
		):
			continue
		for item: Variant in grid.field_items[cell]:
			# A loose Matrix has no volume to strike — never a candidate, the
			# same rule `PartPicker` and `Grid.shootable_part_at` already apply.
			if item is Part:
				result = _consider_assembly(
					best,
					result,
					item,
					cell,
					grid,
					from,
					dir_n,
					exclude_parts,
					max_distance,
					RayHit.KIND_FIELD_ITEM
				)
	return result


## One placed surface, at **its own** height and facing.
##
## Not routed through `_consider_assembly`, and the difference is real: that one
## reads `true_height_for_cell`, which resolves to the cell's *first walkable*
## surface. A cell with two surfaces stacked would then place both at the lower
## one's height. A `Surface` knows where it is; it is asked.
##
## `surface.facing` is passed as the orientation — the same radians convention
## `Unit.orientation` uses, which is what makes a `ramp` directional (taskblock-38
## Pass C) and composes through the identical transform chain with no translation
## step.
static func _consider_surface(
	best: Array[RayHit],
	best_t: float,
	surface: Surface,
	cell: Vector2i,
	from: Vector3,
	dir_n: Vector3,
	exclude_parts: Array[Part],
	max_distance: float
) -> float:
	var root_origin := Vector3(
		cell.x * UnitGeometry.CELL_SIZE, surface.height, cell.y * UnitGeometry.CELL_SIZE
	)
	var result: float = best_t
	var placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		surface.part, cell, surface.facing, null, surface.height
	)
	for placement: BoxPlacement in placements:
		result = _consider(
			best,
			result,
			placement,
			from,
			dir_n,
			exclude_parts,
			max_distance,
			surface.part,
			cell,
			root_origin,
			RayHit.KIND_SURFACE
		)
	return result


## One object's whole assembly tree, at its cell's **real** height.
##
## `BR52.01`: `UnitGeometry.assembly_placements` defaults `height` to 0.0, and
## `PartPicker` took that default while `BoardView._spawn_blocker` passes
## `true_height_for_cell`. On a raised cell that put the hittable volume
## somewhere the mesh is not, contradicting `docs/10`'s "render is hitbox". The
## height is passed here, and `PartPicker` now passes it too.
static func _consider_assembly(
	best: Array[RayHit],
	best_t: float,
	root: Part,
	cell: Vector2i,
	grid: Grid,
	from: Vector3,
	dir_n: Vector3,
	exclude_parts: Array[Part],
	max_distance: float,
	kind: StringName
) -> float:
	var height: float = UnitGeometry.true_height_for_cell(cell, grid)
	var root_origin := Vector3(
		cell.x * UnitGeometry.CELL_SIZE, height, cell.y * UnitGeometry.CELL_SIZE
	)
	var result: float = best_t
	for placement: BoxPlacement in UnitGeometry.assembly_placements(root, cell, 0.0, null, height):
		result = _consider(
			best,
			result,
			placement,
			from,
			dir_n,
			exclude_parts,
			max_distance,
			root,
			cell,
			root_origin,
			kind
		)
	return result


## Tests one box and folds the outcome into the running nearest set. Returns the
## new best `t`. A hit strictly nearer than the current best **replaces** the set;
## one within `TIE_EPSILON` joins it.
static func _consider(
	best: Array[RayHit],
	best_t: float,
	placement: BoxPlacement,
	from: Vector3,
	dir_n: Vector3,
	exclude_parts: Array[Part],
	max_distance: float,
	body: Variant,
	cell: Vector2i,
	root_origin: Vector3,
	kind: StringName
) -> float:
	if exclude_parts.has(placement.part):
		return best_t
	var raw: Dictionary = UnitPicker.ray_box_hit(placement, from, dir_n)
	if raw.is_empty():
		return best_t
	var t: float = raw["t"]
	if t > max_distance or t > best_t + TIE_EPSILON:
		return best_t

	var hit := RayHit.new()
	hit.part = placement.part
	hit.socket = placement.socket
	hit.body = body
	hit.cell = cell
	hit.kind = kind
	hit.t = t
	hit.point = from + dir_n * t
	hit.normal = raw["normal"]
	hit.inside = raw["inside"]
	hit.exit_t = raw["t_exit"]
	hit.exit_point = from + dir_n * float(raw["t_exit"])
	hit.exit_normal = raw["exit_normal"]
	hit.thickness = minf(placement.box.size.x, minf(placement.box.size.y, placement.box.size.z))
	hit.root_origin = root_origin
	hit.placement = placement

	if t < best_t - TIE_EPSILON:
		best.clear()
		best.append(hit)
		return t
	best.append(hit)
	return minf(best_t, t)
