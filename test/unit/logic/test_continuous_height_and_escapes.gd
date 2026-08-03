extends GutTest

## taskblock-54 Pass B2 and B3.
##
## **B2 — height stays continuous.** A walkable part sits at whatever height it sits at, and
## nothing may quantize that away: no level index, no 0.5 grid, no rounding in walkability.
## taskblock-37 made height continuous on purpose and deleting the terrace is the change that
## could quietly undo it, because a terraced renderer is the thing that made whole steps *look*
## like the unit of elevation.
##
## **B3 — a round that leaves the board is counted.** Gaps are legitimate now, so "missed
## everything and left the map" stops being a defect and becomes a metric: how leaky is this
## board.


func _floor_at(grid: Grid, cell: Vector2i, height: float) -> void:
	grid.add_surface(cell, Surface.new(DataLibrary.get_part(&"ship_floor"), height))


# --- B2: nothing quantizes a height ------------------------------------------------------


## **A 0.3-high part is standable**, which is the taskblock's own example — the height a collapse
## would leave behind, and exactly the value a 0.5 grid or a level index would erase.
func test_a_0_3_high_part_is_standable_and_pathable() -> void:
	var grid := Grid.new(4, 4)
	for y: int in range(4):
		for x: int in range(4):
			_floor_at(grid, Vector2i(x, y), 0.0)
	grid.clear_surfaces(Vector2i(1, 1))
	_floor_at(grid, Vector2i(1, 1), 0.3)

	assert_almost_eq(
		UnitGeometry.true_height_for_cell(Vector2i(1, 1), grid),
		0.3,
		0.0001,
		"the height reads back exactly as placed, unrounded"
	)
	assert_true(Pathfinder.new(grid).is_walkable(Vector2i(1, 1)), "a 0.3-high part is standable")

	# **Pathable under the rules that already exist, not under a new one.** A 0.3 rise is an
	# ordinary climb costing `ceil(CLIMB_COST * 0.3)` = 2 — *"partial MP costs round up"*,
	# settled in `docs/PLAN.md` and pinned by `test_pathfinder.gd`. A first attempt at this pass
	# added a free-step threshold that made such a rise cost 1, which **contradicted that settled
	# decision**: a sub-level rise is meant to be cheap, not free.
	var climber := Pathfinder.new(grid, true)
	assert_almost_eq(
		climber.move_cost(Vector2i(1, 0), Vector2i(1, 1)),
		2.0,
		0.0001,
		"a 0.3 rise is pathable, at the rounded-up partial climb cost"
	)
	assert_gt(climber.move_cost(Vector2i(1, 1), Vector2i(1, 0)), 0.0, "and steppable off again")

	# Recorded rather than asserted as desirable: **a unit with no climbing capability cannot
	# cross a 0.3 lip at all**, and no shipped part carries the tag. That is `BR46.02`'s residue,
	# which taskblock-53 answered at the generator level — a map owes a route — rather than by
	# loosening the movement rule. Pinned so the state of affairs is visible rather than assumed.
	assert_lt(
		Pathfinder.new(grid).move_cost(Vector2i(1, 0), Vector2i(1, 1)),
		0.0,
		"a non-climber still cannot cross it — capability-gated, unchanged by this block"
	)


## **A spread of awkward heights all survive a round trip through placement.** Pinned as a set
## rather than one value, because a quantizer would round some of these to the same number and a
## single-value test could miss by landing on a grid point.
func test_awkward_heights_are_never_quantized() -> void:
	var grid := Grid.new(8, 2)
	var heights: Array[float] = [0.1, 0.3, 0.7, 1.25, 1.9, 2.4, 3.33, 4.75]
	for i: int in range(heights.size()):
		_floor_at(grid, Vector2i(i, 0), heights[i])
	var read_back: Array[float] = []
	for i: int in range(heights.size()):
		read_back.append(UnitGeometry.true_height_for_cell(Vector2i(i, 0), grid))
	gut.p("placed %s" % str(heights))
	gut.p("read   %s" % str(read_back))
	for i: int in range(heights.size()):
		assert_almost_eq(read_back[i], heights[i], 0.0001, "height %d survives" % i)
	var distinct: Dictionary = {}
	for height: float in read_back:
		distinct[height] = true
	assert_eq(distinct.size(), heights.size(), "and no two collapse onto one another")


# --- B3: escapes are counted --------------------------------------------------------------


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


## Fires one round into open space and returns how many escapes it produced.
func _escapes_for(grid: Grid, aim: Vector2) -> int:
	var shooter: Unit = _shooter(Vector2i(1, 1))
	var state := CombatState.new(grid, [shooter])
	state.assign_all_to_human()
	CombatState.shots_escaped = 0
	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(1, 1), Vector2(1, 0), aim, 5.0, 0.0, 0.0, null
	)
	return CombatState.shots_escaped


## **Non-zero in an open board.** Nothing is out there, so the round leaves.
func test_a_shot_into_open_space_is_counted_as_escaped() -> void:
	var grid := Grid.new(10, 10)
	assert_eq(_escapes_for(grid, Vector2(1000.0, 0.0)), 1, "a round with nothing to hit escapes")


## **Zero when the round strikes something.** The counter must not be "every shot that missed its
## target" — a round that hits a wall instead is not leaky geometry, it is an ordinary miss.
func test_a_shot_that_strikes_a_wall_is_not_counted_as_escaped() -> void:
	var grid := Grid.new(10, 10)
	for y: int in range(10):
		for x: int in range(10):
			_floor_at(grid, Vector2i(x, y), 0.0)
	grid.blockers[Vector2i(4, 1)] = DataLibrary.get_part(&"wall")

	var before: int = CombatState.shots_escaped
	var shooter: Unit = _shooter(Vector2i(1, 1))
	var state := CombatState.new(grid, [shooter])
	state.assign_all_to_human()
	var landed: bool = ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(1, 1), Vector2(1, 0), Vector2(0.0, 0.5), 5.0, 0.0, 0.0, null
	)
	assert_true(landed, "sanity: the round struck the wall")
	assert_eq(CombatState.shots_escaped, before, "striking something is not an escape")


## The `miss` event names the outcome rather than leaving it to be inferred from the absence of
## an impact, so a log reader can grep for it.
func test_the_miss_event_says_it_escaped() -> void:
	var grid := Grid.new(10, 10)
	var shooter: Unit = _shooter(Vector2i(1, 1))
	var state := CombatState.new(grid, [shooter])
	state.assign_all_to_human()
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ShotResolution.resolve_and_log_point(
		state, shooter, Vector2(1, 1), Vector2(1, 0), Vector2(1000.0, 0.0), 5.0, 0.0, 0.0, null
	)
	var misses: Array[LogEvent] = sink.events_of_kind(&"miss")
	assert_eq(misses.size(), 1, "the escape is logged")
	if misses.is_empty():
		return
	assert_true(misses[0].data.get("escaped", false), "and the event says so in as many words")


## `reset_diagnostics` covers it, so a suite run reports per-run totals rather than a number that
## only ever grows across every bout in the process.
func test_the_counter_is_reset_with_the_other_diagnostics() -> void:
	CombatState.shots_escaped = 7
	CombatState.reset_diagnostics()
	assert_eq(CombatState.shots_escaped, 0, "reset with bouts, turns and dups")
