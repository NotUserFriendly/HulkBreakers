extends GutTest

## taskblock-41 Pass D: "a bout-build log in the order things actually happen
## — recounted in build order rather than summarised at the end. Build order is
## what makes it a diagnostic; the same numbers summarised are not."
##
## So the assertions here are about the SEQUENCE. A totals-only test would pass
## against a summary emitted in one lump at the end, which is precisely the
## thing this pass is not.

## The order `BoardView.build()` actually constructs in. Tiles must precede
## everything that sits on them; blockers must precede the loose items that can
## be lying under them.
##
## taskblock-55 Pass B: the first step was `terrain`, counted in cells. The board
## no longer draws anything per cell — it draws the tiles placed on it — so the
## step is renamed and counted in walkable parts. A per-cell count would have
## reported a number nothing in the scene corresponds to.
##
## tb62 Pass B: `mag_lifts` joins the sequence, after the extraction cells and
## before the blockers. **Position is the claim, not membership** — a lift pad is
## a ground-overlay annotation like an extraction cell, so it belongs with them
## and above anything that can stand on top of it. This list going red when a step
## is added is the test working: a build step nobody declared here is a step that
## slipped into the sequence unnoticed.
const EXPECTED_ORDER: Array[StringName] = [
	&"tiles",
	&"grid_lines",
	&"empty_cells",
	&"extraction_cells",
	&"mag_lifts",
	&"walls",
	&"cover",
	&"field_items",
]


func _board_with_log(grid: Grid, extraction: Dictionary = {}) -> MemorySink:
	var log := CombatLog.new()
	var memory := MemorySink.new()
	log.add_sink(memory)
	var board := BoardView.new()
	add_child_autofree(board)
	board.build_log = log
	board.build(grid, DataLibrary.material_table(), extraction)
	return memory


func _steps(memory: MemorySink) -> Array[LogEvent]:
	return memory.events_of_kind(&"build_step")


func _step_names(memory: MemorySink) -> Array[StringName]:
	var names: Array[StringName] = []
	for event: LogEvent in _steps(memory):
		names.append(event.data["step"])
	return names


func test_the_build_log_records_every_step_in_construction_order() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var memory: MemorySink = _board_with_log(grid)

	assert_eq(_step_names(memory), EXPECTED_ORDER, "the sequence, not the totals")


## The running index is what survives a consumer sorting or filtering the
## stream — order that only exists as array position is order you can lose.
func test_each_step_carries_its_own_position_in_the_sequence() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var memory: MemorySink = _board_with_log(grid)

	var steps: Array[LogEvent] = _steps(memory)
	for i in range(steps.size()):
		assert_eq(steps[i].data["index"], i + 1, "step %d numbered itself" % i)


func test_a_rebuilt_board_restarts_its_own_numbering() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var log := CombatLog.new()
	var memory := MemorySink.new()
	log.add_sink(memory)
	var board := BoardView.new()
	add_child_autofree(board)
	board.build_log = log

	board.build(grid, DataLibrary.material_table())
	board.build(grid, DataLibrary.material_table())

	var steps: Array[LogEvent] = _steps(memory)
	assert_eq(steps.size(), EXPECTED_ORDER.size() * 2)
	assert_eq(steps[0].data["index"], 1)
	assert_eq(
		steps[EXPECTED_ORDER.size()].data["index"],
		1,
		"the second build starts over, not at %d" % (EXPECTED_ORDER.size() + 1)
	)


## Walls and cover are counted off the same `grid.blockers` sweep that builds
## them, so the numbers describe what was drawn rather than a second reading
## of the map.
func test_walls_and_cover_are_counted_separately_as_they_are_built() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	GridFixture.place_wall(grid, Vector2i(1, 1), 0.0)
	GridFixture.place_wall(grid, Vector2i(2, 1), 0.0)
	grid.blockers[Vector2i(4, 4)] = DataLibrary.get_part(&"crate")

	var memory: MemorySink = _board_with_log(grid)

	var by_step: Dictionary = {}
	for event: LogEvent in _steps(memory):
		by_step[event.data["step"]] = event.data["count"]
	assert_eq(by_step[&"walls"], 2)
	assert_eq(by_step[&"cover"], 1, "a crate is cover, not a wall")


func test_extraction_cells_are_counted_where_they_are_actually_drawn() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var extraction: Dictionary = {0: [Vector2i(0, 0), Vector2i(0, 1)], 1: [Vector2i(5, 5)]}

	var memory: MemorySink = _board_with_log(grid, extraction)

	for event: LogEvent in _steps(memory):
		if event.data["step"] == &"extraction_cells":
			assert_eq(event.data["count"], 3, "both squads' cells, counted as drawn")
			return
	fail_test("no extraction_cells step was logged at all")


## Every headless fixture in the suite builds a board with no battle around it.
## The build log is additive and must stay entirely optional.
func test_a_board_with_no_log_attached_builds_exactly_as_before() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	var board := BoardView.new()
	add_child_autofree(board)

	board.build(grid, DataLibrary.material_table())

	assert_null(board.build_log, "no log, no logging, no crash")
	assert_eq(board.grid, grid)
