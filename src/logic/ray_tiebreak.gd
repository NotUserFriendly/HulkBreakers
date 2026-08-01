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


## Picks one hit from a genuine tie and logs which stage did it. `candidates`
## must hold at least two entries; `RayCaster` never calls this otherwise.
##
## **Stage 2 (the swept box) is not wired in yet** — taskblock-52 Pass C builds it,
## with the log below as its evidence that it ever runs. Until then a tie the
## raycast cannot split goes straight to closest root, which is the stage that has
## to be right regardless, since the axis-aligned case falls through to it by
## design even once the box cast exists.
static func resolve(candidates: Array[RayHit], from: Vector3, log: CombatLog = null) -> RayHit:
	var winner: RayHit = _by_closest_root(candidates, from)
	var stage: StringName = STAGE_CLOSEST_ROOT
	if winner == null:
		winner = _by_stable_order(candidates)
		stage = STAGE_STABLE_ORDER
	_log(candidates, winner, stage, log)
	return winner


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
