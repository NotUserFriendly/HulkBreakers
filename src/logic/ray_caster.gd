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

	for cell: Vector2i in state.grid.blockers:
		if not PartPicker.near_ray(
			cell, from, dir_n, UnitGeometry.true_height_for_cell(cell, state.grid)
		):
			continue
		var part: Part = state.grid.blockers[cell]
		best_t = _consider_assembly(
			best,
			best_t,
			part,
			cell,
			state.grid,
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
	for surface: Surface in state.grid.placements():
		if not PartPicker.near_ray(surface.cell, from, dir_n, surface.height):
			continue
		best_t = _consider_surface(
			best, best_t, surface, surface.cell, from, dir_n, exclude_parts, max_distance
		)

	for cell: Vector2i in state.grid.field_items:
		if not PartPicker.near_ray(
			cell, from, dir_n, UnitGeometry.true_height_for_cell(cell, state.grid)
		):
			continue
		for item: Variant in state.grid.field_items[cell]:
			# A loose Matrix has no volume to strike — never a candidate, the
			# same rule `PartPicker` and `Grid.shootable_part_at` already apply.
			if item is Part:
				best_t = _consider_assembly(
					best,
					best_t,
					item,
					cell,
					state.grid,
					from,
					dir_n,
					exclude_parts,
					max_distance,
					RayHit.KIND_FIELD_ITEM
				)

	return best


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
