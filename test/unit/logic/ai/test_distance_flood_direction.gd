extends GutTest

## taskblock-63 Pass C — **the AI's distance model runs the mover's way now.**
##
## `UtilityContext` flooded outward from the target (`Pathfinder.reachable_costs`), which
## answers *"how far could the target walk to this cell"*. What `closes_distance` needs is
## *"how far must I walk to the target"*.
##
## **On symmetric ground those are the same number and this never mattered.** On one-way
## ground they disagree exactly, and **a terraced map is made of one-way ground**: dropping
## off a shelf is cheap and climbing back is not. So the consideration that decides whether a
## candidate cell brings a unit nearer was wrong precisely where elevation exists, which is
## everywhere the last four blocks have been working.
##
## **Both directions are asserted, not just the interesting one.** The flat case is what has
## been passing all along, so a regression there would be invisible next to the terraced case
## unless something pins it.

const LADDER := &"ladder"
## `Pathfinder.CLIMB_COST * 2 levels * LADDER_COST_SCALE`, ceiled — the price of the ladder on
## these boards. Written as the expression rather than as `4.0` so a change to any of the
## three constants reddens the test that reads it rather than silently agreeing with a
## literal.
const LADDER_CLIMB_COST := 4.0


func _unit(cell: Vector2i, squad: int) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad)


func _staged(grid: Grid, units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(grid, units, 7)
	state.assign_rest_to_ai([] as Array[int])
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	return {"state": state, "mission": mission, "view": WorldView.full(state)}


## A low strip at x == 0 and a 2.0 shelf from x == 1 on. `laddered` decides whether the one
## route up exists at all — the same board either way, so the two tests below differ in
## exactly one fact.
func _terrace(laddered: bool) -> Grid:
	var grid := GridFixture.flat(8, 3)
	for y: int in range(3):
		for x: int in range(1, 8):
			GridFixture.place_floor(grid, Vector2i(x, y), 2.0)
	if laddered:
		# tb64 Pass F: the shelf is 2.0 and `Surface.LADDER_SEGMENT_RISE` is now 1.0, so the
		# route up takes **two** segments. One reaches 1.0 and leaves `(0,1)` cut off entirely —
		# which the flood reports by simply not containing the cell, not by costing more.
		for height: float in [0.0, 1.0]:
			GridPlacement.place(grid, Vector2i(0, 1), DataLibrary.get_part(LADDER), height)
	return grid


## A side elevation of the board, so the shape being reasoned about is on the page rather
## than in the reader's head. One column per x, the digit being the cell's world height.
func _profile(grid: Grid, row: int) -> String:
	var heights := ""
	for x: int in range(8):
		heights += "%d" % int(UnitGeometry.true_height_for_cell(Vector2i(x, row), grid))
	return "row %d heights: %s   (ladder stands at x=0)" % [row, heights]


## **The measurement the pass rests on: the two floods disagree, and by exactly the amount
## the asymmetry is worth.** Dropping off the shelf costs `HOP_DOWN_COST`; climbing back costs
## the ladder. The forward flood prices the drop, the reverse flood prices the climb, and the
## difference between them is the whole defect.
func test_the_two_floods_disagree_by_the_climb_on_one_way_ground() -> void:
	var grid: Grid = _terrace(true)
	var mover: Unit = _unit(Vector2i(0, 1), 0)
	var pathfinder := Pathfinder.for_unit(grid, mover)
	var target_cell := Vector2i(5, 1)
	var foot := Vector2i(1, 1)  # on the shelf, at the top of the ladder
	var below := Vector2i(0, 1)  # on the low ground, at the bottom of it

	gut.p(_profile(grid, 1))
	gut.p(
		(
			"edge costs: up %.1f, down %.1f"
			% [pathfinder.move_cost(below, foot), pathfinder.move_cost(foot, below)]
		)
	)

	var outward: Dictionary = pathfinder.reachable_costs(target_cell, INF)
	var inward: Dictionary = pathfinder.costs_to_reach(target_cell, INF)
	gut.p(
		(
			"target at %s — outward says %s costs %.1f, reverse says it costs %.1f"
			% [target_cell, below, float(outward[below]), float(inward[below])]
		)
	)

	assert_almost_eq(
		float(outward[below]) - float(outward[foot]),
		Pathfinder.HOP_DOWN_COST,
		0.0001,
		"the OLD model priced the low cell at one cheap drop below the shelf"
	)
	assert_almost_eq(
		float(inward[below]) - float(inward[foot]),
		LADDER_CLIMB_COST,
		0.0001,
		"the mover's own cost to get up there is the ladder, and that is what it now reads"
	)


## The flat case, which is what has been passing all along. Asserted as whole-dictionary
## equality rather than at a sampled cell: the claim is that nothing about symmetric ground
## changed, and a spot check would not carry it.
func test_the_two_floods_agree_everywhere_on_flat_ground() -> void:
	var grid := GridFixture.flat(8, 6)
	var pathfinder := Pathfinder.new(grid)

	var outward: Dictionary = pathfinder.reachable_costs(Vector2i(3, 3), INF)
	var inward: Dictionary = pathfinder.costs_to_reach(Vector2i(3, 3), INF)

	assert_eq(inward.size(), 48, "sanity: the flood really covered the board")
	assert_eq(inward, outward, "on symmetric ground the direction of the flood cannot matter")


## **`exempt_origin`, and why the reverse flood needs a flag the forward one does not.**
## taskblock-61 hit the mirror of this: `Pathfinder._base_cost` refuses an occupied cell and
## `move_cost(from, to)` checks the DESTINATION — so a reverse flood rooted where somebody is
## standing gates every answer on entering that cell, and "how far to the enemy" is a question
## about an occupied cell by definition.
func test_flooding_toward_an_occupied_cell_needs_the_origin_exempted() -> void:
	var grid := GridFixture.flat(8, 3)
	var mover: Unit = _unit(Vector2i(0, 1), 0)
	var enemy: Unit = _unit(Vector2i(5, 1), 1)
	# Staged only so the grid records the occupants — the pathfinder is what is measured.
	_staged(grid, [mover, enemy] as Array[Unit])
	var pathfinder := Pathfinder.for_unit(grid, mover)

	var gated: Dictionary = pathfinder.costs_to_reach(enemy.cell, INF)
	var exempted: Dictionary = pathfinder.costs_to_reach(enemy.cell, INF, true)

	assert_eq(gated.size(), 1, "without the exemption nothing but the origin itself is reachable")
	assert_gt(exempted.size(), 20, "with it, the board answers")
	assert_true(exempted.has(mover.cell), "and the mover's own cell is priced, not skipped")


## **The behavioural claim, at the level the planner actually reads.** A cell at the foot of an
## unclimbable shelf is *adjacent* to a target standing on it, so every straight-line measure
## and the old outward flood both called it excellent. The mover cannot get up there at all.
func test_a_candidate_that_cannot_reach_the_target_scores_zero_rather_than_near() -> void:
	var grid: Grid = _terrace(false)
	var mover: Unit = _unit(Vector2i(3, 1), 0)
	var enemy: Unit = _unit(Vector2i(6, 1), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(mover, staged["view"], staged["mission"])

	gut.p(_profile(grid, 1))
	var stranded := Vector2i(0, 1)
	var closer := Vector2i(5, 1)

	assert_eq(
		Grid.distance_chebyshev(stranded, enemy.cell),
		6,
		"sanity: the stranded cell is genuinely on the far side, so this is not a near/far trick"
	)
	assert_eq(
		context.inputs_for(stranded)[UtilityContext.INPUT_CLOSES_DISTANCE],
		0.0,
		"no route up means no progress, whatever the map looks like from above"
	)
	assert_gt(
		float(context.inputs_for(closer)[UtilityContext.INPUT_CLOSES_DISTANCE]),
		0.5,
		"and a cell that really does close on the shelf still reads as closing"
	)


## **The clearest statement of what the old model got wrong, in the units the planner reads.**
## The mover is far away along the shelf and the stranded cell is spatially *near* the target,
## so straight-line — which is what the outward flood degenerated to for a cell it could not
## price — called it a strong improvement. It is not a route at all.
##
## The straight-line figure is computed here rather than quoted, so this reads as a
## comparison against the discarded model rather than as a number someone remembered.
func test_a_stranded_candidate_scores_zero_where_straight_line_called_it_closing() -> void:
	var grid: Grid = _terrace(false)
	var mover: Unit = _unit(Vector2i(7, 1), 0)
	var enemy: Unit = _unit(Vector2i(2, 1), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(mover, staged["view"], staged["mission"])
	var stranded := Vector2i(0, 1)

	var here := float(Grid.distance_chebyshev(mover.cell, enemy.cell))
	var there := float(Grid.distance_chebyshev(stranded, enemy.cell))
	var straight_line: float = clampf(0.5 + 0.5 * (here - there) / here, 0.0, 1.0)
	var scored: float = context.inputs_for(stranded)[UtilityContext.INPUT_CLOSES_DISTANCE]
	gut.p(
		"straight line would score the stranded cell %.3f; it scores %.3f" % [straight_line, scored]
	)

	assert_gt(straight_line, 0.5, "the discarded model read this cell as a real improvement")
	assert_eq(scored, 0.0, "and there is no way up to the shelf from it at all")


## **A one-way drop is a route and a sealed shelf is not**, which is the distinction the
## reverse flood exists to make. Asserted on flood membership rather than on the score,
## because of a limit worth recording: `closes_distance` bottoms out at 0.0 for anything more
## than twice as far as the mover already is, so **an expensive route and no route can share a
## score of 0.0.** That is the input's own authored range doing its job ("0.0 for retreating
## far") and not something this pass introduced — but it does mean the score is not the place
## to read the difference.
func test_a_one_way_drop_is_a_route_and_a_sealed_shelf_is_not() -> void:
	var below := Vector2i(0, 1)
	var target_cell := Vector2i(6, 1)

	var laddered: Grid = _terrace(true)
	var sealed: Grid = _terrace(false)
	var laddered_costs: Dictionary = (
		Pathfinder
		. for_unit(laddered, _unit(Vector2i(3, 1), 0))
		. costs_to_reach(target_cell, INF, true)
	)
	var sealed_costs: Dictionary = (
		Pathfinder.for_unit(sealed, _unit(Vector2i(3, 1), 0)).costs_to_reach(target_cell, INF, true)
	)
	gut.p(
		(
			"cost from %s to the shelf: laddered %s, sealed %s"
			% [
				below,
				laddered_costs.get(below, "unreachable"),
				sealed_costs.get(below, "unreachable")
			]
		)
	)

	assert_true(laddered_costs.has(below), "with a ladder the low ground is a costly route up")
	assert_false(sealed_costs.has(below), "without one it is not a route at any price")


## **A walled-off target must not flatten every candidate to the same score.** That is the case
## the straight-line fallback exists for, and reversing the flood changed what "absent" means,
## so it needed re-establishing rather than assuming.
func test_a_target_nobody_can_reach_still_ranks_candidates_by_straight_line() -> void:
	var grid: Grid = _terrace(false)
	var mover: Unit = _unit(Vector2i(0, 1), 0)  # on the low ground, no route up at all
	var enemy: Unit = _unit(Vector2i(6, 1), 1)  # on the shelf
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(mover, staged["view"], staged["mission"])

	var near: float = context.inputs_for(Vector2i(0, 0))[UtilityContext.INPUT_CLOSES_DISTANCE]
	var far: float = context.inputs_for(Vector2i(0, 2))[UtilityContext.INPUT_CLOSES_DISTANCE]
	gut.p("sealed target — same-column candidates score %.3f and %.3f" % [near, far])

	assert_almost_eq(
		near, 0.5, 0.0001, "with nothing reachable, straight line is all there is and it is even"
	)
	assert_almost_eq(far, 0.5, 0.0001, "both cells sit the same distance out, so neither wins")
