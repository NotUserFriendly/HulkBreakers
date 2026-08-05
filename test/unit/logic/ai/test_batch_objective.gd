extends GutTest

## taskblock-45 Pass C: the batch objective, built dormant.
##
## **The supervisor's requirement is that this stands up on its own the moment
## bouts assign batches** — not that it is wired into play now. Automatic
## assignment is explicitly not this block's job, so every unit in an ordinary bout
## is `batch_id == 0` and none of this runs. That makes the dormancy the load-
## bearing claim rather than an afterthought, and it is asserted directly.
##
## **Standing rule 5 is a constraint here, not a goal.** The leader acts, then each
## follower, each on their own turn in initiative order. The objective is computed
## once per batch per round and reused; nothing in this file resolves two units
## together, and a test that made it faster by doing so would be wrong regardless
## of how much time it saved.

const AGGRESSIVE_PROFILE := &"aggressive"
const CAUTIOUS_PROFILE := &"cautious"

# --- fixtures ----------------------------------------------------------------


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


## A leader, one follower and an enemy — the smallest board on which "the objective
## flows from one unit to another" is a real question.
func _squad(grid: Grid) -> Dictionary:
	var leader: Unit = _armed_unit(&"leader", Vector2i(3, 8), 0)
	var follower: Unit = _armed_unit(&"follower", Vector2i(3, 10), 0)
	var enemy: Unit = _armed_unit(&"enemy", Vector2i(17, 8), 1)
	var state := CombatState.new(grid, [leader, follower, enemy])
	state.force_current_unit(leader.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
		# taskblock-46 Pass E: **setting** a batch objective is Elite-only, where
		# reading one is Trained-and-above. These units lead, so they have to be the
		# tier that may lead — a Trained batch is a real configuration, it just has
		# nobody in it who makes the call, which is what the two Mindless tests below
		# assert from the other side.
		unit.intelligence_tier = &"ELITE"
	return {"state": state, "leader": leader, "follower": follower, "enemy": enemy}


## Ordinary cover: a blocker that stops a SHOT without stopping SIGHT — otherwise the enemy is
## hidden from a restricted view entirely and there is nothing left to plan against.
##
## **taskblock-58 Pass C changed what that takes.** This used to place a full `wall` Part and rely
## on leaving `Grid.opacity` alone, because sight was a flat array that cover was never flagged
## in. Sight is geometry now, and a `wall` box is 2.4 tall — it blocks, correctly. So cover has to
## be cover: a crate you can genuinely see over, deliberately shorter than `LoS.SIGHT_HEIGHT`.
## The fixture states the geometry it needs rather than depending on a flag nobody set.
func _place_cover(grid: Grid, cell: Vector2i) -> void:
	GridFixture.place_floor(grid, cell)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 20
	crate.max_hp = 20
	crate.material = &"steel"
	var top: float = LoS.SIGHT_HEIGHT * 0.6
	crate.volume = [Box.new(Vector3(0.0, top * 0.5, 0.0), Vector3(1.0, top, 1.0))]
	grid.blockers[cell] = crate


func _restricted_view(state: CombatState) -> WorldView:
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	return view


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


# --- dormancy is the claim ----------------------------------------------------


## With every unit independent, nothing is recorded, nothing is read, and the
## objective vector is uniformly neutral — so the mechanism is genuinely inert
## rather than merely quiet.
func test_with_no_batch_assigned_no_objective_is_ever_recorded() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	for unit: Unit in bout.state.units:
		assert_eq(unit.batch_id, 0, "sanity: an ordinary bout assigns no batches")

	await UtilityPlanner.plan_turn(
		bout.leader, _restricted_view(bout.state), null, AGGRESSIVE_PROFILE
	)

	assert_eq(
		bout.state.batch_plans.objective_for(0, bout.state.round_number),
		BatchPlan.NO_OBJECTIVE,
		"an independent unit leads nothing and records nothing"
	)


## The neutral vector is all-ones, never all-zeros. A zero would veto through the
## product and every batchless unit — which is every unit in play today — would
## stop acting entirely. This is the single most consequential detail of the
## dormant design.
func test_a_dormant_objective_vector_is_neutral_rather_than_vetoing() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	var context: UtilityContext = UtilityContext.build(bout.leader, _restricted_view(bout.state))

	var inputs: Dictionary = context.inputs_for(bout.leader.cell)

	var seen := 0
	for objective: UtilityActionDef in DataLibrary.batch_objectives_pool():
		var input_id: StringName = BatchObjective.input_id_for(objective.id)
		assert_true(inputs.has(input_id), "%s is published" % input_id)
		assert_eq(float(inputs[input_id]), 1.0, "%s is neutral while dormant" % input_id)
		seen += 1
	assert_gt(seen, 0, "sanity: there are objectives to be neutral about")


# --- assigning a batch makes the objective flow -------------------------------


## The pass's own "stands up on its own" test: the ONLY thing that changes is the
## `set_batch` verb, and the objective reaches the follower.
func test_assigning_a_batch_through_the_injector_flows_an_objective() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	var injector := BoutInjector.new(bout.state)
	injector.set_batch(bout.leader, 1)
	injector.set_batch(bout.follower, 1)
	var view: WorldView = _restricted_view(bout.state)

	await UtilityPlanner.plan_turn(bout.leader, view, null, AGGRESSIVE_PROFILE)

	var objective: StringName = bout.state.batch_plans.objective_for(1, view.round_number)
	gut.p("leader chose objective: %s" % objective)
	assert_ne(objective, BatchPlan.NO_OBJECTIVE, "the leader made a call for the batch")
	assert_eq(
		bout.state.batch_plans.leader_id_for(1, view.round_number),
		bout.leader.id,
		"and the first member to act is the one who made it"
	)
	assert_eq(
		view.batch_plan_for(bout.follower).get("objective"),
		objective,
		"which is exactly what the follower reads"
	)


## Leadership is derived from acting first, so a follower can never redirect the
## batch it belongs to mid-manoeuvre.
func test_a_follower_cannot_overwrite_the_objective_it_was_given() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	for unit: Unit in [bout.leader, bout.follower]:
		unit.batch_id = 1
	var view: WorldView = _restricted_view(bout.state)

	await UtilityPlanner.plan_turn(bout.leader, view, null, AGGRESSIVE_PROFILE)
	var chosen: StringName = bout.state.batch_plans.objective_for(1, view.round_number)
	bout.state.force_current_unit(bout.follower.id)
	await UtilityPlanner.plan_turn(bout.follower, view, null, CAUTIOUS_PROFILE)

	assert_eq(
		bout.state.batch_plans.objective_for(1, view.round_number),
		chosen,
		"the round's call stands even though the follower would have chosen otherwise"
	)


# --- a follower decides measurably differently under an objective -------------


## The whole point of injecting an objective as a consideration rather than as a
## destination: it changes what the follower WANTS, and the follower still decides
## its own turn.
##
## Driven by forcing the objective onto the record directly rather than by finding
## a board where the leader happens to pick each one — the claim under test is that
## a follower responds to the objective, not that a leader can be manoeuvred into
## choosing a particular one.
## **The winning ACTION per selection, not the queue shape.** Two different actions
## can legitimately land on the same cell — `approach` and `take_cover` both emit a
## `MoveAction`, and if the best covered cell is also the best closing cell the
## queues are identical while the decisions are not. Read off the decision log,
## which exists for exactly this question.
func _follower_decisions_under(objective: StringName) -> Array[String]:
	var grid: Grid = GridFixture.flat(24, 16)
	# Cover between the follower and the enemy, so `take_cover` is genuinely on
	# offer. Without it the withdraw objective has nothing to boost and the two
	# objectives are indistinguishable for the honest reason that the board offers
	# no way to act on one of them — which is what the first draft of this test
	# actually found.
	for y in range(9, 12):
		_place_cover(grid, Vector2i(10, y))
	var bout: Dictionary = _squad(grid)
	for unit: Unit in [bout.leader, bout.follower]:
		unit.batch_id = 1
	var view: WorldView = _restricted_view(bout.state)
	bout.state.batch_plans.record(1, view.round_number, bout.leader.id, bout.leader.cell, objective)
	bout.state.force_current_unit(bout.follower.id)
	var sink := MemorySink.new()
	bout.state.combat_log.add_sink(sink)
	await UtilityPlanner.plan_turn(bout.follower, view, null, CAUTIOUS_PROFILE)
	bout.state.combat_log.remove_sink(sink)

	var chosen: Array[String] = []
	for event: LogEvent in sink.events_of_kind(&"ai_utility_decision"):
		var index: int = int(event.data["winner_index"])
		if index < 0:
			continue
		chosen.append(str((event.data["candidates"] as Array)[index]["action_id"]))
	return chosen


func test_a_follower_decides_differently_with_and_without_an_objective() -> void:
	var plans: Dictionary = {}
	var objectives: Array[StringName] = [
		BatchPlan.NO_OBJECTIVE, &"advance", &"hold", &"withdraw", &"flank"
	]
	for objective: StringName in objectives:
		var plan: Array[String] = await _follower_decisions_under(objective)
		plans[objective] = plan
		gut.p("%-10s : %s" % [objective if objective != &"" else &"(none)", plan])

	var distinct: Array = []
	for objective: StringName in plans:
		if not distinct.has(plans[objective]):
			distinct.append(plans[objective])

	assert_gt(
		distinct.size(),
		1,
		"if every objective plans the identical turn, the whole mechanism is decoration"
	)


# --- the blackboard is tier-gated ---------------------------------------------


## A `MINDLESS` follower gets no objective and plans for itself. **That is correct
## behaviour, not a gap** — a unit that cannot use a team blackboard is not
## coordinated, and pretending otherwise would make the tier gap decorative.
func test_a_mindless_follower_ignores_the_blackboard() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	for unit: Unit in [bout.leader, bout.follower]:
		unit.batch_id = 1
	bout.follower.intelligence_tier = &"MINDLESS"
	var view: WorldView = _restricted_view(bout.state)
	bout.state.batch_plans.record(
		1, view.round_number, bout.leader.id, bout.leader.cell, &"withdraw"
	)

	assert_true(
		view.batch_plan_for(bout.follower).is_empty(),
		"it cannot read the objective the batch is under"
	)
	assert_false(view.has_blackboard(bout.follower))
	assert_true(view.has_blackboard(bout.leader), "and the gate is on the tier, not the batch")


## A `MINDLESS` unit acting first leaves the batch with no objective at all rather
## than setting one it could never read back — the same asymmetry `claim_batch_lead`
## already refuses.
func test_a_mindless_leader_leaves_the_batch_uncoordinated() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	for unit: Unit in [bout.leader, bout.follower]:
		unit.batch_id = 1
	bout.leader.intelligence_tier = &"MINDLESS"
	var view: WorldView = _restricted_view(bout.state)

	await UtilityPlanner.plan_turn(bout.leader, view, null, AGGRESSIVE_PROFILE)

	assert_eq(
		bout.state.batch_plans.objective_for(1, view.round_number),
		BatchPlan.NO_OBJECTIVE,
		"a squad led by something that cannot coordinate is not coordinated"
	)


# --- leader death -------------------------------------------------------------


## **Leadership is derived, so leader death costs no code.** The record is left
## untouched, followers finish the round on the objective they were given, and the
## next-fastest living member is simply first next round — no promotion logic, no
## staleness check, no field to keep in sync across a `dup()`.
func test_leader_death_leaves_followers_on_the_rounds_objective() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	for unit: Unit in [bout.leader, bout.follower]:
		unit.batch_id = 1
	var view: WorldView = _restricted_view(bout.state)

	await UtilityPlanner.plan_turn(bout.leader, view, null, AGGRESSIVE_PROFILE)
	var objective: StringName = bout.state.batch_plans.objective_for(1, view.round_number)
	assert_ne(objective, BatchPlan.NO_OBJECTIVE, "sanity: there was a call to inherit")

	bout.leader.alive = false

	assert_eq(
		view.batch_plan_for(bout.follower).get("objective"),
		objective,
		"the squad finishes the manoeuvre it was committed to"
	)


func test_the_next_round_is_led_by_whoever_acts_first() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	for unit: Unit in [bout.leader, bout.follower]:
		unit.batch_id = 1
	var view: WorldView = _restricted_view(bout.state)
	await UtilityPlanner.plan_turn(bout.leader, view, null, AGGRESSIVE_PROFILE)
	bout.leader.alive = false

	# A new round: the record has aged out by comparison, with no hook clearing it.
	view.round_number += 1
	bout.state.force_current_unit(bout.follower.id)
	await UtilityPlanner.plan_turn(bout.follower, view, null, CAUTIOUS_PROFILE)

	assert_eq(
		bout.state.batch_plans.leader_id_for(1, view.round_number),
		bout.follower.id,
		"the next-fastest living member leads, with no promotion code anywhere"
	)


# --- one objective per batch per round ---------------------------------------


## Standing rule 5's amortisation, asserted as a property: the expensive-ish coarse
## pass runs once per batch per round and every follower reuses the answer. Units
## still act one at a time — this is about the objective being computed once, never
## about resolving them together.
func test_the_objective_is_computed_once_and_reused() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var bout: Dictionary = _squad(grid)
	var third: Unit = _armed_unit(&"third", Vector2i(3, 12), 0)
	third.intelligence_tier = &"ELITE"
	third.ap = third.max_ap
	bout.state.units.append(third)
	for unit: Unit in [bout.leader, bout.follower, third]:
		unit.batch_id = 1
	var view: WorldView = _restricted_view(bout.state)

	await UtilityPlanner.plan_turn(bout.leader, view, null, AGGRESSIVE_PROFILE)
	var after_leader: StringName = bout.state.batch_plans.objective_for(1, view.round_number)
	bout.state.force_current_unit(bout.follower.id)
	await UtilityPlanner.plan_turn(bout.follower, view, null, CAUTIOUS_PROFILE)
	bout.state.force_current_unit(third.id)
	await UtilityPlanner.plan_turn(third, view, null, AGGRESSIVE_PROFILE)

	assert_eq(
		bout.state.batch_plans.objective_for(1, view.round_number),
		after_leader,
		"three turns, one call — the followers reused it rather than re-deciding"
	)


# --- the objective pool is data -----------------------------------------------


func test_the_four_objectives_are_authored_as_data() -> void:
	var ids: Array[StringName] = []
	for objective: UtilityActionDef in DataLibrary.batch_objectives_pool():
		ids.append(objective.id)

	assert_eq(ids, [&"advance", &"flank", &"hold", &"withdraw"] as Array[StringName])


## Each objective publishes its own input, derived from its id — so a fifth
## objective is a fifth `.tres` and the input every action can read appears with
## it, no code knowing the four names.
func test_the_input_vocabulary_is_derived_from_the_authored_ids() -> void:
	assert_eq(BatchObjective.input_id_for(&"advance"), &"objective_advance")
	assert_eq(BatchObjective.input_id_for(&"flank"), &"objective_flank")
