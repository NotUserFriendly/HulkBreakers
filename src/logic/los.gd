class_name LoS
extends RefCounted

## **Can A see B — asked of the geometry, and of nothing else.** taskblock-58 Pass C.
##
## Three things used to answer this question. `LoS` walked `Grid.line` reading `Grid.opacity`, a
## flat per-cell float array; `VisibilityField` shadowcast from that same array and recorded its
## own limit in its own doc comment (*occlusion data here is 2D, per cell, with no per-level*);
## and `RayCaster` marched the real 3D boxes. **Geometry already knew what blocks, and a parallel
## flat array also claimed to** — which is the no-parallel-systems rule broken in the open.
##
## `Grid.opacity` is retired. A wall blocks sight because it is a wall, not because a cell was
## flagged, and everything follows from that:
##
## - **Height comes for free.** A 1.0 wall stops blocking sight to a unit standing at 3.0, which
##   it did not before, because the array had no height in it.
## - **`DamageResolver` stops clearing a flag** when a wall dies. Destroying the geometry *is*
##   clearing it, and the flag it used to clear was the one thing standing between a shot-out wall
##   and the sight line through the hole.
## - **The editor's `sight_blocking` tool retires with the array.** There is nothing left to author.
## - **Gases and windows are the exception, not the rule.** They arrive later as volumes carrying
##   a transmission property. Opaque by declaration is the wrong default; opaque by being there is
##   the right one.
##
## ## What a sight line actually is
##
## Two points, cast through `RayCaster.obstructed` — the same march, the same reject and the same
## slab test a round takes, with the unit loop left off (`RayCaster.geometry_candidates`). Units
## do not block sight: a body standing in the way is a shot-resolution concern the shot plane
## answers, and treating one as opaque would have every unit blind to everything behind itself.

## How high above a cell's own walkable surface a sight line runs.
##
## **Flagged, not designed** (CLAUDE.md). It is `UnitGeometry.DEFAULT_MUZZLE_HEIGHT` because a
## sight line and a shot line wanting the same height is the honest default — every production
## caller of `has_los` is gating or scoring a *shot* — and inventing a second, differently-named
## constant for the eye would be a balance number presented as design. The real answer arrives
## with a per-shell sensor height, at which point this becomes the fallback rather than the rule.
const SIGHT_HEIGHT: float = UnitGeometry.DEFAULT_MUZZLE_HEIGHT


## True if no world geometry stands between `a` and `b`.
##
## **The two endpoint cells never block sight to or from themselves** — the same exemption the old
## supercover walk expressed by skipping the first and last cell of its line, restated as the two
## cells' own parts being excluded from this one query. A unit standing in a doorway can see out
## of it; a wall cell can be seen into.
##
## The corner-blocking rule the supercover walk gave for free is now geometric rather than
## stipulated: two wall cells meeting at a corner share a face plane, and a ray threading the
## lattice point between them meets one of them, because the boxes are actually there.
static func has_los(grid: Grid, a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	return not RayCaster.obstructed(
		grid, sight_point(grid, a), sight_point(grid, b), _endpoints(grid, a, b)
	)


## Where a sight line starts and ends for a cell: `SIGHT_HEIGHT` above whatever that cell's own
## walkable surface stands at. An unfloored cell reports 0.0 — the same answer
## `UnitGeometry.true_height_for_cell` already gives every other caller, rather than a second
## opinion about where a floor that is not there would be.
static func sight_point(grid: Grid, cell: Vector2i) -> Vector3:
	return Vector3(
		float(cell.x) * UnitGeometry.CELL_SIZE,
		UnitGeometry.true_height_for_cell(cell, grid) + SIGHT_HEIGHT,
		float(cell.y) * UnitGeometry.CELL_SIZE
	)


## Every part standing at either endpoint cell — what the endpoint exemption excludes.
##
## Blockers, placed surfaces and loose field items alike: a unit on a catwalk is standing *on* a
## surface whose box its own sight line begins inside, and a floor that blinded whoever stood on
## it would be a spectacular way to fail this pass.
static func _endpoints(grid: Grid, a: Vector2i, b: Vector2i) -> Array[Part]:
	var parts: Array[Part] = []
	for cell: Vector2i in [a, b]:
		parts.append_array(grid.parts_at(cell))
	return parts


## All cells within Chebyshev `radius` of origin (inclusive) that have LoS
## from origin. Includes origin itself.
static func visible_cells(grid: Grid, origin: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var y_start: int = maxi(origin.y - radius, 0)
	var y_end: int = mini(origin.y + radius, grid.rows - 1)
	var x_start: int = maxi(origin.x - radius, 0)
	var x_end: int = mini(origin.x + radius, grid.width - 1)

	for y in range(y_start, y_end + 1):
		for x in range(x_start, x_end + 1):
			var cell := Vector2i(x, y)
			if Grid.distance_chebyshev(origin, cell) > radius:
				continue
			if has_los(grid, origin, cell):
				result.append(cell)

	return result
