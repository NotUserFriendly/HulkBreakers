extends GutTest

## taskblock-53 Pass D: the generator owes navigability, and `BR46.02`'s own check is the
## invariant.

## **A deliberately narrow sweep.** `BR46.02` was measured over 40 seeds at 32x24 and this
## block re-measured the same 40 either side of the fix: **16 of 40 before, 0 of 40 after**,
## worst case seed 16 with 216 one-way cells. Forty seeds is too slow for a gate someone waits
## on, so the gate runs twelve — including seed 16, the worst one recorded — and the full sweep
## stays a thing to run deliberately.
const GATE_SEEDS: Array[int] = [0, 1, 2, 3, 5, 8, 13, 16, 21, 27, 33, 39]
const BOUT_WIDTH := 32
const BOUT_ROWS := 24


## Builds a bout-sized board, so this file is skipped by the fast gate.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func test_no_generated_map_contains_ground_a_unit_cannot_leave() -> void:
	var offenders: Array[String] = []
	for map_seed: int in GATE_SEEDS:
		var grid: Grid = MapGen.generate(map_seed, BOUT_WIDTH, BOUT_ROWS)
		var stranded: Array[Vector2i] = MapNavigability.stranding_cells(grid)
		if not stranded.is_empty():
			offenders.append(
				"seed %d: %d one-way cells, first %s" % [map_seed, stranded.size(), stranded[0]]
			)
	gut.p("%d seeds swept at %dx%d" % [GATE_SEEDS.size(), BOUT_WIDTH, BOUT_ROWS])
	assert_eq(offenders, [] as Array[String], "every generated map must be two-way navigable")


## **The check has to be able to fail, or the sweep above proves nothing.** A hand-built pit —
## a floor with a lowered cell in it and no route up — must be reported. Without this, a bug
## that made `stranding_cells` always return empty would turn the sweep green and silent.
func test_the_invariant_reports_a_pit_that_has_no_route_out() -> void:
	var grid := Grid.new(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			grid.add_surface(Vector2i(x, y), Surface.new(DataLibrary.get_part(&"ship_floor"), 3.0))
	# One cell dropped 2.0 below its neighbours: **exactly the window that strands.** A drop
	# is legal to `MAX_HOP_DOWN_LEVELS` (2.0) and a bare climb only to `MAX_CLIMB_LEVELS`
	# (1.0), so 2.0 is free to fall into and impossible to climb out of. Deeper is not worse,
	# it is unreachable — you cannot fall in at all, so it is not one-way ground.
	grid.clear_surfaces(Vector2i(2, 2))
	grid.add_surface(Vector2i(2, 2), Surface.new(DataLibrary.get_part(&"ship_floor"), 1.0))
	grid.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)

	var stranded: Array[Vector2i] = MapNavigability.stranding_cells(grid)
	gut.p("pit reported: %s" % str(stranded))
	assert_true(stranded.has(Vector2i(2, 2)), "the pit is one-way ground and must be named")


## **A pit deeper than a step gets a ladder.** Asserted on the repaired board rather than by
## calling the private stamper, so the test describes the rule and not the implementation.
##
## tb60 Pass A: this asserted a *ramp* until the ramp was retired. The rule it now describes
## is simpler and is the whole of the repair path: a rise inside the step height was never
## stranding in the first place, and everything else is a ladder.
func test_a_pit_deeper_than_a_step_is_repaired_with_a_ladder() -> void:
	var grid: Grid = _pit_grid(3.0)
	MapGen.guarantee_navigability(grid)
	assert_true(
		Surface.has_ladder_at(grid, Vector2i(2, 2)),
		"a 2-high face is ladder work — there is no shallower repair left to reach for"
	)
	assert_eq(MapNavigability.stranding_cells(grid), [] as Array[Vector2i], "and the pit is open")


## **The ladder branch was measured-dead and this pass woke it up — this is the measurement
## the other way round.**
##
## The old rule was "rise <= `RAMP_MAX_RISE` gets a ramp, anything higher gets a ladder", and
## the second half could not fire: a cell is one-way only if you can *fall into* it, which
## caps the drop at `MAX_HOP_DOWN_LEVELS` (2.0); the way out is the same face you came down,
## so the repair's rise never exceeded 2.0 either — exactly the old `RAMP_MAX_RISE`. Every
## stranded cell was therefore ramp work, and the previous version of this test asserted
## precisely that inequality.
##
## **Its own instruction was "if this test fails, the branch has woken up — update it rather
## than deleting it," and that is what happened.** tb60 Pass A deleted the ramp branch, so
## the ladder is not merely reachable, it is the only repair there is. The assertion inverts
## to match: every stranded cell now takes a ladder, and the arithmetic that used to prove
## the branch dead is what now bounds how tall those ladders get.
func test_every_repair_is_a_ladder_now_that_the_ramp_branch_is_gone() -> void:
	var grid: Grid = _pit_grid(3.0)
	var stranded_before: Array[Vector2i] = MapNavigability.stranding_cells(grid)
	assert_false(stranded_before.is_empty(), "sanity: there is something to repair")

	MapGen.guarantee_navigability(grid)

	for cell: Vector2i in stranded_before:
		assert_true(
			Surface.has_ladder_at(grid, cell),
			"stranded cell %s must have been repaired with a ladder" % cell
		)
	(
		gut
		. p(
			(
				"MAX_HOP_DOWN_LEVELS %.1f, MAX_CLIMB_LEVELS %.1f, step height %.2f — %d repaired"
				% [
					Pathfinder.MAX_HOP_DOWN_LEVELS,
					Pathfinder.MAX_CLIMB_LEVELS,
					Unit.BASE_STEP_HEIGHT,
					stranded_before.size(),
				]
			)
		)
	)


## **A rise inside the step height is not stranding at all**, which is why the repair path
## never has a shallow case to handle. The boundary the deleted ramp branch used to sit on,
## asserted directly instead of by the constant that used to name it.
func test_a_drop_within_the_step_height_never_strands() -> void:
	var grid := Grid.new(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			grid.add_surface(Vector2i(x, y), Surface.new(DataLibrary.get_part(&"ship_floor"), 3.0))
	grid.clear_surfaces(Vector2i(2, 2))
	grid.add_surface(
		Vector2i(2, 2),
		Surface.new(DataLibrary.get_part(&"ship_floor"), 3.0 - Unit.BASE_STEP_HEIGHT)
	)
	grid.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)

	assert_eq(
		MapNavigability.stranding_cells(grid),
		[] as Array[Vector2i],
		"you can step back out of a dip that shallow, so it is not one-way ground"
	)


func _pit_grid(depth: float) -> Grid:
	var grid := Grid.new(5, 5)
	for y: int in range(5):
		for x: int in range(5):
			grid.add_surface(
				Vector2i(x, y), Surface.new(DataLibrary.get_part(&"ship_floor"), depth)
			)
	grid.clear_surfaces(Vector2i(2, 2))
	# `depth - 2.0`: the drop is exactly `MAX_HOP_DOWN_LEVELS`, the deepest a unit can
	# fall into and so the deepest pit that can strand anyone.
	grid.add_surface(Vector2i(2, 2), Surface.new(DataLibrary.get_part(&"ship_floor"), depth - 2.0))
	grid.set_spawn_marker(Vector2i(0, 0), Enums.SpawnMarker.SPAWN_A)
	return grid


## **The editor warns, it never blocks.** An authored map that fails the invariant still loads
## — the committed proving ground is exactly such a map on purpose, since its height-4 shelves
## have no route until a ladder is placed.
func test_an_authored_map_that_fails_the_invariant_still_loads() -> void:
	var map: MapFile = load("res://data/maps/proving_ground.tres") as MapFile
	var result: Dictionary = MapSerializer.to_grid(map)
	assert_true(result.has("grid"), "a knowingly-unnavigable authored map still loads")
	var stranded: Array[Vector2i] = MapNavigability.stranding_cells(result["grid"])
	gut.p("proving ground one-way cells: %d" % stranded.size())
	assert_eq(
		MapSerializer.describe_problems(map),
		[] as Array[String],
		"and its authoring checks stay separate from navigability, which is the generator's"
	)
