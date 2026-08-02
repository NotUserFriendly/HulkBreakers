extends GutTest

## taskblock-53 Pass B: the committed hand-authored map, `data/maps/proving_ground.tres`.
##
## **The ASCII dump is the point of this file, not decoration.** CLAUDE.md: a spatial system
## without a dump is one nobody can verify, and CC cannot see the map. Every assertion below
## is checkable against the printed board in the run log, so a future change that shifts the
## platform edge by one cell shows up as a picture rather than as a number that moved.

const MAP_PATH := "res://data/maps/proving_ground.tres"


func _map() -> MapFile:
	return load(MAP_PATH) as MapFile


func _grid() -> Grid:
	var result: Dictionary = MapSerializer.to_grid(_map())
	assert_eq(result.get("error", ""), "", "the committed map must load")
	return result.get("grid")


## One character per cell, chosen by what a unit would actually meet there — a blocker first
## (it is what stops you), then the highest walkable surface, then nothing.
func _glyph(grid: Grid, cell: Vector2i) -> String:
	if grid.blockers.has(cell):
		return "#" if (grid.blockers[cell] as Part).id == &"wall" else "c"
	var surfaces: Array[Surface] = grid.surfaces_at(cell)
	if surfaces.is_empty():
		return " "
	if Surface.is_ramp_at(grid, cell):
		return "+"
	var top: float = -1.0
	for surface: Surface in surfaces:
		top = maxf(top, surface.height)
	if is_equal_approx(top, 0.0):
		return "."
	if is_equal_approx(top, 2.0):
		return "="
	return "^"


func _dump(grid: Grid) -> void:
	gut.p("proving ground — %dx%d" % [grid.width, grid.rows])
	gut.p("  # wall   c cover   . ground(0)   = platform(2)   ^ ledge(4)   + ramp")
	for y: int in range(grid.rows):
		var row := ""
		for x: int in range(grid.width):
			row += _glyph(grid, Vector2i(x, y))
		gut.p("  %2d %s" % [y, row])
	var spawn_a := ""
	var spawn_b := ""
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var marker: int = grid.get_spawn_marker(Vector2i(x, y))
			if marker == Enums.SpawnMarker.SPAWN_A:
				spawn_a += "%s " % Vector2i(x, y)
			elif marker == Enums.SpawnMarker.SPAWN_B:
				spawn_b += "%s " % Vector2i(x, y)
	gut.p("  spawn A: %s" % spawn_a)
	gut.p("  spawn B: %s" % spawn_b)


func test_the_committed_map_loads_and_looks_like_its_authored_shape() -> void:
	var grid: Grid = _grid()
	if grid == null:
		return
	_dump(grid)

	assert_eq(grid.width, 21, "the authored width")
	assert_eq(grid.rows, 12, "the authored rows")
	assert_eq(
		MapSerializer.describe_problems(_map()),
		[] as Array[String],
		"the committed map is well-formed"
	)


## **Real vertical structure, which is what Pass B asked the map to have.** Three distinct
## elevations that a unit can be standing on, not one flat board with decoration.
func test_the_map_has_three_distinct_elevations() -> void:
	var grid: Grid = _grid()
	if grid == null:
		return
	var heights: Dictionary = {}
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			for surface: Surface in grid.surfaces_at(Vector2i(x, y)):
				heights[snappedf(surface.height, 0.01)] = true
	var found: Array = heights.keys()
	found.sort()
	gut.p("elevations present: %s" % str(found))
	assert_true(found.has(0.0), "ground")
	assert_true(found.has(2.0), "the platform")
	assert_true(found.has(4.0), "the high ledge")


## **The ledges are a stacked second surface at a cell that already has one** — the format's
## ordered per-cell array carrying the thing it exists for, in committed content rather than
## only in a unit test's fixture.
func test_the_high_ledges_are_stacked_over_the_platform() -> void:
	var grid: Grid = _grid()
	if grid == null:
		return
	var stacked := 0
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			if grid.surfaces_at(Vector2i(x, y)).size() > 1:
				stacked += 1
	gut.p("%d cells carry more than one surface" % stacked)
	assert_gt(stacked, 0, "the map exercises stacked surfaces")

	var ledge := Vector2i(15, 2)
	var surfaces: Array[Surface] = grid.surfaces_at(ledge)
	assert_eq(surfaces.size(), 2, "%s is platform + ledge" % ledge)
	assert_almost_eq(surfaces[0].height, 2.0, 0.001, "the platform is first — what you stand on")
	assert_almost_eq(surfaces[1].height, 4.0, 0.001, "the ledge is above it")


## **Both spawn zones exist and are standable.** A map whose spawns have no floor under them
## loads fine and is useless, which is why `describe_problems` checks it and why this pins it
## for the committed map specifically.
func test_both_spawns_are_placed_on_walkable_ground() -> void:
	var grid: Grid = _grid()
	if grid == null:
		return
	var a := 0
	var b := 0
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			var marker: int = grid.get_spawn_marker(cell)
			if marker == Enums.SpawnMarker.NONE:
				continue
			assert_not_null(
				Surface.first_walkable(grid.surfaces_at(cell)), "%s must be standable" % cell
			)
			if marker == Enums.SpawnMarker.SPAWN_A:
				a += 1
			else:
				b += 1
	assert_gt(a, 0, "squad A has somewhere to start")
	assert_gt(b, 0, "squad B has somewhere to start")


## **The map round-trips like any other**, which is the check that committed content and the
## format cannot drift apart — a format change that broke the committed map would otherwise
## only show up the next time someone opened it.
func test_the_committed_map_round_trips() -> void:
	var grid: Grid = _grid()
	if grid == null:
		return
	var again: Dictionary = MapSerializer.to_grid(MapSerializer.to_map_file(grid, "again"))
	assert_eq(again.get("error", ""), "")
	var reloaded: Grid = again["grid"]
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			assert_eq(
				grid.surfaces_at(cell).size(),
				reloaded.surfaces_at(cell).size(),
				"%s keeps its surface count" % cell
			)
