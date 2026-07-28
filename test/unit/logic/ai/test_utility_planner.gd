extends GutTest

## taskblock-45 Pass B: **the two tests at the top of this file matter more than
## the rest of it.**
##
## If `MINDLESS` and `TRAINED` produce identical play, the information gating is
## decorative and Passes C–E are built on nothing. If the two profiles produce
## identical play, the same is true on the other axis. Everything else here — the
## preconditions, the flag, the log — is checking that a working thing works;
## those two are checking that there is a thing at all. They are written first
## deliberately.
##
## **The substituted test.** taskblock-45 Pass B's own third bullet asked for a
## `MINDLESS` unit acting on a remembered position that is now wrong. That is not
## writable against the tier the supervisor actually chose: `MINDLESS` is strictly
## current-sight-only (`WorldView.MEMORY_TIERS`), so it has no remembered position
## to be wrong about. The equivalent claim for this tier — it stops planning
## against an enemy the instant line of sight breaks, while `TRAINED` keeps
## engaging — is tested instead, and the unmet bullet is flagged rather than
## quietly dropped. Chasing a stale sighting is Grunt's behaviour and arrives with
## `PLAN.md`'s *fill in the tier table*.

const AGGRESSIVE_PROFILE := &"aggressive"
const CAUTIOUS_PROFILE := &"cautious"


func before_each() -> void:
	UtilityPlanner.candidates_scored = 0
	UtilityPlanner.empty_decisions = 0


# --- fixtures ----------------------------------------------------------------


## An armed humanoid with a real weapon part, a real manipulator and a real
## `WeaponDef` — the same shape `test_world_view_seam.gd` builds, because a unit
## whose weapon is not genuinely operable never offers `shoot` at all and every
## assertion below would pass for the wrong reason.
func _armed_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 30.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


func _duel(grid: Grid, hunter_cell: Vector2i, prey_cell: Vector2i) -> Dictionary:
	var hunter: Unit = _armed_unit(&"hunter", hunter_cell, 0)
	var prey: Unit = _armed_unit(&"prey", prey_cell, 1)
	var state := CombatState.new(grid, [hunter, prey])
	state.force_current_unit(hunter.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	return {"state": state, "hunter": hunter, "prey": prey}


## A restricted view — the one the utility planner actually runs against.
func _restricted_view(state: CombatState) -> WorldView:
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	return view


## A compact, readable rendering of a queue, so a failure says WHAT the planner
## decided rather than only that two arrays differed. CC cannot watch the game, so
## a decision that is only visible as an inequality is a decision nobody can debug
## (CLAUDE.md).
func _shape(queue: ActionQueue) -> Array[String]:
	var shape: Array[String] = []
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			var move: MoveAction = action
			var end: Vector2i = move.path[move.path.size() - 1]
			shape.append("move->(%d,%d)" % [end.x, end.y])
		else:
			shape.append(action.get_script().get_global_name())
	return shape


# --- 1. the two tiers decide differently -------------------------------------


## **The load-bearing test of the whole block.** A wall splits the board, the team
## has a fresh sighting of the enemy behind it, and the only difference between the
## two runs is one `StringName`.
##
## `TRAINED` reads the sighting and plans against it. `MINDLESS` does not read it,
## so as far as that unit is concerned the board is empty and there is nothing to
## plan against — which is a real decision, not an error, and is exactly the
## "plausible-but-wrong given a degraded world model" behaviour the tier exists to
## produce.
##
## **The assertion on `TRAINED` is deliberately "it does something", not "it moves".**
## It moved when the pool was four combat actions and it holds overwatch now that
## overwatch is in the pool — both are it acting on knowledge `MINDLESS` does not
## have, which is the claim. Pinning the specific action would pin the pool's
## contents, and this test would then fail every time a `.tres` is added, which is
## exactly the change it should be indifferent to.
func test_the_two_tiers_decide_differently_on_the_same_board() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(11, y))
	var trained_bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(20, 8))
	var trained_view: WorldView = _restricted_view(trained_bout.state)
	trained_bout.hunter.intelligence_tier = &"TRAINED"
	trained_view.remembered[trained_bout.prey.id] = {
		"cell": trained_bout.prey.cell, "round_seen": trained_view.round_number
	}

	var mindless_bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(20, 8))
	var mindless_view: WorldView = _restricted_view(mindless_bout.state)
	mindless_bout.hunter.intelligence_tier = &"MINDLESS"
	mindless_view.remembered[mindless_bout.prey.id] = {
		"cell": mindless_bout.prey.cell, "round_seen": mindless_view.round_number
	}

	var trained: ActionQueue = await UtilityPlanner.plan_turn(
		trained_bout.hunter, trained_view, null, CAUTIOUS_PROFILE
	)
	var mindless: ActionQueue = await UtilityPlanner.plan_turn(
		mindless_bout.hunter, mindless_view, null, CAUTIOUS_PROFILE
	)

	gut.p("TRAINED  : %s" % [_shape(trained)])
	gut.p("MINDLESS : %s" % [_shape(mindless)])

	assert_ne(
		_shape(mindless),
		_shape(trained),
		"if the tiers plan the same turn, the information gating is decorative"
	)
	assert_ne(
		_shape(trained),
		["EndTurnAction"] as Array[String],
		"TRAINED acts on the sighting it is entitled to"
	)
	# taskblock-46 Pass C: this used to assert `["EndTurnAction"]` — a blind unit was
	# offered nothing and idled, which was `BR45.03`'s hole. It now searches. The
	# tier claim is unchanged and sharper: TRAINED acts on knowledge MINDLESS does
	# not have, while MINDLESS goes looking.
	assert_true(
		_shape(mindless).any(func(step: String) -> bool: return step.begins_with("move")),
		"MINDLESS searches rather than idling"
	)
	assert_does_not_have(
		_shape(mindless),
		"AttackAction",
		"but it has nothing to shoot at, because it knows of nobody"
	)


## The gate is on the TIER, not on the restriction flag — otherwise "restricted"
## and "mindless" would be the same switch and the tier table could never have a
## middle.
func test_the_same_mindless_unit_engages_once_it_can_actually_see() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(20, 8))
	bout.hunter.intelligence_tier = &"MINDLESS"

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, _restricted_view(bout.state), null, AGGRESSIVE_PROFILE
	)

	gut.p("MINDLESS with line of sight: %s" % [_shape(queue)])
	assert_gt(queue.actions.size(), 1, "with the enemy in plain sight it plans a real turn")


# --- 2. the two profiles decide differently ----------------------------------


## The other anti-vacuity test, with tier held constant. Same board, same seed,
## same tier — only the weight vector differs, and it has to change the play.
##
## Both are `TRAINED` and both can see the enemy; the aggressive weights close the
## distance and the cautious ones would rather shoot from where they stand than
## walk into the open.
func test_the_two_profiles_decide_differently_with_tier_held_constant() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var aggressive_bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	var cautious_bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	aggressive_bout.hunter.intelligence_tier = &"TRAINED"
	cautious_bout.hunter.intelligence_tier = &"TRAINED"

	var aggressive: ActionQueue = await UtilityPlanner.plan_turn(
		aggressive_bout.hunter, _restricted_view(aggressive_bout.state), null, AGGRESSIVE_PROFILE
	)
	var cautious: ActionQueue = await UtilityPlanner.plan_turn(
		cautious_bout.hunter, _restricted_view(cautious_bout.state), null, CAUTIOUS_PROFILE
	)

	gut.p("aggressive : %s" % [_shape(aggressive)])
	gut.p("cautious   : %s" % [_shape(cautious)])

	assert_ne(
		_shape(cautious),
		_shape(aggressive),
		"if the profiles plan the same turn, they are decoration on one behaviour"
	)


## A profile is a weight vector, never a code path — so an unknown profile id is a
## fully neutral one rather than an error, and still plans a real turn.
func test_an_unknown_profile_id_plans_neutrally_rather_than_failing() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, _restricted_view(bout.state), null, &"no_such_profile"
	)

	assert_gt(queue.actions.size(), 1, "a neutral profile is still a profile")


# --- 3. losing sight (the substituted bullet) --------------------------------


## The supervisor's chosen `MINDLESS` degradation, stated as behaviour: an enemy
## that breaks line of sight stops existing for this tier, while `TRAINED` keeps
## engaging the sighting it recorded a moment earlier.
##
## Both units see the enemy on the first turn, so both record what they are
## entitled to record — `MINDLESS` records nothing, which is the point.
func test_a_mindless_unit_forgets_an_enemy_that_breaks_line_of_sight() -> void:
	var open_grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(open_grid, Vector2i(2, 8), Vector2i(20, 8))
	bout.hunter.intelligence_tier = &"MINDLESS"
	var view: WorldView = _restricted_view(bout.state)

	# Turn one: in plain sight. Whatever it records, it records now.
	await UtilityPlanner.plan_turn(bout.hunter, view, null, AGGRESSIVE_PROFILE)
	assert_true(view.remembered.is_empty(), "a tier with no memory writes none either")

	# The enemy steps behind a wall.
	for y in range(open_grid.rows):
		GridFixture.place_wall(open_grid, Vector2i(11, y))
	bout.hunter.ap = bout.hunter.max_ap

	var blind_turn: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, view, null, AGGRESSIVE_PROFILE
	)

	# taskblock-46 Pass C: out of sight is still out of mind — it just searches now
	# instead of standing still. What matters for the tier is that it is no longer
	# ENGAGING: nothing it does is aimed at an enemy it cannot know about.
	assert_does_not_have(
		_shape(blind_turn),
		"AttackAction",
		"out of sight is out of mind, which is the whole tier"
	)


func test_a_trained_unit_keeps_engaging_the_sighting_it_recorded() -> void:
	var open_grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(open_grid, Vector2i(2, 8), Vector2i(20, 8))
	bout.hunter.intelligence_tier = &"TRAINED"
	var view: WorldView = _restricted_view(bout.state)

	await UtilityPlanner.plan_turn(bout.hunter, view, null, AGGRESSIVE_PROFILE)
	assert_false(view.remembered.is_empty(), "it wrote down what it saw")

	for y in range(open_grid.rows):
		GridFixture.place_wall(open_grid, Vector2i(11, y))
	bout.hunter.ap = bout.hunter.max_ap

	var blind_turn: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, view, null, AGGRESSIVE_PROFILE
	)

	gut.p("TRAINED, sight broken: %s" % [_shape(blind_turn)])
	assert_gt(blind_turn.actions.size(), 1, "it still acts on the position it remembers")


# --- 4. preconditions genuinely gate ------------------------------------------


## An action whose preconditions cannot hold must never be selected — otherwise
## the precondition list is documentation rather than a gate, and the decision log
## cannot tell "not offered" from "offered and scored zero".
func test_an_action_with_an_unsatisfiable_precondition_is_never_selected() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	var context: UtilityContext = UtilityContext.build(bout.hunter, _restricted_view(bout.state))
	var impossible := UtilityActionDef.new(&"impossible", &"shoot")
	impossible.preconditions = [&"a_predicate_nothing_publishes"]

	for cell: Vector2i in context.candidate_cells:
		assert_false(
			UtilityScorer.preconditions_hold(impossible, context.predicates_for(cell)),
			"an unpublished predicate reads false, so the action is never offered"
		)


## Each of the four authored actions is gated by something real. Asserted against
## the shipped `.tres` files rather than a fixture, because the claim is about the
## pool the game actually runs.
func test_every_authored_action_declares_at_least_one_precondition() -> void:
	var pool: Array[UtilityActionDef] = DataLibrary.utility_actions_pool()

	# The pool has grown past Pass B's deliberate four: the mission actions (a
	# combat-only pool completed 0% of bouts), overwatch, and taskblock-46's four
	# search verbs (a unit matching no gate was offered nothing at all). The count is
	# asserted so a `.tres` going missing is loud, not because any number was ever
	# the target.
	assert_eq(pool.size(), 12, "the authored pool is twelve rows")
	for action: UtilityActionDef in pool:
		assert_false(
			action.preconditions.is_empty(), "%s must state when it is even possible" % action.id
		)
		assert_false(action.considerations.is_empty(), "%s must state what it wants" % action.id)


## `hold_position` is gated on there being someone to defer to, which is
## `HoldAction`'s own legality requirement — published as a precondition so a hold
## that could never be enqueued is never even offered.
func test_hold_is_not_offered_when_there_is_nobody_to_defer_to() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var lone: Unit = _armed_unit(&"lone", Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [lone])
	state.force_current_unit(lone.id)
	lone.ap = lone.max_ap

	var context: UtilityContext = UtilityContext.build(lone, _restricted_view(state))

	assert_false(
		bool(context.predicates_for(lone.cell)[UtilityContext.PRED_CAN_DEFER_TURN]),
		"a unit alone on the board has no next ally to hold for"
	)


# --- 5. the flag off changes nothing ------------------------------------------


func _action_sequence(state: CombatState, mission: MissionState, steps: int) -> Array[String]:
	var runner := BoutRunner.new(state, mission)
	var taken: Array[String] = []
	var i := 0
	while not runner.finished and i < steps:
		await runner.step()
		for event: LogEvent in runner.last_events:
			taken.append("%s@%d" % [event.kind, event.unit_id])
		i += 1
	return taken


func _bout(map_seed: int) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.presets_pool()[i % DataLibrary.presets_pool().size()]
		roster.append(entry)
	return BoutSetup.build_bout(roster, roster, map_seed)


## Pass B shipped the planner switched off and this asserted the flag-off path was
## byte-identical to the engagement-score planner. **Pass D flipped the default and
## Pass E deleted the alternative, so that claim no longer has two sides.** What
## survives, and is worth more, is the property underneath it: a seeded bout is
## reproducible. Same seed, same map, same event stream, twice.
func test_a_seeded_bout_is_reproducible() -> void:
	var a: Dictionary = _bout(31337)
	assert_eq(a.get("error", ""), "", "sanity: the bout built")
	var expected: Array[String] = await _action_sequence(a.state, a.mission, 8)

	var b: Dictionary = _bout(31337)
	var actual: Array[String] = await _action_sequence(b.state, b.mission, 8)

	assert_eq(actual, expected)
	assert_gt(expected.size(), 0, "sanity: the bout actually did something")


## `AiPlanner` is the one seam every AI turn is planned through, so "it actually
## routes" is asserted directly rather than inferred from a bout looking different.
func test_the_seam_routes_to_the_utility_planner() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))

	await AiPlanner.plan_turn(bout.hunter, WorldView.full(bout.state), null, &"AGGRESSIVE")

	assert_gt(UtilityPlanner.candidates_scored, 0, "the utility scorer did the deciding")


## The seam restricts the view itself, once, for everyone — so "did this caller
## remember to set the flag" is not a thing anyone has to know. `BoutRunner` hands
## in an unrestricted view and the tier gating applies regardless.
func test_the_seam_restricts_the_world_view_itself() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	var view: WorldView = WorldView.full(bout.state)
	assert_false(view.restricted, "sanity: it starts unrestricted")

	await AiPlanner.plan_turn(bout.hunter, view, null, &"AGGRESSIVE")

	assert_true(view.restricted)


func test_the_playstyle_bridge_maps_onto_the_authored_profiles() -> void:
	var authored: Array[StringName] = []
	for profile: UtilityProfile in DataLibrary.utility_profiles_pool():
		authored.append(profile.id)

	for playstyle: StringName in AiPlanner.PLAYSTYLES:
		assert_has(
			authored,
			AiPlanner.profile_id_for(playstyle),
			"%s maps onto a profile that actually exists" % playstyle
		)


# --- the decision log, and determinism ---------------------------------------


## Pass A designed the log in; this is the first pass that produces one from a real
## turn. A decision nobody can reconstruct is the hole BR26.02 sat in for three
## passes.
func test_a_planned_turn_emits_a_reconstructable_decision() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	var sink := MemorySink.new()
	bout.state.combat_log.add_sink(sink)

	await UtilityPlanner.plan_turn(
		bout.hunter, _restricted_view(bout.state), null, AGGRESSIVE_PROFILE
	)
	bout.state.combat_log.remove_sink(sink)

	var decisions: Array[LogEvent] = sink.events_of_kind(&"ai_utility_decision")
	assert_gt(decisions.size(), 0, "the turn recorded what it decided")
	var first: LogEvent = decisions[0]
	assert_gt((first.data["candidates"] as Array).size(), 0, "and against what")
	assert_eq(first.data["tier"], bout.hunter.intelligence_tier)
	assert_eq(first.data["profile"], AGGRESSIVE_PROFILE)

	var winner_index: int = int(first.data["winner_index"])
	assert_gt(winner_index, -1, "sanity: it chose something")
	var winner: Dictionary = (first.data["candidates"] as Array)[winner_index]
	var rebuilt: float = 1.0
	for entry: Dictionary in winner["trace"] as Array:
		rebuilt *= float(entry["compensated"])
	assert_gt(rebuilt, 0.0, "the trace alone carries the arithmetic")


## Same board, same profile, same tier — same queue, every time. The planner is a
## pure function of what it was handed (`docs/00`: same seed = same battle).
func test_planning_the_same_turn_twice_produces_the_same_queue() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var first: Array[String] = []

	for run in range(3):
		var bout: Dictionary = _duel(grid, Vector2i(3, 6), Vector2i(17, 9))
		var queue: ActionQueue = await UtilityPlanner.plan_turn(
			bout.hunter, _restricted_view(bout.state), null, CAUTIOUS_PROFILE
		)
		if run == 0:
			first = _shape(queue)
		else:
			assert_eq(_shape(queue), first, "run %d agreed" % run)


# --- resumability -------------------------------------------------------------


## Built resumable from the first line, because it cannot be retrofitted: a
## conditional `await` is a parse error in GDScript, so "make it resumable later"
## means converting the whole call chain again (measured in taskblock-44 Pass D,
## not assumed).
func test_the_candidate_loop_yields_to_a_watching_pacer() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	var pacer := PlanPacer.new()
	pacer.chunk = 2
	pacer.frame_signal = get_tree().process_frame

	await UtilityPlanner.plan_turn(
		bout.hunter, _restricted_view(bout.state), null, AGGRESSIVE_PROFILE, pacer
	)

	assert_gt(pacer.yields, 0, "the plan actually suspended rather than running through")


## The budget is what makes a visible "thinking…" label honest — past it the scan
## stops where it is and the unit acts on the best candidate it had found.
## Aborting is safe at any iteration because candidates are only ever appended.
func test_an_aborted_scan_still_produces_a_legal_turn() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))
	var pacer := PlanPacer.new()
	pacer.budget_msec = 0
	pacer.frame_signal = get_tree().process_frame

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, _restricted_view(bout.state), null, AGGRESSIVE_PROFILE, pacer
	)

	assert_true(pacer.aborted, "sanity: the budget really did run out")
	assert_gt(queue.actions.size(), 0, "and the turn still ends rather than hanging")


## **The claim the `repeatable` data field makes**: how many shots a turn holds is
## decided by the AP economy, not by a planner constant. `MAX_SELECTIONS` sits
## above the AP ceiling precisely so this is observable — if the cap were the
## binding limit, raising it would produce more shots, and it does not.
func test_the_shot_count_is_decided_by_ap_not_by_the_selection_cap() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(7, 8))
	var gun: Part = bout.hunter.shell.find_part(&"hunter_gun")

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.hunter, _restricted_view(bout.state), null, CAUTIOUS_PROFILE
	)

	var shots := 0
	for action: CombatAction in queue.actions:
		if action is AttackAction:
			shots += 1
	var affordable: int = bout.hunter.max_ap / gun.ap_cost
	gut.p("%d shots against %d AP at %d each" % [shots, bout.hunter.max_ap, gun.ap_cost])
	assert_eq(shots, affordable, "it spends the AP it has, and stops when it runs out")
	assert_lt(shots, UtilityPlanner.MAX_SELECTIONS, "the cap is a backstop, not the rule")


# --- the cost claim -----------------------------------------------------------


## The block's whole reason for existing: the per-candidate `ShotPlane` cast is
## gone. One `VisibilityField` is built per target per turn and every candidate's
## line-of-fire question is a bit test against it.
##
## Asserted as "the field exists and answers", not as a timing — a wall-clock
## assertion in a unit test measures the machine, and Pass D's bench is where the
## real number belongs.
func test_line_of_fire_is_answered_from_one_field_not_a_cast_per_candidate() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	# A wall with a gap on the firing row: the enemy stays directly visible (so
	# there IS a target to build a field for) while most cells off that row are
	# genuinely ruled out. A wall straight across would leave nothing to plan
	# against at all under a restricted view, and the test would pass on the
	# emptiness rather than on the field.
	for y in range(4, 12):
		if y == 8:
			continue
		GridFixture.place_wall(grid, Vector2i(9, y))
	var bout: Dictionary = _duel(grid, Vector2i(2, 8), Vector2i(16, 8))

	var context: UtilityContext = UtilityContext.build(bout.hunter, _restricted_view(bout.state))

	assert_not_null(context.field, "one field, built once for this target")
	var blocked := 0
	var open := 0
	for cell: Vector2i in context.candidate_cells:
		if float(context.inputs_for(cell)[UtilityContext.INPUT_LINE_OF_FIRE]) > 0.0:
			open += 1
		else:
			blocked += 1
	gut.p("candidates: %d with a possible line, %d without" % [open, blocked])
	assert_gt(blocked, 0, "the wall genuinely rules cells out")


# --- BR32.10: concave geometry ------------------------------------------------


## **The bug stated as behaviour, not as a distance metric.** A unit tucked inside a
## U-shaped pocket, target outside the opening: the cell closest as the crow flies
## is on the wrong side of the wall, so a scorer reading straight-line distance
## walks into that wall and stays there every turn.
##
## Asserted as "it ends up somewhere with a line to its target" rather than "it
## picked cell X" — the route around a pocket is a property of the map, and pinning
## a cell would pin one map's answer instead of the behaviour.
##
## The retired planner had a Dijkstra-to-a-cell-with-a-line branch for this;
## taskblock-46 deleted it, because being stuck became a scoring outcome rather
## than a branch that failed to fire, and the fix belongs in the score
## (`UtilityContext._closes_distance` reads path distance).
func test_a_unit_in_a_concave_pocket_works_its_way_to_a_cell_with_a_line() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	# A pocket opening downward: walls above, left and right of the hunter.
	for x in range(6, 13):
		GridFixture.place_wall(grid, Vector2i(x, 5))
	for y in range(5, 9):
		GridFixture.place_wall(grid, Vector2i(6, y))
		GridFixture.place_wall(grid, Vector2i(12, y))
	var bout: Dictionary = _duel(grid, Vector2i(9, 6), Vector2i(9, 2))
	var hunter: Unit = bout.hunter
	var prey: Unit = bout.prey
	var view: WorldView = _restricted_view(bout.state)
	# It knows where the enemy is; the question is whether it can get to it.
	view.remembered[prey.id] = {"cell": prey.cell, "round_seen": view.round_number}
	hunter.intelligence_tier = &"TRAINED"

	var reached_a_firing_cell := false
	var visited: Array[Vector2i] = [hunter.cell]
	for turn in range(12):
		hunter.ap = hunter.max_ap
		bout.state.force_current_unit(hunter.id)
		var queue: ActionQueue = await UtilityPlanner.plan_turn(
			hunter, view, null, AGGRESSIVE_PROFILE
		)
		bout.state.resolve_until(queue)
		visited.append(hunter.cell)
		if LineOfFire.has_clear_line_of_fire(hunter, prey, hunter.cell, bout.state):
			reached_a_firing_cell = true
			break

	gut.p("path out of the pocket: %s" % [visited])
	assert_true(
		reached_a_firing_cell,
		"it never found a cell with a line — straight-line scoring walks into the wall"
	)


## The mechanism underneath it, asserted directly so a regression says WHY. A cell
## on the far side of a wall is nearer as the crow flies and further along a path,
## and the input the scorer reads must report the second.
func test_closes_distance_reads_path_distance_not_straight_line() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	for y in range(0, 12):
		GridFixture.place_wall(grid, Vector2i(11, y))
	var bout: Dictionary = _duel(grid, Vector2i(9, 6), Vector2i(13, 6))
	var view: WorldView = _restricted_view(bout.state)
	# The wall blocks sight, so without a remembered sighting there is no target and
	# no distance input at all — the enemy has to be KNOWN for the question to exist.
	view.remembered[bout.prey.id] = {"cell": bout.prey.cell, "round_seen": view.round_number}
	var context: UtilityContext = UtilityContext.build(bout.hunter, view)

	# Hard against the wall: two cells from the target in a straight line, but the
	# only route is the long way round the wall's end.
	var against_the_wall := Vector2i(10, 6)
	# Backing off along the open route the unit must actually take.
	var toward_the_opening := Vector2i(9, 11)

	var wall_score: float = float(
		context.inputs_for(against_the_wall)[UtilityContext.INPUT_CLOSES_DISTANCE]
	)
	var opening_score: float = float(
		context.inputs_for(toward_the_opening)[UtilityContext.INPUT_CLOSES_DISTANCE]
	)
	gut.p("against the wall %.3f vs toward the opening %.3f" % [wall_score, opening_score])

	assert_lt(
		Grid.distance_chebyshev(against_the_wall, bout.prey.cell),
		Grid.distance_chebyshev(toward_the_opening, bout.prey.cell),
		"sanity: the wall cell IS nearer as the crow flies, which is the trap"
	)
	assert_gt(
		opening_score,
		wall_score,
		"but the route around must score higher, or the unit walks into the wall"
	)
