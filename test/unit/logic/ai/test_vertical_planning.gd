extends GutTest

## tb62 Passes D and E: **what the planner knows about going up and coming down.**
##
## The block's original framing for these passes did not survive measurement, and this file
## records what replaced it. `ClimbAction`/`HopDownAction` turned out to be reachable from
## neither the player nor the AI while `MoveAction` already crossed every vertical edge at the
## same cost — a real planned turn had been going up ladders all along — so they were retired
## (Pass C1) rather than given utility actions that would have raced them.
##
## **What was genuinely missing is here:**
##
## - **The planner did not know a hop-down is one-way.** Descent is free; ascent needs a step,
##   a ladder, a lift or a capability nothing authors, so a unit could drop somewhere it could
##   not leave. `can_return` is the consideration that prices it.
## - **The mag lift had no planner path and could not get one by accident**, because it is not
##   a `Pathfinder` edge at all — it is an AP-costing teleport. `ride_mag_lift.tres` is the
##   action, and it is the interesting one: it competes for AP against shooting.

const LADDER := &"ladder"
const PAD := &"mag_lift_pad"


func _unit(cell: Vector2i, squad: int, tier: StringName = &"TRAINED") -> Unit:
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad)
	unit.intelligence_tier = tier
	return unit


## `DataLibrary` exposes the pool rather than a by-id lookup for utility actions, so this is
## the lookup — kept in one place instead of a loop per test.
func _authored(action_id: StringName) -> UtilityActionDef:
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if action.id == action_id:
			return action
	return null


func _staged(grid: Grid, units: Array[Unit]) -> Dictionary:
	var state := CombatState.new(grid, units, 7)
	state.assign_rest_to_ai([] as Array[int])
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	return {"state": state, "mission": mission, "view": WorldView.full(state)}


# --- Pass D: a hop-down is one-way, and the planner knows ------------------------------


## A pit: (1,1) sits two levels below everything around it, with no ladder. Anything can drop
## in; nothing without a climbing capability gets out.
func _pit_board() -> Grid:
	var grid := GridFixture.flat(5, 5, 2.0)
	GridFixture.place_floor(grid, Vector2i(1, 1), 0.0)
	return grid


## **The measurement the consideration rests on**: the pit really is one-way for this body.
## Asserted first, because a penalty for stranding is meaningless if the fixture does not
## actually strand.
func test_the_pit_is_genuinely_one_way() -> void:
	var grid: Grid = _pit_board()
	var unit: Unit = _unit(Vector2i(1, 2), 0)
	var pf := Pathfinder.for_unit(grid, unit)

	gut.p(
		(
			"down %.1f, back up %.1f"
			% [pf.move_cost(Vector2i(1, 2), Vector2i(1, 1)), pf.move_cost(Vector2i(1, 1), Vector2i(1, 2))]
		)
	)
	assert_gt(pf.move_cost(Vector2i(1, 2), Vector2i(1, 1)), 0.0, "the drop in is a legal edge")
	assert_almost_eq(
		pf.move_cost(Vector2i(1, 1), Vector2i(1, 2)), -1.0, 0.0001, "and the way back is not"
	)


## **`can_return` reads 0 for the pit and 1 for ordinary ground**, off one reverse flood.
func test_the_context_knows_which_cells_strand_the_unit() -> void:
	var grid: Grid = _pit_board()
	var mover: Unit = _unit(Vector2i(1, 2), 0)
	var enemy: Unit = _unit(Vector2i(4, 4), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(
		staged["state"].units[0], staged["view"], staged["mission"]
	)

	var in_the_pit: float = context.inputs_for(Vector2i(1, 1))[UtilityContext.INPUT_CAN_RETURN]
	var on_the_floor: float = context.inputs_for(Vector2i(2, 2))[UtilityContext.INPUT_CAN_RETURN]

	gut.p("can_return — pit %.1f, ordinary ground %.1f" % [in_the_pit, on_the_floor])
	assert_almost_eq(in_the_pit, 0.0, 0.0001, "dropping into the pit strands the unit")
	assert_almost_eq(on_the_floor, 1.0, 0.0001, "ordinary ground does not")


## **It is a cost, not a prohibition — assert both, or the rule is the wrong shape.**
##
## The same cell, scored twice against the same authored action: once as a returnable cell and
## once as a stranding one. The stranding score must be genuinely lower and genuinely
## non-zero, because a veto would forbid the drop that reaches an otherwise unreachable
## target, and that drop is sometimes exactly right.
func test_stranding_is_priced_rather_than_forbidden() -> void:
	var action: UtilityActionDef = _authored(&"approach")
	assert_not_null(action, "the approach action is authored")
	if action == null:
		return
	var profile: UtilityProfile = DataLibrary.get_utility_profile(&"")

	var base: Dictionary = {}
	for consideration: ConsiderationDef in action.considerations:
		base[consideration.input_id] = 1.0
	var stranding: Dictionary = base.duplicate()
	stranding[UtilityContext.INPUT_CAN_RETURN] = 0.0

	var safe_score: float = UtilityScorer.score(action, base, profile)
	var stranding_score: float = UtilityScorer.score(action, stranding, profile)

	gut.p("approach scores %.3f returnable, %.3f stranding" % [safe_score, stranding_score])
	assert_lt(stranding_score, safe_score, "stranding costs the candidate real utility")
	assert_gt(stranding_score, 0.0, "but never vetoes it — a good enough reason still wins")


## **And a good enough reason does win.** With every other consideration at its floor on the
## safe cell and at its ceiling in the pit, the pit outscores it — which is the half that
## proves this is a weight rather than a wall.
func test_a_good_enough_reason_outbids_the_stranding_penalty() -> void:
	var action: UtilityActionDef = _authored(&"approach")
	if action == null:
		return
	var profile: UtilityProfile = DataLibrary.get_utility_profile(&"")

	var poor_but_safe: Dictionary = {}
	var rich_but_stranding: Dictionary = {}
	for consideration: ConsiderationDef in action.considerations:
		poor_but_safe[consideration.input_id] = 0.1
		rich_but_stranding[consideration.input_id] = 1.0
	poor_but_safe[UtilityContext.INPUT_CAN_RETURN] = 1.0
	rich_but_stranding[UtilityContext.INPUT_CAN_RETURN] = 0.0

	var safe: float = UtilityScorer.score(action, poor_but_safe, profile)
	var stranding: float = UtilityScorer.score(action, rich_but_stranding, profile)

	gut.p("poor-but-safe %.3f vs rich-but-stranding %.3f" % [safe, stranding])
	assert_gt(stranding, safe, "a cell worth having beats a cell that is merely escapable")


## Every action that can relocate carries the consideration. The ones pinned to the unit's own
## cell do not, and must not — they cannot strand anybody.
func test_every_relocating_action_prices_stranding() -> void:
	var missing: Array[String] = []
	var pinned: Array[String] = []
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		var prices_it := false
		for consideration: ConsiderationDef in action.considerations:
			if consideration.input_id == UtilityContext.INPUT_CAN_RETURN:
				prices_it = true
		var stays_put: bool = UtilityContext.PRED_CELL_IS_CURRENT in action.preconditions
		if stays_put and prices_it:
			pinned.append(String(action.id))
		elif not stays_put and not prices_it:
			missing.append(String(action.id))

	gut.p("%d authored actions checked" % DataLibrary.utility_actions_pool().size())
	assert_eq(missing, [] as Array[String], "these can relocate and ignore stranding: %s" % [missing])
	assert_eq(pinned, [] as Array[String], "these cannot move and should not price it: %s" % [pinned])


# --- Pass E: the AI rides the lift -----------------------------------------------------


## A shelf at x>=3 reachable only by a mag lift standing at (2,2). Wide, so the enemy on the
## shelf is **out of weapon range** — otherwise the unit simply shoots across the height
## difference and never needs to go anywhere, which is a correct decision and tests nothing.
func _lift_board() -> Grid:
	var grid := GridFixture.flat(20, 5)
	for y: int in range(5):
		for x: int in range(3, 20):
			GridFixture.place_floor(grid, Vector2i(x, y), 2.0)
	GridPlacement.place(grid, Vector2i(2, 2), DataLibrary.get_part(PAD).duplicate(true), 0.0)
	GridPlacement.place(grid, Vector2i(3, 2), DataLibrary.get_part(PAD).duplicate(true), 2.0)
	return grid


## **The lift is not a pathfinder edge**, which is exactly why it needed a planner action of
## its own — nothing about walking could ever discover it.
func test_the_shelf_is_unreachable_by_walking() -> void:
	var grid: Grid = _lift_board()
	var unit: Unit = _unit(Vector2i(2, 2), 0)
	var pf := Pathfinder.for_unit(grid, unit)

	assert_eq(
		pf.astar(Vector2i(2, 2), Vector2i(4, 2)),
		[] as Array[Vector2i],
		"no walking route onto the shelf exists at all"
	)
	assert_eq(
		Surface.mag_lift_destination(grid, Vector2i(2, 2)), Vector2i(3, 2), "but the lift goes there"
	)


## **The precondition offers the ride only where a lift actually is.** A guaranteed refusal in
## every decision log on the board is worse than no entry.
func test_the_ride_is_offered_on_a_pad_and_nowhere_else() -> void:
	var grid: Grid = _lift_board()
	var mover: Unit = _unit(Vector2i(2, 2), 0)
	var enemy: Unit = _unit(Vector2i(18, 2), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(
		staged["state"].units[0], staged["view"], staged["mission"]
	)

	assert_true(
		context.predicates_for(Vector2i(2, 2))[UtilityContext.PRED_CELL_HAS_MAG_LIFT],
		"the pad's own cell offers the ride"
	)
	assert_false(
		context.predicates_for(Vector2i(1, 1))[UtilityContext.PRED_CELL_HAS_MAG_LIFT],
		"and bare ground does not"
	)


## **The ride's value is measured at the cell it takes you to**, which is the modelling
## problem the framework does not solve on its own: it scores cells, and a lift's whole point
## is the other one.
func test_the_lift_is_worth_something_only_when_it_gains_ground() -> void:
	var grid: Grid = _lift_board()
	var mover: Unit = _unit(Vector2i(2, 2), 0)
	var enemy: Unit = _unit(Vector2i(18, 2), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var context: UtilityContext = UtilityContext.build(
		staged["state"].units[0], staged["view"], staged["mission"]
	)

	var on_the_pad: float = context.inputs_for(Vector2i(2, 2))[UtilityContext.INPUT_LIFT_ADVANCE]
	var off_it: float = context.inputs_for(Vector2i(1, 2))[UtilityContext.INPUT_LIFT_ADVANCE]

	gut.p("lift_advance — on the pad %.2f, off it %.2f" % [on_the_pad, off_it])
	assert_gt(on_the_pad, 0.0, "riding toward the enemy's tier is worth something")
	assert_almost_eq(off_it, 0.0, 0.0001, "a cell with no lift on it gains nothing by definition")


## **The acceptance: a target reachable only by lift gets reached.**
func test_the_planner_rides_a_lift_to_reach_an_otherwise_unreachable_target() -> void:
	var grid: Grid = _lift_board()
	var mover: Unit = _unit(Vector2i(2, 2), 0)
	var enemy: Unit = _unit(Vector2i(18, 2), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var state: CombatState = staged["state"]
	state.force_current_unit(state.units[0].id)

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		state.units[0], staged["view"], staged["mission"]
	)
	var queued: Array[String] = []
	var rode := false
	for action: CombatAction in queue.actions:
		queued.append(action.describe())
		if action is MagLiftAction:
			rode = true

	gut.p("queued: %s" % ", ".join(queued))
	assert_true(rode, "the planner queued the ride rather than standing on the pad forever")


## **`MINDLESS` does not get an action its tier excludes.** The gap between tiers is
## information and reach, and a tier that cannot shoot or take cover does not operate
## machinery either.
func test_a_mindless_unit_is_never_offered_the_ride() -> void:
	var grid: Grid = _lift_board()
	var mover: Unit = _unit(Vector2i(2, 2), 0, &"MINDLESS")
	var enemy: Unit = _unit(Vector2i(18, 2), 1)
	var staged: Dictionary = _staged(grid, [mover, enemy] as Array[Unit])
	var state: CombatState = staged["state"]
	state.force_current_unit(state.units[0].id)

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		state.units[0], staged["view"], staged["mission"]
	)
	for action: CombatAction in queue.actions:
		assert_false(action is MagLiftAction, "a MINDLESS unit was offered the lift")

	var lift: UtilityActionDef = _authored(&"ride_mag_lift")
	assert_not_null(lift)
	if lift != null:
		assert_false(&"MINDLESS" in lift.tiers, "and the tier list is where that is decided")
