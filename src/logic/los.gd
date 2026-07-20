class_name LoS
extends RefCounted

## Line of sight over a Grid's opacity field. Cover (Grid.blockers) never
## blocks vision — only opacity does; cover is a hit-resolution concern (Phase 6).

const OPAQUE_THRESHOLD: float = 1.0


## True if nothing opaque sits strictly between a and b. The two endpoint
## cells' own opacity never blocks sight to/from themselves. Because
## Grid.line is a symmetric supercover (both cells bordering an exact corner
## crossing are included), a single opaque cell at a corner is enough to
## block a diagonal shot through that gap — the "corner-blocking rule".
static func has_los(grid: Grid, a: Vector2i, b: Vector2i) -> bool:
	var cells: Array[Vector2i] = Grid.line(a, b)
	for i in range(1, cells.size() - 1):
		if grid.get_opacity(cells[i]) >= OPAQUE_THRESHOLD:
			return false
	return true


## taskblock-27 (CC, re-diagnosing tb26 B2 a second time — confirmed still
## broken on a real bout's own combat log, every playstyle frozen from
## Turn 2 onward): how many opaque cells sit between `a` and `b` — 0 means
## `has_los` would return true. Unlike a boolean, this is a MONOTONIC
## signal a scorer can climb even while no candidate cell has full LOS
## yet: working around a corner reduces the obstruction count one wall at
## a time, where raw Chebyshev distance-to-preferred-range can plateau or
## even worsen mid-detour (the exact freeze this exists to fix — see
## `UnitAI._engagement_score`'s own use of it). Same `Grid.line` walk
## `has_los` already does, just counting instead of early-exiting on the
## first hit — never a second, differently-shaped visibility test.
static func obstruction_count(grid: Grid, a: Vector2i, b: Vector2i) -> int:
	var cells: Array[Vector2i] = Grid.line(a, b)
	var count := 0
	for i in range(1, cells.size() - 1):
		if grid.get_opacity(cells[i]) >= OPAQUE_THRESHOLD:
			count += 1
	return count


## All cells within Chebyshev `radius` of origin (inclusive) that have LoS
## from origin. Includes origin itself.
static func visible_cells(grid: Grid, origin: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var y_start: int = maxi(origin.y - radius, 0)
	var y_end: int = mini(origin.y + radius, grid.height - 1)
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
