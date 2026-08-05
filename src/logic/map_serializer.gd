class_name MapSerializer
extends RefCounted

## taskblock-53 Pass B: **`Grid` <-> `MapFile`, both directions.**
##
## Pure logic, zero SceneTree (CLAUDE.md): saving and loading a map is testable headlessly,
## and the round trip is the test — save a generated map, load it, and the loaded `Grid`
## must be equivalent to the original.
##
## ## Loading never enforces the placement grammar, deliberately
##
## `GridPlacement.can_place` gates *authoring*: `GROUND` needs an empty cell, a side
## attachment needs a free matching socket on an orthogonal neighbour. Replaying those rules
## at load time would be wrong twice over. It would reject a legitimate saved stack whose
## cell is no longer empty by the time the second surface loads — the grammar is about the
## act of placing, not about the result — and taskblock-53 is explicit that **an authored map
## may be broken on purpose**: the editor's later job is to *warn*, never to block. So load
## reproduces what was saved, and `describe_problems()` below is the thing that warns.
##
## What load *does* reject is a file it cannot honestly turn into a board at all: an unknown
## part id, a cell off the grid, a non-positive dimension, two blockers on one cell. Those
## are not authoring opinions, they are files that do not describe a map.


## `{"map": MapFile}` — a `Grid` captured as a saved map. Never fails: any `Grid` the engine
## produced is by definition describable.
##
## **Parts are captured by id.** A blocker whose part carries battle damage saves as its
## authored id and reloads intact, which is what makes this a map format rather than a
## savegame (`MapFile`'s own doc comment).
static func to_map_file(grid: Grid, map_name: String = "") -> MapFile:
	var map := MapFile.new()
	map.map_name = map_name
	map.width = grid.width
	map.rows = grid.rows

	# Cells are visited in a fixed row-major order rather than in `Dictionary` order, so the
	# same board always saves to the same file. A format whose byte output depended on
	# insertion order could not be diffed between two runs, which is half of what a
	# committed map is for.
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			for surface: Surface in grid.surfaces_at(cell):
				map.placements.append(
					MapPlacement.new(
						cell,
						MapPlacement.KIND_SURFACE,
						surface.part.id,
						surface.height,
						surface.facing
					)
				)
			if grid.blockers.has(cell):
				map.placements.append(
					MapPlacement.new(
						cell, MapPlacement.KIND_BLOCKER, (grid.blockers[cell] as Part).id
					)
				)
			for item: Variant in grid.field_items.get(cell, []):
				map.placements.append(MapPlacement.new(cell, MapPlacement.KIND_FIELD_ITEM, item.id))

			var marker: int = grid.get_spawn_marker(cell)
			if marker != Enums.SpawnMarker.NONE:
				map.spawn_cells.append(cell)
				map.spawn_markers.append(marker)
	return map


## `{"grid": Grid, "error": ""}` on success, `{"error": "<reason>"}` with no `grid` key on a
## file that does not describe a board. **Never crashes and never invents** — the same
## posture `BoutSetup.build_bout` already takes, and the reason a malformed map is a readable
## sentence rather than a stack trace in a headless run.
static func to_grid(map: MapFile) -> Dictionary:
	if map == null:
		return {"error": "no map resource"}
	if map.width <= 0 or map.rows <= 0:
		return {
			"error":
			"map '%s' has non-positive dimensions %dx%d" % [map.map_name, map.width, map.rows]
		}
	if map.spawn_cells.size() != map.spawn_markers.size():
		return {
			"error":
			(
				"spawn arrays disagree: %d cells, %d markers"
				% [map.spawn_cells.size(), map.spawn_markers.size()]
			)
		}

	var grid := Grid.new(map.width, map.rows)
	for index: int in range(map.placements.size()):
		var placement: MapPlacement = map.placements[index]
		if placement == null:
			return {"error": "placement %d is empty" % index}
		if not grid.in_bounds(placement.cell):
			return {
				"error":
				(
					"placement %d ('%s') sits at %s, outside a %dx%d map"
					% [index, placement.part_id, placement.cell, map.width, map.rows]
				)
			}
		var part: Part = DataLibrary.get_part(placement.part_id)
		if part == null:
			return {
				"error":
				(
					"placement %d names part '%s', which DataLibrary does not have"
					% [index, placement.part_id]
				)
			}
		match placement.kind:
			MapPlacement.KIND_SURFACE:
				grid.add_surface(
					placement.cell, Surface.new(part, placement.height, placement.facing)
				)
			MapPlacement.KIND_BLOCKER:
				if grid.blockers.has(placement.cell):
					return {
						"error":
						(
							"placement %d puts a second blocker at %s; a cell holds one"
							% [index, placement.cell]
						)
					}
				grid.blockers[placement.cell] = part
			MapPlacement.KIND_FIELD_ITEM:
				if not grid.field_items.has(placement.cell):
					grid.field_items[placement.cell] = []
				(grid.field_items[placement.cell] as Array).append(part)
			_:
				return {"error": "placement %d has unknown kind '%s'" % [index, placement.kind]}

	for i: int in range(map.spawn_cells.size()):
		if not grid.in_bounds(map.spawn_cells[i]):
			return {"error": "spawn %d sits at %s, outside the map" % [i, map.spawn_cells[i]]}
		grid.set_spawn_marker(map.spawn_cells[i], map.spawn_markers[i])

	return {"grid": grid, "error": ""}


## **Authoring warnings, never load failures.** taskblock-53: an authored map may be broken
## on purpose, so nothing here rejects anything — this is what an editor would surface and
## what a test can assert against. Returns one sentence per problem, empty when clean.
##
## Deliberately does NOT include navigability: that is Pass D's asymmetric flood, it needs a
## spawn to flood from, and it is a property a *generator* owes rather than one an author
## does.
static func describe_problems(map: MapFile) -> Array[String]:
	var problems: Array[String] = []
	if map == null:
		problems.append("no map resource")
		return problems

	var walkable_cells: Dictionary = {}
	for placement: MapPlacement in map.placements:
		if placement == null or placement.kind != MapPlacement.KIND_SURFACE:
			continue
		var part: Part = DataLibrary.get_part(placement.part_id)
		if part != null and Surface.WALKABLE_TAG in part.tags:
			walkable_cells[placement.cell] = true

	if walkable_cells.is_empty():
		problems.append("no walkable surface anywhere — nothing can stand on this map")
	if map.spawn_cells.is_empty():
		problems.append("no spawn markers — a bout has nowhere to place a squad")
	for i: int in range(map.spawn_cells.size()):
		if not walkable_cells.has(map.spawn_cells[i]):
			problems.append("spawn at %s has no walkable surface under it" % map.spawn_cells[i])
	return problems
