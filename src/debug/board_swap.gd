class_name BoardSwap
extends RefCounted

## taskblock-54 Pass D: **putting units onto a board that has just been replaced.**
##
## Split out of `BoutInjector` because two debug verbs now replace the whole board — `load_map`
## and `preview_section` — and both face the same problem: a unit standing where the new board
## has a wall, or off the edge of a smaller one. Two copies would be two places for that to be
## got wrong, and the injector was over its own file-length limit besides.
##
## **Logic, not debug policy.** Nothing here decides whether a swap is allowed or logs one; the
## injector keeps both. This only answers "where does this unit stand now", which is a question
## about a board and a roster.


## Replaces the live board with `grid` and relocates every living unit onto it, returning the ids
## of any that could not be placed.
##
## **Shared by `load_map` and `preview_section`** rather than written twice. Both replace the
## whole board and both face the same problem — a unit standing where the new board has a wall,
## or off the edge of a smaller one — so two copies would be two places for that to be got wrong.
## They differ in one thing only, which is the argument: a **map** carries spawn markers and units
## belong on their own squad's, while a **section** is a fragment that need not have any, so a
## preview just puts them on the first standable cell.
##
## **A unit that finds nowhere at all is left where it is and named**, never destroyed. Refusing
## the whole load because one unit could not be placed would be worse than a board you can see the
## problem on.
static func swap_board(state: CombatState, grid: Grid, prefer_spawn_markers: bool) -> Array[int]:
	state.grid = grid
	var stranded: Array[int] = []
	for unit: Unit in state.units:
		if not unit.alive:
			continue
		var destination: Variant = null
		if prefer_spawn_markers:
			destination = _first_free_spawn(grid, unit.squad_id)
		if destination == null:
			destination = _first_free_walkable(grid)
		if destination == null:
			stranded.append(unit.id)
			continue
		unit.cell = destination
		grid.set_occupant_id(destination, unit.id)
		unit.height = UnitGeometry.true_height_for_cell(destination, grid)
		unit.level = unit.height / UnitGeometry.LEVEL_HEIGHT
	return stranded


## The first cell carrying this squad's own spawn marker and nobody standing on it.
static func _first_free_spawn(grid: Grid, squad_id: int) -> Variant:
	var wanted: int = Enums.SpawnMarker.SPAWN_A if squad_id == 0 else Enums.SpawnMarker.SPAWN_B
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_spawn_marker(cell) != wanted:
				continue
			if grid.get_occupant_id(cell) == -1 and _is_standable(grid, cell):
				return cell
	return null


static func _first_free_walkable(grid: Grid) -> Variant:
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_occupant_id(cell) == -1 and _is_standable(grid, cell):
				return cell
	return null


static func _is_standable(grid: Grid, cell: Vector2i) -> bool:
	return not grid.blockers.has(cell) and Surface.first_walkable(grid.surfaces_at(cell)) != null
