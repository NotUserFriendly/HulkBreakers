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


## **A rise of 2 or less gets a ramp.** Asserted on the repaired board rather than by calling
## the private stamper, so the test describes the rule and not the implementation.
func test_a_shallow_pit_is_repaired_with_a_ramp() -> void:
	var grid: Grid = _pit_grid(3.0)
	MapGen.guarantee_navigability(grid)
	assert_true(
		Surface.is_ramp_at(grid, Vector2i(2, 2)), "a 2-high face is ramp work, not ladder work"
	)
	assert_eq(MapNavigability.stranding_cells(grid), [] as Array[Vector2i], "and the pit is open")


## **The ladder branch of the generator rule is measured-dead, and this is the measurement.**
##
## The rule is "rise <= 2 gets a ramp, anything higher gets a ladder". Nothing generated can
## reach the second half, and the reason is arithmetic rather than luck: a cell is one-way only
## if you can *fall into* it, which caps the drop at `MAX_HOP_DOWN_LEVELS` (2.0); the way out
## is the same face you came down, so the repair's rise never exceeds 2.0 either — exactly
## `RAMP_MAX_RISE`. Every stranded cell is therefore ramp work.
##
## **The branch is kept rather than deleted**, the same way taskblock-52 kept its measured-dead
## tiebreak stage: it costs nothing, and it is one constant away from live. **If this test
## fails, the branch has woken up — update it rather than deleting it**, and check that the
## generator really is placing ladders where it should.
func test_the_generators_ladder_branch_cannot_currently_fire() -> void:
	(
		gut
		. p(
			(
				"MAX_HOP_DOWN_LEVELS %.1f, MAX_CLIMB_LEVELS %.1f, RAMP_MAX_RISE %.1f"
				% [
					Pathfinder.MAX_HOP_DOWN_LEVELS,
					Pathfinder.MAX_CLIMB_LEVELS,
					MapGen.RAMP_MAX_RISE,
				]
			)
		)
	)
	assert_lte(
		Pathfinder.MAX_HOP_DOWN_LEVELS * UnitGeometry.LEVEL_HEIGHT,
		MapGen.RAMP_MAX_RISE,
		(
			"a drop no deeper than a ramp can repair means no stranded cell ever needs a ladder"
			+ " — if this stops holding, the ladder branch is live and wants a real test"
		)
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
