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
## injector keeps both. This answers "which file did they mean" and "where does this unit stand
## now" — both questions about a board and a roster rather than about whether an injection may
## happen.
##
## taskblock-56 Pass F3: **the file resolution moved here for the reason this class exists.** Adding
## `load_map_file` put `BoutInjector` back over the file-size gate (`gdlintrc`'s `max-file-lines`,
## then at a lower value), which is the same pressure that
## created this file — and "a catalog name or a `res://` path" is no more debug policy than "where
## does this unit stand now" was. What stayed behind is exactly the injector's own protocol: the
## guard, the refusal reason and the `inject` log line.

## The `path` a board that never came from disk is logged under — see `BoutInjector.load_map_file`.
## A sentinel nobody could mistake for a `res://` path, so a reader of the log is never sent looking
## for a file that does not exist.
const AUTHORED_SOURCE := "<authored>"


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


## `{"map": MapFile, "path": String, "error": StringName}` — the authored map a display name or a
## `res://` path stands for.
##
## taskblock-53: **a name or a path.** The debug panel offers a dropdown of authored map names and a
## test or script is better off naming a file; resolving both here keeps every caller on one entry
## point instead of the panel doing a lookup the injector would then have to trust.
##
## The `error` is the injector's own refusal reason, unchanged, so moving this out did not change
## what a refused load says.
static func resolve_map(path_or_name: String) -> Dictionary:
	var found: Dictionary = _resolve(path_or_name, MapCatalog.path_for(StringName(path_or_name)))
	if found["path"] == "":
		return {"error": &"no_map_by_that_name", "path": path_or_name}
	var map := found["resource"] as MapFile
	if map == null:
		return {"error": &"path_is_not_a_map_file", "path": found["path"]}
	return {"map": map, "path": found["path"], "error": &""}


## The section mirror of `resolve_map`, with `SectionCatalog` and `SectionFile`'s own reasons.
static func resolve_section(path_or_name: String) -> Dictionary:
	var found: Dictionary = _resolve(
		path_or_name, SectionCatalog.path_for(StringName(path_or_name))
	)
	if found["path"] == "":
		return {"error": &"no_section_by_that_name", "path": path_or_name}
	var section := found["resource"] as SectionFile
	if section == null:
		return {"error": &"path_is_not_a_section_file", "path": found["path"]}
	return {"section": section, "path": found["path"], "error": &""}


## taskblock-56 Pass F: keyed on `://` rather than on `res://` specifically, so a `user://` path is
## a path too. The editor's own save-and-reopen is the caller that needs it, and no catalog display
## name contains `://` — a name is a name and a URI is a URI.
static func _resolve(path_or_name: String, catalog_path: String) -> Dictionary:
	var path: String = path_or_name if path_or_name.contains("://") else catalog_path
	if path == "":
		return {"path": "", "resource": null}
	return {"path": path, "resource": load(path) if ResourceLoader.exists(path) else null}


## `{"grid": Grid, "stranded": Array[int], "error": String}` — `map` turned into a board and swapped
## in. `error` carries `MapSerializer.to_grid`'s own readable sentence when the file does not
## describe a board at all, and nothing is swapped in that case.
static func swap_to_map(state: CombatState, map: MapFile, prefer_spawn_markers: bool) -> Dictionary:
	var result: Dictionary = MapSerializer.to_grid(map)
	if not result.has("grid"):
		return {"error": result["error"]}
	var grid: Grid = result["grid"]
	return {"grid": grid, "stranded": swap_board(state, grid, prefer_spawn_markers), "error": ""}
