extends GutTest

## taskblock-46 Pass A: **nothing sinks into a raised room's floor.**
##
## BR40.03 (scattered cover) and BR40.04 (spawn and extraction cells) are one
## defect. `_repair_stranded_elevation` floods with a real `Pathfinder` and
## flattens every unreached `OPEN` cell to level 0 — and `Pathfinder._base_cost`
## returns `-1.0` for any cell carrying a live blocker, so **a cell that a
## `_scatter_cover` crate just landed on is unreachable by construction** and gets
## flattened regardless of whether anything about it is stranded. The result is a
## one-cell pit punched through an otherwise flat raised floor, with the cover item
## at the bottom of it.
##
## For spawn cells the same flatten fires and then `_mark_zone` erases the blocker,
## leaving a clean, correctly-marked cell a full `LEVEL_HEIGHT` below its own room.
## **That one is not cosmetic**: climbing is gated on `Shell.can_climb()` and no
## part in the repo carries `CLIMBER`, so a unit spawned in the pit has exactly one
## reachable cell and spends the battle in it.
##
## ## Why these assertions are phrased against the grid, not against rooms
##
## `MapGen.generate` returns a `Grid` and keeps its room rectangles private. Rather
## than widen that seam for a test, the assertions use the same **visible symptom**
## BR40.03 measured the defect by: a floored cell sitting below three or more of its
## orthogonal neighbours is a pit, whatever produced it. That is stronger than a
## room-relative check as well as cheaper — it catches a sunk cell the room
## bookkeeping might have disagreed about.

## Enough seeds to hit raised rooms reliably — BR40.03's own 40-seed sweep found
## 30/40 maps authoring at least one, and the defect in 8 of 80 spawn zones.
const SEEDS := 40
## `BoutSetup`'s own map size, so this measures the maps the game actually builds.
const WIDTH := 32
const ROWS := 24


## taskblock-48 Pass B2: **this file's failures have a visual form, so it declares
## one.** A rendered map answers in a second what a boolean cannot — which is the same
## argument `docs/00` makes for ASCII dumps, pointed at a screen instead.
##
## The sweep's assertions are about seeds, so the handle rebuilds the seed's map as a
## board with no units on it. There is nothing to fight on it; the map *is* the thing
## that failed.
##
## Returns `null` for tests with nothing spatial to show, which is how a script says
## "not this one" without maintaining a list.
static func replay_handle_for(test_name: String) -> ReplayHandle:
	if not test_name.begins_with("test_"):
		return null
	if test_name == "test_the_generator_still_authors_raised_rooms":
		# An anti-vacuity count, not a place. Nothing to look at.
		return null
	return ReplayHandle.of(
		"map:%s" % test_name,
		"map seed 0",
		func() -> Dictionary:
			var grid: Grid = MapCorpus.read(0, WIDTH, ROWS)
			var state := CombatState.new(grid, [] as Array[Unit])
			return {"state": state, "mission": MissionState.new(RunState.new(), state)}
	)


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _height(grid: Grid, cell: Vector2i) -> float:
	return UnitGeometry.true_height_for_cell(cell, grid)


func _is_floored(grid: Grid, cell: Vector2i) -> bool:
	return Surface.first_walkable(grid.surfaces_at(cell)) != null


## A cell that sits below three or more of its orthogonal neighbours — BR40.03's
## own metric for the symptom, and what a one-cell hole punched through a raised
## floor looks like from the grid alone.
func _is_pit(grid: Grid, cell: Vector2i) -> bool:
	if not _is_floored(grid, cell):
		return false
	var own: float = _height(grid, cell)
	var higher := 0
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbour: Vector2i = cell + step
		if neighbour.x < 0 or neighbour.y < 0:
			continue
		if neighbour.x >= grid.width or neighbour.y >= grid.rows:
			continue
		if not _is_floored(grid, neighbour):
			continue
		if _height(grid, neighbour) > own + 0.01:
			higher += 1
	return higher >= 3


func _cells(grid: Grid) -> Array[Vector2i]:
	var all: Array[Vector2i] = []
	for y in range(grid.rows):
		for x in range(grid.width):
			all.append(Vector2i(x, y))
	return all


func _spawn_zones(grid: Grid) -> Dictionary:
	var zones: Dictionary = {}
	for cell: Vector2i in _cells(grid):
		var marker: int = grid.get_spawn_marker(cell)
		if marker == Enums.SpawnMarker.NONE:
			continue
		if not zones.has(marker):
			zones[marker] = [] as Array[Vector2i]
		(zones[marker] as Array[Vector2i]).append(cell)
	return zones


# --- the tests below are not vacuous ----------------------------------------


## **Every other assertion in this file passes trivially on a flat map.** "No cell
## sits in a pit" is free if nothing is ever raised, so a change that quietly
## stopped generating elevation would turn this whole file green while deleting the
## feature it guards. This is the assertion that stops that reading.
##
## The numbers are the ones BR40.03 measured on the *broken* generator, which is
## the point: the fix removed pits, not elevation, so the raised-room count is
## unchanged at 30/40 while the sunk-cell count went to zero.
func test_the_generator_still_authors_raised_rooms() -> void:
	var maps_with_raised := 0
	var raised_cells := 0
	var floored_cells := 0
	for map_seed in range(SEEDS):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, ROWS)
		var any := false
		for cell: Vector2i in _cells(grid):
			if not _is_floored(grid, cell):
				continue
			floored_cells += 1
			if _height(grid, cell) > 0.01:
				raised_cells += 1
				any = true
		if any:
			maps_with_raised += 1

	gut.p(
		(
			"raised: %d/%d maps, %d of %d floored cells"
			% [maps_with_raised, SEEDS, raised_cells, floored_cells]
		)
	)
	assert_gt(
		maps_with_raised,
		SEEDS / 2,
		"most maps should author a raised room — BR40.03 measured 30/40 before the fix"
	)
	assert_gt(
		float(raised_cells) / float(floored_cells),
		0.05,
		"raised ground must be a real share of the map, not a token cell or two"
	)


# --- BR40.03: cover does not punch a hole ------------------------------------


## **The headline.** Every cell carrying a scattered cover blocker must sit level
## with the floor around it. BR40.03 measured 483 of 2882 cover cells in a pit
## across this sweep, and zero cells with neither a blocker nor a spawn marker —
## so a non-zero count here is this defect and nothing else.
func test_no_cover_object_sits_in_a_pit_of_its_own() -> void:
	var sunk: Array[String] = []
	var cover_cells := 0
	for map_seed in range(SEEDS):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, ROWS)
		for cell: Vector2i in grid.blockers.keys():
			cover_cells += 1
			if _is_pit(grid, cell):
				sunk.append("seed %d %s at %.2f" % [map_seed, cell, _height(grid, cell)])

	gut.p("cover cells swept: %d over %d seeds" % [cover_cells, SEEDS])
	assert_gt(cover_cells, 0, "sanity: the sweep actually generated cover")
	assert_eq(
		sunk.size(),
		0,
		"cover sank into a pit in %d place(s): %s" % [sunk.size(), ", ".join(sunk.slice(0, 8))]
	)


## The general form, and the one that would catch a *different* thing sinking. Any
## floored cell in a pit is a defect regardless of what is standing on it.
func test_no_floored_cell_anywhere_sits_in_a_pit() -> void:
	var sunk: Array[String] = []
	for map_seed in range(SEEDS):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, ROWS)
		for cell: Vector2i in _cells(grid):
			if _is_pit(grid, cell):
				sunk.append("seed %d %s" % [map_seed, cell])

	assert_eq(sunk.size(), 0, "%d pit(s): %s" % [sunk.size(), ", ".join(sunk.slice(0, 8))])


# --- BR40.04: a spawn zone is flat, and a unit on it can move ----------------


## Every cell of a spawn zone at the same height. BR40.03's sweep found 8 of 80
## zones with one or two cells a full `LEVEL_HEIGHT` below the rest.
func test_every_spawn_zone_has_a_uniform_floor_height() -> void:
	var broken: Array[String] = []
	var zones_seen := 0
	for map_seed in range(SEEDS):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, ROWS)
		for marker: int in _spawn_zones(grid):
			var cells: Array[Vector2i] = _spawn_zones(grid)[marker]
			zones_seen += 1
			var heights: Array[float] = []
			for cell: Vector2i in cells:
				var height: float = _height(grid, cell)
				if not heights.any(func(h: float) -> bool: return absf(h - height) < 0.01):
					heights.append(height)
			if heights.size() > 1:
				broken.append("seed %d marker %d heights %s" % [map_seed, marker, heights])

	gut.p("spawn zones swept: %d over %d seeds" % [zones_seen, SEEDS])
	assert_gt(zones_seen, 0, "sanity: the sweep actually placed spawn zones")
	assert_eq(
		broken.size(),
		0,
		"%d zone(s) non-uniform: %s" % [broken.size(), ", ".join(broken.slice(0, 6))]
	)


## **The gameplay consequence, asserted as gameplay.** A unit standing on any spawn
## cell must be able to go somewhere. Uses a real non-climbing `Pathfinder`, which
## is every unit that exists — no part in the repo carries `CLIMBER`.
func test_a_unit_on_any_spawn_cell_can_reach_more_than_its_own_cell() -> void:
	var trapped: Array[String] = []
	for map_seed in range(SEEDS):
		var grid: Grid = MapCorpus.read(map_seed, WIDTH, ROWS)
		var pathfinder := Pathfinder.new(grid, false)
		for marker: int in _spawn_zones(grid):
			for cell: Vector2i in _spawn_zones(grid)[marker] as Array[Vector2i]:
				var reachable: Array[Vector2i] = pathfinder.reachable(cell, INF)
				if reachable.size() <= 1:
					trapped.append("seed %d %s" % [map_seed, cell])

	assert_eq(
		trapped.size(),
		0,
		"%d spawn cell(s) sealed: %s" % [trapped.size(), ", ".join(trapped.slice(0, 8))]
	)
