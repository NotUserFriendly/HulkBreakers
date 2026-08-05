extends GutTest

## taskblock-46 Pass E: the Elite lookahead.
##
## ## The two things a lookahead test has to prove, and only one is obvious
##
## The obvious one is that it predicts correctly — an enemy with a clear lane onto
## a cell is a threat to it, one behind a wall is not.
##
## The one that is easy to skip is that **it changes what the unit does.** A search
## that runs, produces a number nobody's score is sensitive to, and costs a scoring
## pass per turn is worse than no search at all, and every test asserting it
## computes the right threat would still pass. `docs/11` names that failure mode:
## a tier or restriction that does nothing passes every test asserting what it
## should do. So the assertions here come in pairs — what it predicts, and what
## turning it off changes.

const ELITE := &"ELITE"
const TRAINED := &"TRAINED"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()
	UtilityLookahead.reset_diagnostics()


func after_each() -> void:
	DataLibrary.reset()


func _armed(id: StringName, cell: Vector2i, squad: int, tier: StringName) -> Unit:
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad)
	unit.id = int(abs(hash(id))) % 10000
	unit.intelligence_tier = tier
	unit.ap = unit.max_ap
	return unit


## An open board with one wall column, so "behind the wall" and "in the open" are
## both real places rather than a re-derivation of the same geometry.
func _field(hunter_tier: StringName = ELITE) -> Dictionary:
	var grid: Grid = GridFixture.flat(24, 16)
	# A wall stub that leaves the middle row open, so the board has BOTH a clear
	# firing lane and a shadow behind cover. A wall spanning the whole column would
	# hide the enemy outright and the lookahead would correctly predict nothing —
	# the first version of this fixture did exactly that and every threat came back
	# empty, which reads identically to a search that does not work.
	#
	# **`place_wall`, never `place_floor` plus a blocker.** Sight is blocked by
	# `Grid.opacity`, which only `place_wall` sets — a hand-rolled blocker is cover
	# that everything can see straight through, so a board built that way tests
	# geometry it does not actually have.
	for y in range(0, 7):
		GridFixture.place_wall(grid, Vector2i(12, y))
	var hunter: Unit = _armed(&"hunter", Vector2i(6, 8), 0, hunter_tier)
	var prey: Unit = _armed(&"prey", Vector2i(18, 8), 1, TRAINED)
	var state := CombatState.new(grid, [hunter, prey])
	state.force_current_unit(hunter.id)
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	return {"grid": grid, "state": state, "hunter": hunter, "prey": prey, "view": view}


func _context(bout: Dictionary) -> UtilityContext:
	return UtilityContext.build(bout.hunter, bout.view)


# --- who searches at all ------------------------------------------------------


## The tier gate, and it is a gate on INFORMATION rather than on an action —
## `docs/11`'s rule. A Trained unit is offered every action Elite is; it just does
## not know what happens next.
func test_only_elite_searches() -> void:
	for tier: StringName in [&"MINDLESS", &"GRUNT", TRAINED]:
		var bout: Dictionary = _field(tier)
		assert_false(UtilityLookahead.searches(bout.hunter), "%s must not search" % tier)
		assert_eq(
			await UtilityLookahead.threat_map(_context(bout), [Vector2i(8, 8)] as Array[Vector2i]),
			{},
			"%s gets no map at all, not a map of zeroes" % tier
		)

	var elite: Dictionary = _field(ELITE)
	assert_true(UtilityLookahead.searches(elite.hunter))


## A tier that does not search must not pay for the search either — the diagnostic
## exists so "it is free below Elite" is a measurement rather than a claim.
func test_a_tier_that_does_not_search_builds_no_fields() -> void:
	var bout: Dictionary = _field(TRAINED)
	UtilityLookahead.reset_diagnostics()

	await UtilityLookahead.threat_map(_context(bout), _context(bout).candidate_cells)

	assert_eq(UtilityLookahead.fields_built, 0)


# --- what it predicts ---------------------------------------------------------


## The shallow ply: a cell in the enemy's open lane is threatened, a cell in the
## wall's shadow is not. **Both cells on the same board in the same call**, so the
## comparison cannot be an artifact of two differently-built fixtures.
func test_the_shallow_ply_tells_the_open_lane_from_the_wall_s_shadow() -> void:
	var bout: Dictionary = _field()
	var exposed := Vector2i(10, 8)  # the open lane, straight down the prey's row
	var sheltered := Vector2i(10, 6)  # tucked into the wall stub's shadow
	var enemies: Array[Unit] = [bout.prey] as Array[Unit]
	var fields: Array = [VisibilityField.build(bout.state.grid, (bout.prey as Unit).cell)]

	var open: float = UtilityLookahead._threat_from_standing_enemies(exposed, enemies, fields)
	var shadow: float = UtilityLookahead._threat_from_standing_enemies(sheltered, enemies, fields)

	gut.p("standing enemy: exposed %.2f, sheltered %.2f" % [open, shadow])
	assert_eq(open, 1.0, "the only enemy has a clear lane onto the exposed cell")
	assert_eq(shadow, 0.0, "and none onto the sheltered one")


## **What the deeper ply is FOR, stated as the thing it changes.**
##
## The sheltered cell is safe from an enemy that stands still and not safe from one
## that walks four squares around the wall stub. Depth 2 calls it safe; depth 3
## calls it exposed; and "cover that the enemy can simply step around is not cover"
## is the entire behavioural difference between an Elite unit and a Trained one.
##
## This started life as a vaguer assertion — "the deeper ply finds something new
## somewhere" — which passed vacuously the moment the shortlist happened to fill up
## with cells that were already threatened. Naming the cell is what makes it a test.
func test_the_deeper_ply_sees_the_enemy_walk_around_the_cover() -> void:
	var bout: Dictionary = _field()
	var exposed := Vector2i(10, 8)
	var sheltered := Vector2i(10, 6)
	var enemies: Array[Unit] = [bout.prey] as Array[Unit]
	var fields: Array = [VisibilityField.build(bout.state.grid, (bout.prey as Unit).cell)]
	var shallow: float = UtilityLookahead._threat_from_standing_enemies(sheltered, enemies, fields)

	# A two-cell list, so both get the expensive ply rather than depending on where
	# they land in a shortlist.
	var deep: Dictionary = await UtilityLookahead.threat_map(
		_context(bout), [exposed, sheltered] as Array[Vector2i]
	)

	gut.p("sheltered cell: depth 2 %.2f, depth 3 %.2f" % [shallow, deep[sheltered]])
	assert_eq(shallow, 0.0, "sanity: the shallow ply thinks this cell is safe")
	assert_gt(
		float(deep[sheltered]),
		shallow,
		"the enemy can walk around the wall, and only the deeper ply knows it"
	)


## Threat is a SHARE, so it has to stay inside 0–1 whatever the enemy count —
## a consideration input that leaves that range multiplies the whole score by
## something nobody authored.
func test_threat_is_normalised_between_zero_and_one() -> void:
	var bout: Dictionary = _field()
	var context: UtilityContext = _context(bout)

	var threats: Dictionary = await UtilityLookahead.threat_map(context, context.candidate_cells)

	assert_gt(threats.size(), 0, "sanity: it examined something")
	for cell: Vector2i in threats:
		assert_between(float(threats[cell]), 0.0, 1.0, "threat at %s" % cell)


## **Depth 3 is nested inside depth 2, never an alternative to it.** An enemy that
## can shoot a cell from where it stands can also shoot it after choosing not to
## move, so the deeper ply can only ever widen the set — the monotonicity that lets
## the two plies be `maxf`-ed together rather than reconciled.
func test_the_deeper_ply_never_predicts_less_threat_than_the_shallow_one() -> void:
	var bout: Dictionary = _field()
	var context: UtilityContext = _context(bout)
	var cells: Array[Vector2i] = context.candidate_cells

	var shallow_only: Dictionary = {}
	var enemies: Array[Unit] = [bout.prey] as Array[Unit]
	var fields: Array = [VisibilityField.build(bout.state.grid, (bout.prey as Unit).cell)]
	for cell: Vector2i in cells:
		shallow_only[cell] = UtilityLookahead._threat_from_standing_enemies(cell, enemies, fields)
	var both: Dictionary = await UtilityLookahead.threat_map(context, cells)

	for cell: Vector2i in cells:
		assert_gte(
			float(both[cell]),
			float(shallow_only[cell]),
			"depth 3 lost a threat depth 2 had found, at %s" % cell
		)


## The lookahead reads the `WorldView`, so it cannot predict the moves of a unit
## the searcher has never seen — the information gate applies to the future as well
## as to the present, which is the whole reason the search goes through the view.
func test_it_cannot_predict_an_enemy_it_has_never_seen() -> void:
	var bout: Dictionary = _field()
	# Sealed away entirely: no sight, and an Elite unit's memory holds nothing
	# because `record_sightings` was never called for it.
	(bout.prey as Unit).cell = Vector2i(23, 15)
	var walled: Grid = bout.grid
	for y in range(0, 16):
		if not walled.blockers.has(Vector2i(21, y)):
			GridFixture.place_wall(walled, Vector2i(21, y))
	assert_eq(
		bout.view.units_visible_to(bout.hunter).size(),
		1,
		"sanity: the hunter sees only itself, or this asserts nothing"
	)

	var context: UtilityContext = UtilityContext.build(bout.hunter, bout.view)
	var threats: Dictionary = await UtilityLookahead.threat_map(context, context.candidate_cells)

	for cell: Vector2i in threats:
		assert_eq(float(threats[cell]), 0.0, "an unseen enemy cannot be predicted, at %s" % cell)


# --- the cost bound -----------------------------------------------------------


## **The bound is the reason this is shippable**, so it gets an assertion rather
## than a comment. One field per enemy for the cheap ply, plus at most `SHORTLIST`
## for the expensive one — and the candidate set here is far larger than the
## shortlist, so a missing cap would show up as hundreds.
func test_the_expensive_ply_is_capped_at_the_shortlist() -> void:
	var bout: Dictionary = _field()
	var context: UtilityContext = _context(bout)
	assert_gt(
		context.candidate_cells.size(),
		UtilityLookahead.SHORTLIST,
		"sanity: there are more candidates than the shortlist, or this proves nothing"
	)
	UtilityLookahead.reset_diagnostics()

	await UtilityLookahead.threat_map(context, context.candidate_cells)

	gut.p(
		(
			"%d fields for %d candidates (shortlist %d)"
			% [
				UtilityLookahead.fields_built,
				context.candidate_cells.size(),
				UtilityLookahead.SHORTLIST
			]
		)
	)
	assert_lte(UtilityLookahead.fields_built, 1 + UtilityLookahead.SHORTLIST)


## Determinism (`docs/00`): same board, same prediction, every time. A search whose
## shortlist came out of Dictionary iteration order would pass this only by luck,
## which is why the planner sorts before shortlisting.
func test_the_same_board_predicts_the_same_threats_twice() -> void:
	var first: Dictionary = _field()
	var second: Dictionary = _field()

	assert_eq(
		await UtilityLookahead.threat_map(_context(first), _context(first).candidate_cells),
		await UtilityLookahead.threat_map(_context(second), _context(second).candidate_cells)
	)


# --- does it change anything? -------------------------------------------------


## **`docs/11`'s named failure mode, applied to the lookahead.** A search that runs,
## produces a number, and moves no decision is worse than no search — it costs a
## whole extra scoring pass per Elite turn and every test above would still pass.
##
## So: plan the same board twice, once Elite and once Trained, and require the
## chosen cells to differ. The board is built so the difference has somewhere to
## show — an exposed lane that is the shortest way forward, and a shadow beside it.
func test_an_elite_unit_picks_different_ground_than_a_trained_one() -> void:
	var elite: Dictionary = _field(ELITE)
	var trained: Dictionary = _field(TRAINED)

	var elite_cells: Array[Vector2i] = await _planned_cells(elite)
	var trained_cells: Array[Vector2i] = await _planned_cells(trained)

	gut.p("ELITE   moves through %s" % [elite_cells])
	gut.p("TRAINED moves through %s" % [trained_cells])
	assert_ne(
		elite_cells, trained_cells, "the lookahead changed no decision — it is an expensive no-op"
	)


## The other half of that pair: **adding a capability to the top tier must not move
## the tiers below it.**
##
## `NO_PREDICTION` is 0.0 rather than a mid "unknown" precisely so the inverted
## consideration multiplies out to exactly 1.0 for anything that cannot search. If
## that ever drifts, every Trained and Grunt unit in the game quietly re-scores
## because of a feature they do not have, and nothing else would report it.
func test_the_lookahead_consideration_is_inert_below_elite() -> void:
	var bout: Dictionary = _field(TRAINED)
	var context: UtilityContext = _context(bout)
	var take_cover: UtilityActionDef = null
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if action.id == &"take_cover":
			take_cover = action
	assert_not_null(take_cover, "sanity: take_cover is authored")
	var threat_considerations: Array = take_cover.considerations.filter(
		func(c: ConsiderationDef) -> bool:
			return c.input_id == UtilityContext.INPUT_PREDICTED_THREAT
	)
	assert_eq(threat_considerations.size(), 1, "sanity: take_cover reads the prediction at all")

	for cell: Vector2i in context.candidate_cells:
		assert_eq(
			context.predicted_threat(cell),
			UtilityContext.NO_PREDICTION,
			"a Trained unit must have no prediction at %s" % cell
		)
	var curve: ResponseCurve = (threat_considerations[0] as ConsiderationDef).curve
	assert_almost_eq(
		curve.apply(UtilityContext.NO_PREDICTION),
		1.0,
		0.0001,
		"and no prediction must multiply out to exactly no opinion"
	)


## Every cell the plan actually routes the unit through, in order.
func _planned_cells(bout: Dictionary) -> Array[Vector2i]:
	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, bout.view, null, &"cautious"
	)
	var cells: Array[Vector2i] = []
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			var path: Array[Vector2i] = (action as MoveAction).path
			if not path.is_empty():
				cells.append(path[path.size() - 1])
	return cells
