class_name LoS
extends RefCounted

## Line of sight over a Grid's opacity field. Cover (Grid.cover_value) never
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


## All cells within Chebyshev `range` of origin (inclusive) that have LoS from
## origin. Includes origin itself.
static func visible_cells(grid: Grid, origin: Vector2i, range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var y_start: int = maxi(origin.y - range, 0)
	var y_end: int = mini(origin.y + range, grid.height - 1)
	var x_start: int = maxi(origin.x - range, 0)
	var x_end: int = mini(origin.x + range, grid.width - 1)

	for y in range(y_start, y_end + 1):
		for x in range(x_start, x_end + 1):
			var cell := Vector2i(x, y)
			if Grid.distance_chebyshev(origin, cell) > range:
				continue
			if has_los(grid, origin, cell):
				result.append(cell)

	return result
