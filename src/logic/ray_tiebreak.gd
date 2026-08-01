class_name RayTiebreak
extends RefCounted

## taskblock-52 Pass C: **which of several things met at the same distance takes
## the hit.**
##
## ## What can actually tie is narrower than it looks
##
## Units are lumpy part trees and cannot share a cell with a wall, so a
## unit-versus-wall tie is effectively impossible. The realistic case is
## **wall versus wall**: adjacent cells whose boxes share a face plane exactly,
## met by a ray crossing that plane at one `t`.
##
## ## And a tie is benign
##
## A shared plane means the ray hits *at least one* of them, so the gap
## `BR34.05` describes cannot arise here. **A tie is an attribution question —
## which cell takes the damage — never a hit-or-miss one.** That is why this file
## is allowed to be simple.
##
## ## Three stages, each reached only when the one above does not resolve
##
## 1. **Raycast.** Resolves nearly always; by the time anything reaches here it
##    already has not.
## 2. **Box cast, over the tied candidates only.** Handed the set the ray already
##    found, it arbitrates within it — it cannot add a hit or widen the
##    projectile. Swept along the ray, it leads with a corner and separates two
##    faces one flat cast would meet together. **When the ray is axis-aligned the
##    box is too**, and meets both symmetrically, so that subcase falls through
##    to stage 3 by design.
## 3. **Closest root.** Not type priority — the realistic tie is same-type, where
##    a type rule is a no-op. The shooter is the ray's own root; each candidate's
##    root is its own object. The gun is offset from the unit's centreline and
##    two cells' centres differ, so root-to-root distance separates them, and the
##    arithmetic is cell-aligned and cheap.
##
## **Every tie writes to the combat log, naming the stage that resolved it.**
## Neither the supervisor nor CC knows the tie rate; a stage that fires once in
## ten thousand shots is a path nobody ever sees run, which is exactly the
## failure this project keeps producing. The log is what turns stage 2 from
## insurance into something with evidence behind it.

const STAGE_BOX_CAST: StringName = &"box_cast"
const STAGE_CLOSEST_ROOT: StringName = &"closest_root"
const STAGE_STABLE_ORDER: StringName = &"stable_order"

## How much nearer one candidate's swept-box or root distance must be to count as
## genuinely nearer rather than the same. Matched to `RayCaster.TIE_EPSILON` for
## the same reason: below any real geometry, above float noise.
const SEPARATION_EPSILON := 0.0001

## The arbiter probe's half-width, in world units.
##
## **This is not a projectile width and must not become one.** The taskblock is
## explicit that box casting as a weapon property — a shotgun pellet and a sniper
## round wanting different thicknesses — is a design lever for later, and that
## letting a tiebreak dictate the weapon model would be the wrong reason to build
## it. This exists only to give the probe a corner that can lead, so it is
## deliberately tiny against a 1.0 cell: big enough to separate two cells at any
## real angle, small enough that it could never reach anything the ray did not.
## A flagged, tunable constant, not a balance number.
const PROBE_RADIUS := 0.05


## Picks one hit from a genuine tie and logs which stage did it. `candidates`
## must hold at least two entries; `RayCaster` never calls this otherwise.
static func resolve(
	candidates: Array[RayHit], from: Vector3, dir_n: Vector3, log: CombatLog = null
) -> RayHit:
	var winner: RayHit = _by_box_cast(candidates, from, dir_n)
	var stage: StringName = STAGE_BOX_CAST
	if winner == null:
		winner = _by_closest_root(candidates, from)
		stage = STAGE_CLOSEST_ROOT
	if winner == null:
		winner = _by_stable_order(candidates)
		stage = STAGE_STABLE_ORDER
	_log(candidates, winner, stage, log)
	return winner


## Stage 2. **An arbiter over the tied set, never a second cast.** It iterates
## `candidates` alone and returns one of them, so it is structurally incapable of
## reporting a body the raycast did not already find — the property the taskblock
## asks to be asserted, and it is, in `test_ray_tiebreak.gd`.
##
## The probe is a box **aligned to the ray**, swept along it, represented by the
## four corner rays of its cross-section. Each candidate is scored by the earliest
## `t` any corner reaches it; the lowest score wins.
##
## **Why a corner leads, and why an axis-aligned ray has none.** For a ray at
## angle theta to the world axes, the cross-section basis is tilted with it, so
## the corner on one side sits fractionally further downrange than the corner on
## the other and reaches the shared face plane first — and the side it favours is
## the one the ray is angling away from, which is a real geometric fact about the
## approach rather than a coin flip. At theta = 0 the tilt vanishes, both corners
## sit at the same distance, and the scores come out equal: **that subcase falls
## through to stage 3 by design.** Null is returned then, not a guess.
static func _by_box_cast(candidates: Array[RayHit], from: Vector3, dir_n: Vector3) -> RayHit:
	var best: RayHit = null
	var best_score: float = INF
	var contested := false
	for hit: RayHit in candidates:
		if hit.placement == null:
			return null  # nothing to re-probe against; leave it to the next stage
		var score: float = _earliest_corner_t(hit, from, dir_n)
		if score == INF:
			continue
		if score < best_score - SEPARATION_EPSILON:
			best = hit
			best_score = score
			contested = false
		elif absf(score - best_score) <= SEPARATION_EPSILON:
			contested = true
	return null if contested else best


## The earliest `t` at which any of the swept probe's four corners reaches this
## candidate's own box, or INF if none of them do.
static func _earliest_corner_t(hit: RayHit, from: Vector3, dir_n: Vector3) -> float:
	var earliest: float = INF
	for corner: Vector3 in _corner_offsets(dir_n):
		var raw: Dictionary = UnitPicker.ray_box_hit(hit.placement, from + corner, dir_n)
		if raw.is_empty():
			continue
		earliest = minf(earliest, float(raw["t"]))
	return earliest


## The probe's cross-section corners, in the plane perpendicular to the ray.
##
## The reference axis swaps for a near-vertical ray, where `UP` would be
## degenerate — a shot fired straight down is exactly the case a floor makes
## ordinary, so it cannot be left to produce a zero-length cross product.
static func _corner_offsets(dir_n: Vector3) -> Array[Vector3]:
	var reference: Vector3 = Vector3.RIGHT if absf(dir_n.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var right: Vector3 = dir_n.cross(reference).normalized()
	var up: Vector3 = right.cross(dir_n).normalized()
	return [
		right * PROBE_RADIUS + up * PROBE_RADIUS,
		right * PROBE_RADIUS - up * PROBE_RADIUS,
		-right * PROBE_RADIUS + up * PROBE_RADIUS,
		-right * PROBE_RADIUS - up * PROBE_RADIUS,
	]


## Stage 3. Null when two candidates' roots are equidistant, which sends the
## caller to the stable order below rather than letting a coin land on its edge.
static func _by_closest_root(candidates: Array[RayHit], from: Vector3) -> RayHit:
	var best: RayHit = null
	var best_distance: float = INF
	var contested := false
	for hit: RayHit in candidates:
		var distance: float = from.distance_to(hit.root_origin)
		if distance < best_distance - SEPARATION_EPSILON:
			best = hit
			best_distance = distance
			contested = false
		elif absf(distance - best_distance) <= SEPARATION_EPSILON:
			contested = true
	return null if contested else best


## The last resort, and it is **geometric rather than dictionary order**.
##
## Godot iterates a `Dictionary` in insertion order, which for `grid.blockers` is
## map-generation order and therefore seeded and reproducible — but that is a
## guarantee about the generator, not about the resolver, and it would quietly
## stop holding the first time anything re-inserted a cell. Sorting on the cell
## and then the part id makes the answer a property of where things are, which is
## a **stronger** determinism guarantee than the plane's own `sort_custom` over
## dictionary iteration ever had.
static func _by_stable_order(candidates: Array[RayHit]) -> RayHit:
	var sorted: Array[RayHit] = candidates.duplicate()
	sorted.sort_custom(
		func(a: RayHit, b: RayHit) -> bool:
			if a.cell.x != b.cell.x:
				return a.cell.x < b.cell.x
			if a.cell.y != b.cell.y:
				return a.cell.y < b.cell.y
			return String(a.part.id) < String(b.part.id)
	)
	return sorted[0]


static func _log(
	candidates: Array[RayHit], winner: RayHit, stage: StringName, log: CombatLog
) -> void:
	if log == null:
		return
	var cells: Array[String] = []
	for hit: RayHit in candidates:
		cells.append("%s:%s" % [hit.cell, hit.part.id])
	(
		log
		. emit(
			(
				LogEvent
				. new(
					0,
					Enums.Phase.RESOLUTION,
					-1,
					&"ray_tie",
					{
						"stage": stage,
						"candidates": candidates.size(),
						"winner_cell_x": winner.cell.x,
						"winner_cell_y": winner.cell.y,
						"winner_part": winner.part.id,
						"t": winner.t,
					},
					(
						"%d candidates tied at t=%.5f, resolved by %s -> %s (%s)"
						% [candidates.size(), winner.t, stage, winner.part.id, ", ".join(cells)]
					)
				)
			)
		)
	)
