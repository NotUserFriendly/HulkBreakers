extends GutTest

## tb62 Pass C1: **going up and going down are ordinary movement, and this file is where
## every rule about them now lives.**
##
## It carries the whole of three retired files — `test_climb_action.gd`,
## `test_hop_down_action.gd` and `test_climb_interrupt.gd` — rule for rule, re-asserted
## through `MoveAction`. **Nothing was cut** (`docs/TEST-AUDIT.md`'s cut rule: a test may only
## be removed if breaking the rule it guards reddens a different test, demonstrated rather
## than asserted). The rules did not change; the class that carries them did.
##
## ## Why `ClimbAction` and `HopDownAction` were retired
##
## Measured before the retirement, on the same board with the same unit:
##
## - `Pathfinder.move_cost` prices a climb, a ladder edge and a drop. `astar` routes through
##   all three. `MoveAction.is_legal` was **true for the identical step** at the **identical
##   cost** the discrete action charged.
## - A real planned AI turn already went up a ladder — the planner queued a `MoveAction` that
##   carried a unit from height 0 to height 2.0 on a board whose only route up was a ladder.
## - `MoveAction.apply_stepwise` already fired the overwatch hook on **every** cell including
##   the one it dropped onto, so the exposure `HopDownAction` was faulted for missing was
##   already covered wherever a drop actually happens.
## - Neither class was reachable from the player OR the AI — only from `BoutInjector`.
##
## So they were a second code path deciding what `MoveAction` already decided, which is the
## thing CLAUDE.md names outright: *"if two code paths decide the same thing, that's the bug
## to fix."* The two had also already drifted — `move_cost` **ceils** a climb price and
## `ClimbAction._cost` did not, so the planner quoted 3 MP where the action charged 2.8.
##
## **Taller climbs can still cost differently.** Every cost constant lives on `Pathfinder`,
## `move_cost` sees an edge's full rise, and shaping it is a change to that one expression —
## the retirement removed a duplicate of the formula, never the formula.

const LADDER := &"ladder"


## A climbing-capable shell by default. Authors no `step_height`, so it takes
## `Unit.BASE_STEP_HEIGHT` — the unmodified-body assumption (tb62 Pass A).
func _make_unit(cell: Vector2i, climber: bool = true) -> Unit:
	var root := Part.new()
	root.id = &"torso"
	root.hp = 10
	root.max_hp = 10
	root.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.6))]
	if climber:
		root.tags = [&"CLIMBER"]
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


func _step(unit: Unit, to: Vector2i) -> MoveAction:
	return MoveAction.new(unit, [unit.cell, to] as Array[Vector2i])


# --- going up ------------------------------------------------------------------------


## From `test_climb_action.gd`: *"a climb-up action moves a unit one level and costs 4 MP"*
## (taskblock-37 Pass D's own stated test). Same board, same numbers, one fewer class.
func test_climbing_a_full_level_moves_the_unit_and_costs_4_mp() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 0.0

	var action: MoveAction = _step(unit, Vector2i(1, 0))
	assert_true(action.is_legal(state), "a climber may step up a full level")
	assert_true(state.try_apply(action))

	assert_eq(unit.cell, Vector2i(1, 0))
	assert_almost_eq(unit.height, UnitGeometry.LEVEL_HEIGHT, 0.0001)
	# 4 MP at mp_per_ap() = 2.0 (agility 0) -> two AP burns, mp lands at 0.
	assert_eq(unit.ap, unit.max_ap - 2, "two AP converted to pay 4 MP")
	assert_almost_eq(unit.mp, 0.0, 0.0001)


## From `test_climb_action.gd`, and the reason that test was worth keeping: a climb launched
## from a ramp cell the mover already rests on uses `RampGeometry.STANDING_OFFSET`, so the
## real rise is 0.75 and the real price is 3 MP — not the 0.5/2 MP a level-index reading
## gives. The number is the point; a fixture that got it wrong is what taskblock-39 caught.
func test_a_climb_from_a_ramp_costs_3_mp_at_the_real_standing_height() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_ramp(grid, Vector2i(0, 0), 0)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 0.0

	var rise: float = (
		UnitGeometry.true_height_for_cell(Vector2i(1, 0), grid)
		- UnitGeometry.true_height_for_cell(Vector2i(0, 0), grid)
	)
	gut.p("rise from the ramp's rest height: %.2f" % rise)
	assert_almost_eq(rise, 0.75, 0.0001, "the mover rests at 0.25 on the ramp, not 0.5")
	assert_true(state.try_apply(_step(unit, Vector2i(1, 0))))
	assert_eq(unit.ap, unit.max_ap - 2, "3 MP costs two AP at 2.0 MP each")
	assert_almost_eq(unit.mp, 1.0, 0.0001, "with 1 MP change")


## From `test_climb_action.gd`: beyond `MAX_CLIMB_LEVELS` a bare face is not an edge at all.
func test_a_climb_beyond_one_level_is_not_an_edge() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 2)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])

	assert_false(_step(unit, Vector2i(1, 0)).is_legal(state), "two levels is past the cap")


## From `test_climb_action.gd`: the capability gate. A shell with no `CLIMBER` tag has no
## upward edge on a bare face — which is exactly why ladders, steps and lifts exist.
func test_a_non_climber_has_no_upward_edge_on_a_bare_face() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])

	assert_false(_step(unit, Vector2i(1, 0)).is_legal(state), "no capability, no bare climb")


## From `test_climb_action.gd`, restated for tb60's continuous rule: a rise **within the
## mover's own step height** is a walk, priced at the plain terrain cost, never a climb.
func test_a_rise_within_the_step_height_is_a_plain_walk() -> void:
	var grid := GridFixture.flat(2, 1)
	var unit := _make_unit(Vector2i(0, 0))
	GridFixture.place_floor(grid, Vector2i(1, 0), unit.step_height() / UnitGeometry.LEVEL_HEIGHT)
	var state := CombatState.new(grid, [unit])

	assert_almost_eq(
		Pathfinder.for_unit(grid, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.DEFAULT_COST,
		0.0001,
		"a rise at the step height is ordinary movement, not a 4 MP climb"
	)
	assert_true(_step(unit, Vector2i(1, 0)).is_legal(state))


## From `test_climb_action.gd`: flat ground is flat. Kept because "nothing to climb" was a
## real refusal on the retired class, and the replacement must not quietly price it as one.
func test_flat_ground_costs_the_plain_terrain_cost() -> void:
	var grid := GridFixture.flat(2, 1)
	var unit := _make_unit(Vector2i(0, 0))

	assert_almost_eq(
		Pathfinder.for_unit(grid, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.DEFAULT_COST,
		0.0001
	)


# --- going down ----------------------------------------------------------------------


## From `test_hop_down_action.gd`: a two-level drop moves the unit and costs a flat 1 MP.
func test_a_two_level_drop_moves_the_unit_and_costs_1_mp() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 2)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	unit.mp = 4.0

	assert_true(state.try_apply(_step(unit, Vector2i(1, 0))))
	assert_eq(unit.cell, Vector2i(1, 0))
	assert_almost_eq(unit.height, 0.0, 0.0001)
	assert_almost_eq(unit.mp, 3.0, 0.0001, "flat HOP_DOWN_COST regardless of depth")
	assert_eq(unit.ap, unit.max_ap, "and no AP conversion needed")


## From `test_hop_down_action.gd`: one level is legal, three is not — the drop cap is real.
func test_one_level_drops_and_three_does_not() -> void:
	var one := GridFixture.flat(2, 1)
	GridFixture.place_floor(one, Vector2i(0, 0), 1)
	var shallow := _make_unit(Vector2i(0, 0))
	var shallow_state := CombatState.new(one, [shallow])

	var deep_grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(deep_grid, Vector2i(0, 0), 3)
	var deep := _make_unit(Vector2i(0, 0))
	var deep_state := CombatState.new(deep_grid, [deep])

	assert_true(_step(shallow, Vector2i(1, 0)).is_legal(shallow_state), "one level drops")
	assert_false(
		_step(deep, Vector2i(1, 0)).is_legal(deep_state),
		"three levels is past MAX_HOP_DOWN_LEVELS and is not an edge"
	)


## From `test_hop_down_action.gd`: a drop **within the step height** is ordinary movement,
## and one just past it is a real drop. The free rise is symmetric on purpose — an asymmetric
## one manufactures the one-way ground `BR46.02` was about, a tenth of a level at a time.
func test_the_free_rise_is_symmetric_and_the_boundary_is_real() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var within := GridFixture.flat(2, 1)
	GridFixture.place_floor(within, Vector2i(0, 0), unit.step_height() / UnitGeometry.LEVEL_HEIGHT)
	var past := GridFixture.flat(2, 1)
	GridFixture.place_floor(
		past, Vector2i(0, 0), (unit.step_height() + 0.2) / UnitGeometry.LEVEL_HEIGHT
	)

	assert_almost_eq(
		Pathfinder.for_unit(within, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.DEFAULT_COST,
		0.0001,
		"stepping down the step height is a walk"
	)
	assert_almost_eq(
		Pathfinder.for_unit(past, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.HOP_DOWN_COST,
		0.0001,
		"and one tenth further is a real drop"
	)


# --- the log -------------------------------------------------------------------------


## From `test_climb_action.gd`/`test_hop_down_action.gd`, whose `climbed`/`hopped_down` events
## went with their actions: **a vertical leg is still legible in the combat log**, as a `rise`
## on the `move` event. docs/00's rule is that anything a supervisor can only report as a
## feeling must reach the log as a number, and "did it go up?" is exactly that.
func test_a_move_event_carries_the_rise_it_climbed() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 1)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(_step(unit, Vector2i(1, 0)))

	var events: Array[LogEvent] = sink.events_of_kind(&"move")
	assert_eq(events.size(), 1, "one move event")
	if events.is_empty():
		return
	gut.p("move event: %s" % events[0].text)
	assert_almost_eq(
		float(events[0].data["rise"]), UnitGeometry.LEVEL_HEIGHT, 0.0001, "and it carries the rise"
	)
	assert_true("rise" in events[0].text, "which is in the human-readable line too")


## The mirror: a drop reports a negative rise rather than omitting it, so a reader never has
## to infer direction from the cells.
func test_a_drop_reports_a_negative_rise() -> void:
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 2)
	var unit := _make_unit(Vector2i(0, 0))
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	state.try_apply(_step(unit, Vector2i(1, 0)))

	var events: Array[LogEvent] = sink.events_of_kind(&"move")
	assert_eq(events.size(), 1)
	if events.is_empty():
		return
	assert_almost_eq(float(events[0].data["rise"]), -2.0, 0.0001, "down is a negative rise")


# --- being caught on the way ---------------------------------------------------------


## The whole of `test_climb_interrupt.gd`, which existed because **a unit on a ladder is the
## most exposed it will ever be** — slow, committed, unable to take cover — and was once the
## one thing in the game that could not be shot at while moving (`docs/09`: every real
## exposure the same).
##
## It reads the same through `MoveAction` because that is where the rule always lived: the
## per-cell hook fires on the cell the climber steps onto, and a hook that fires stops the
## queue.
func _ladder_board() -> Grid:
	var grid := GridFixture.flat(6, 6)
	for y: int in range(6):
		GridFixture.place_floor(grid, Vector2i(2, y), 2)
	# tb64 Pass F: `LADDER_SEGMENT_RISE` is 1.0, so the 2.0 shelf takes **two** segments. The rise
	# is unchanged and so is every MP figure below — a ladder edge is priced by rise, not by pieces.
	for height: float in [0.0, 1.0]:
		GridPlacement.place(grid, Vector2i(1, 0), DataLibrary.get_part(LADDER), height)
	return grid


func test_a_hook_that_fires_stops_the_queue_on_a_climb() -> void:
	var grid: Grid = _ladder_board()
	var climber := _make_unit(Vector2i(1, 0), false)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var fired := {"count": 0}
	var hook := func(_s: CombatState, _u: Unit) -> bool:
		fired.count += 1
		return true

	var climb: MoveAction = _step(climber, Vector2i(2, 0))
	assert_true(climb.is_legal(state), "sanity: the ladder makes this step legal")
	var result: Dictionary = climb.apply_interruptible(state, hook)

	assert_eq(fired.count, 1, "the hook is consulted exactly once for one step")
	assert_true(result.stopped, "and a hook that fires stops the queue")
	assert_eq(climber.cell, Vector2i(2, 0), "the climb itself completes — being shot on a ladder")
	assert_almost_eq(climber.height, 2.0, 0.001, "ends the turn, it does not rewind the rungs")


func test_a_hook_that_does_not_fire_leaves_the_climb_uninterrupted() -> void:
	var grid: Grid = _ladder_board()
	var climber := _make_unit(Vector2i(1, 0), false)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var hook := func(_s: CombatState, _u: Unit) -> bool: return false
	var result: Dictionary = _step(climber, Vector2i(2, 0)).apply_interruptible(state, hook)

	assert_false(result.stopped, "a quiet hook changes nothing")
	assert_eq(climber.cell, Vector2i(2, 0))


func test_plain_apply_still_climbs() -> void:
	var grid: Grid = _ladder_board()
	var climber := _make_unit(Vector2i(1, 0), false)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	_step(climber, Vector2i(2, 0)).apply(state)

	assert_eq(climber.cell, Vector2i(2, 0), "no hook at all is the ordinary path")
	assert_almost_eq(climber.height, 2.0, 0.001)


## **The same rule, not a parallel one.** An interrupted climb returns the queue to the
## resolver with the same reason an interrupted move does, through the same
## `apply_interruptible` contract every action now answers.
func test_an_interrupted_climb_stops_the_queue_the_way_an_interrupted_move_does() -> void:
	var grid: Grid = _ladder_board()
	var climber := _make_unit(Vector2i(1, 0), false)
	var state := CombatState.new(grid, [climber])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var queue := ActionQueue.new(climber)
	assert_true(queue.enqueue(_step(climber, Vector2i(2, 0)), state), "the climb queues")
	var hook := func(_s: CombatState, _u: Unit) -> bool: return true
	var outcome: Dictionary = state.resolve_until(queue, hook)

	assert_eq(outcome["kind"], Enums.ResolveOutcome.STOPPED, "the queue stopped")
	assert_eq(outcome["reason"], &"mid_move_interrupt", "for the move interrupt reason")


## From `test_climb_interrupt.gd`'s own closing claim, and the one worth keeping most: an
## overwatcher is wired to a vertical step through **no second code path at all** — the
## resolver makes one `apply_interruptible` call and does not know the step went up.
func test_an_overwatcher_catches_a_climb_through_no_second_code_path() -> void:
	var grid: Grid = _ladder_board()
	var climber := _make_unit(Vector2i(1, 0), false)
	var watcher := _make_unit(Vector2i(4, 4), false)
	watcher.squad_id = 1
	var state := CombatState.new(grid, [climber, watcher])
	state.assign_all_to_human()
	state.force_current_unit(climber.id)

	var seen: Array[Vector2i] = []
	var hook := func(_s: CombatState, u: Unit) -> bool:
		seen.append(u.cell)
		return false
	_step(climber, Vector2i(2, 0)).apply_interruptible(state, hook)

	gut.p("hook saw the climber at %s" % [seen])
	assert_eq(seen, [Vector2i(2, 0)] as Array[Vector2i], "the watcher sees the cell climbed onto")


# --- a climb has a position along it (tb62 Pass C2) -----------------------------------


## An eight-segment ladder: 8.0 of rise from (0,0) to the shelf at (1,0). At
## `LADDER_COST_SCALE` that edge costs `ceil(4.0 * 8.0 * 0.5)` = 16 MP, which is more than
## any turn's whole budget — the case `LADDER_COST_SCALE` was lowered to paper over.
##
## **Eight pieces since tb64 Pass F, and the same 16 MP.** `LADDER_SEGMENT_RISE` went 2.0 -> 1.0,
## so the same rise needs twice the segments — and costs exactly what it did, because
## `Pathfinder.move_cost` prices the edge by rise and never counts pieces. The number in the
## sentence above is the one that matters and it did not move.
func _tall_ladder_board() -> Grid:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 8.0 / UnitGeometry.LEVEL_HEIGHT)
	for step: int in range(8):
		GridPlacement.place(
			grid,
			Vector2i(0, 0),
			DataLibrary.get_part(LADDER),
			float(step) * Surface.LADDER_SEGMENT_RISE
		)
	return grid


## **The acceptance: a climb longer than this turn's MP leaves the unit partway up.**
##
## Before this pass the same board produced no movement at all — `is_legal` refused the whole
## path, so a tall ladder was not expensive, it was impossible. That is the real fix for tall
## ladders the taskblock asks for, rather than a cheaper scale factor.
func test_a_climb_longer_than_the_turn_leaves_the_unit_partway_up() -> void:
	var grid: Grid = _tall_ladder_board()
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)

	var cost: float = Pathfinder.for_unit(grid, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0))
	var budget: float = unit.mp + float(unit.ap) * unit.mp_per_ap()
	gut.p("the ladder edge costs %.0f MP; the turn affords %.0f" % [cost, budget])
	assert_gt(cost, budget, "sanity: this climb cannot be finished in one turn")

	var move: MoveAction = _step(unit, Vector2i(1, 0))
	assert_true(move.is_legal(state), "a climb that can be STARTED is legal")
	var result: Dictionary = move.apply_interruptible(state)

	gut.p(
		(
			"after one turn: cell %s, height %.2f, ap %d, mp %.1f"
			% [unit.cell, unit.height, unit.ap, unit.mp]
		)
	)
	assert_true(result.stopped, "the move reports it could not complete")
	assert_eq(unit.cell, Vector2i(0, 0), "the unit is still on the ladder's own cell")
	assert_gt(unit.height, 0.0, "but no longer on the floor of it")
	assert_lt(unit.height, 8.0, "and not yet at the top")
	assert_almost_eq(unit.height, 8.0 * budget / cost, 0.0001, "it bought the share it paid for")


## **The partial position is a real board position: pathable FROM.** The rise it has left is
## what the next step is priced against, not the rise it started with — which is the one thing
## `Pathfinder` genuinely had to learn (`_height_leaving`).
func test_the_remaining_rise_is_what_the_next_turn_pays_for() -> void:
	var grid: Grid = _tall_ladder_board()
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)
	var full: float = Pathfinder.for_unit(grid, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0))

	_step(unit, Vector2i(1, 0)).apply_interruptible(state)
	var remaining: float = Pathfinder.for_unit(grid, unit).move_cost(Vector2i(0, 0), Vector2i(1, 0))

	gut.p("edge cost %.0f from the floor, %.0f from partway up" % [full, remaining])
	assert_lt(remaining, full, "a unit partway up is quoted the rise it has LEFT")
	assert_gt(remaining, 0.0, "and still has some to pay")


## **And it finishes.** Given enough turns the unit reaches the top — a tall climb costing
## several turns is correct; a tall climb being unpurchasable was not.
func test_a_tall_climb_completes_across_turns() -> void:
	var grid: Grid = _tall_ladder_board()
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)

	var turns := 0
	while unit.cell != Vector2i(1, 0) and turns < 8:
		unit.ap = unit.max_ap
		unit.mp = 0.0
		var move: MoveAction = _step(unit, Vector2i(1, 0))
		if not move.is_legal(state):
			break
		move.apply_interruptible(state)
		turns += 1
		gut.p("turn %d: height %.2f" % [turns, unit.height])

	assert_eq(unit.cell, Vector2i(1, 0), "the unit reaches the top")
	assert_almost_eq(unit.height, 8.0, 0.0001, "at the shelf's real height")
	assert_gt(turns, 1, "and it genuinely took more than one turn")


## **Visible and shootable partway up.** The body is drawn and projected from `Unit.height`,
## so a unit halfway up a ladder is a target at the height it actually reached — not at the
## floor it left. Read back off the real geometry rather than off the field.
func test_a_unit_partway_up_is_a_real_target_at_its_real_height() -> void:
	var grid: Grid = _tall_ladder_board()
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)
	var on_the_floor: AABB = UnitGeometry.bounding_box(unit)

	_step(unit, Vector2i(1, 0)).apply_interruptible(state)
	var partway: AABB = UnitGeometry.bounding_box(unit)

	gut.p("body centre Y %.2f -> %.2f" % [on_the_floor.get_center().y, partway.get_center().y])
	assert_almost_eq(
		partway.get_center().y - on_the_floor.get_center().y,
		unit.height,
		0.0001,
		"the drawn and shot-planed body rose by exactly the height the climb bought"
	)


## **A seeded partial climb is reproducible** — the same board and the same budget stop at the
## same height every time. Determinism is the standing rule and a fractional position is
## exactly the sort of thing that quietly stops obeying it.
func test_a_partial_climb_is_reproducible() -> void:
	var heights: Array[float] = []
	for run: int in range(3):
		var grid: Grid = _tall_ladder_board()
		var unit := _make_unit(Vector2i(0, 0), false)
		var state := CombatState.new(grid, [unit])
		state.assign_all_to_human()
		state.force_current_unit(unit.id)
		_step(unit, Vector2i(1, 0)).apply_interruptible(state)
		heights.append(unit.height)

	gut.p("three runs stopped at %s" % [heights])
	assert_almost_eq(heights[0], heights[1], 0.0000001, "run 1 and 2 agree")
	assert_almost_eq(heights[1], heights[2], 0.0000001, "and so do 2 and 3")


## **A horizontal step does not divide**, and neither does a drop. Only a climb has a position
## along it — a walk has nowhere to stop between two cells, and a drop is one motion rather
## than a sustained effort.
func test_only_a_climb_divides() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 2)
	var unit := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)
	unit.ap = 0
	unit.mp = 0.0

	var drop: MoveAction = _step(unit, Vector2i(1, 0))
	assert_false(drop.is_legal(state), "a drop with no budget simply does not happen")
	assert_almost_eq(unit.height, 2.0, 0.0001, "and the unit has not sunk partway into it")


## **An overwatcher catches a unit dropping off a ledge**, which is the taskblock's own Pass D
## test and the exposure `HopDownAction` was faulted for never checking.
##
## **Added after the fact, and the omission is worth recording.** The retirement rested on
## measuring that `apply_stepwise` fires the hook on every cell *including the one it drops
## onto* — but that measurement lived in a scratch probe that was deleted, so the argument was
## made from a number nothing pinned. Its climbing twin
## (`test_an_overwatcher_catches_a_climb_through_no_second_code_path`) was retained and this
## one was not, which is exactly the asymmetry that let the gap through.
func test_an_overwatcher_catches_a_drop_on_the_cell_it_lands_on() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 2)
	var mover := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [mover])
	state.assign_all_to_human()
	state.force_current_unit(mover.id)

	var seen: Array[Vector2i] = []
	var hook := func(_s: CombatState, u: Unit) -> bool:
		seen.append(u.cell)
		return false
	var drop: MoveAction = _step(mover, Vector2i(1, 0))
	assert_true(drop.is_legal(state), "sanity: the drop is a legal step")
	drop.apply_interruptible(state, hook)

	gut.p("the hook saw the dropping unit at %s" % [seen])
	assert_eq(
		seen,
		[Vector2i(1, 0)] as Array[Vector2i],
		"the watcher sees the unit on the cell it dropped ONTO — a drop is not a blind spot"
	)


## And a hook that fires stops the drop's queue, the same way it stops a climb's.
func test_a_hook_that_fires_stops_the_queue_on_a_drop() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), 2)
	var mover := _make_unit(Vector2i(0, 0), false)
	var state := CombatState.new(grid, [mover])
	state.assign_all_to_human()
	state.force_current_unit(mover.id)

	var hook := func(_s: CombatState, _u: Unit) -> bool: return true
	var result: Dictionary = _step(mover, Vector2i(1, 0)).apply_interruptible(state, hook)

	assert_true(result.stopped, "being caught mid-drop ends the turn")
	assert_eq(mover.cell, Vector2i(1, 0), "and the drop itself completes")
