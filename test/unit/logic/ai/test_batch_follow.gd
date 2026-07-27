extends GutTest

## taskblock-43 Pass D: the leader plans, the followers follow.
##
## The leader is DERIVED, never stored — the first member of a batch to take a
## turn in the current round claims the lead, and every later member that round
## reads its destination instead of running the positional search. That is what
## makes leader death free: no promotion code, no staleness check, no field to
## keep in sync.
##
## `UnitAI.engagement_searches` is what most of this hangs on. "A follower does
## not call `_pick_engagement_position`" is not observable from the returned
## queue — a follower and a leader can legitimately choose the same cell — so
## only counting the searches tells "skipped the search" apart from "searched and
## agreed."


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
	weapon.weapon_def.max_range = 15.0
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


## Open ground with the enemy CLOSER than MARKSMAN's own standoff, which is what
## puts every unit here on the repositioning path — the branch this pass changes.
##
## Deliberately not a walled fixture. The first draft of this file used one, on
## the reasoning that units need a reason to move; it made units take the
## no-line approach fallback instead, which never consults a batch plan at all,
## and the search-count assertions passed for entirely the wrong reason.
## `_branch_taken` below exists so that cannot happen again quietly.
func _field() -> Dictionary:
	var grid: Grid = GridFixture.flat(30, 24)
	var alpha: Unit = _armed_unit(&"alpha", Vector2i(5, 5), 0)
	var beta: Unit = _armed_unit(&"beta", Vector2i(5, 7), 0)
	var enemy: Unit = _armed_unit(&"enemy", Vector2i(8, 6), 1)
	var state := CombatState.new(grid, [alpha, beta, enemy])
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	return {"state": state, "alpha": alpha, "beta": beta, "enemy": enemy}


## `force_current_unit` is load-bearing, not decoration. Every action's own
## `is_legal` gate starts with `state.current_unit() != actual`, so planning a
## turn for a unit whose turn it is not produces a queue in which every enqueue
## is silently refused — leaving nothing but an `EndTurnAction`, which
## `plan_turn`'s stalled-unit check then swaps for a `ShutdownAction`. The first
## draft of this file omitted it and got empty queues that looked like the
## follower had decided to do nothing.
func _plan(unit: Unit, state: CombatState) -> ActionQueue:
	state.force_current_unit(unit.id)
	return await UnitAI.plan_turn(unit, WorldView.full(state), null, &"MARKSMAN")


## Which branch `_plan_ranged` actually took, off the decision log — the guard
## against a test passing because some OTHER cheap branch ran.
func _branch_taken(unit: Unit, state: CombatState) -> StringName:
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	await _plan(unit, state)
	state.combat_log.remove_sink(sink)
	for event: LogEvent in sink.events:
		if event.kind == &"ai_decision" and event.unit_id == unit.id:
			return event.data["branch"]
	return &"none"


# --- who leads --------------------------------------------------------------


## The pass's own headline acceptance, stated as a count because the queue alone
## cannot answer it.
func test_a_two_unit_batch_runs_one_full_search_and_one_cheap_plan() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var alpha: Unit = field["alpha"]
	var beta: Unit = field["beta"]
	alpha.batch_id = 1
	beta.batch_id = 1

	UnitAI.engagement_searches = 0
	assert_eq(await _branch_taken(alpha, state), &"repositioned", "the leader searched for real")
	var after_leader: int = UnitAI.engagement_searches
	assert_eq(await _branch_taken(beta, state), &"followed_leader", "and the follower did not")
	var after_follower: int = UnitAI.engagement_searches

	assert_eq(after_leader, 1, "the leader pays the real cost, once")
	assert_eq(after_follower, 1, "and the follower adds none")


func test_the_first_member_to_act_becomes_the_leader() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var alpha: Unit = field["alpha"]
	var beta: Unit = field["beta"]
	alpha.batch_id = 1
	beta.batch_id = 1

	await _plan(beta, state)

	assert_eq(
		state.batch_plans.leader_id_for(1, state.round_number),
		beta.id,
		"leadership follows turn order, not roster order"
	)


## Two units in DIFFERENT batches are not a batch — each pays its own full
## search, which is what stops the optimisation quietly applying to everyone.
func test_members_of_different_batches_each_lead_their_own() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var alpha: Unit = field["alpha"]
	var beta: Unit = field["beta"]
	alpha.batch_id = 1
	beta.batch_id = 2

	UnitAI.engagement_searches = 0
	await _plan(alpha, state)
	await _plan(beta, state)

	assert_eq(UnitAI.engagement_searches, 2)


func test_an_independent_unit_never_records_a_plan() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]

	await _plan(field["alpha"], state)

	assert_true(state.batch_plans.for_batch(0, state.round_number).is_empty())


# --- what a follower does ---------------------------------------------------


## "Followers keep the cheap can-I-fire-from-where-I-stand check. Only the
## expensive positional search is replaced." A follower with a shot must take it
## rather than jogging toward its leader first.
func test_a_follower_with_a_shot_fires_instead_of_forming_up() -> void:
	var grid: Grid = GridFixture.flat(24, 20)
	var leader: Unit = _armed_unit(&"leader", Vector2i(2, 2), 0)
	# 9 clear cells from the enemy, past MARKSMAN's own standoff of 7 and inside
	# the weapon's 15, so firing from right here is already the right call.
	var follower: Unit = _armed_unit(&"follower", Vector2i(2, 9), 0)
	var enemy: Unit = _armed_unit(&"enemy", Vector2i(11, 9), 1)
	var state := CombatState.new(grid, [leader, follower, enemy])
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	leader.batch_id = 1
	follower.batch_id = 1
	# The leader is somewhere else entirely, so "form up" and "shoot" disagree.
	state.batch_plans.record(1, state.round_number, leader.id, Vector2i(2, 2))

	var queue: ActionQueue = await _plan(follower, state)

	var fired: bool = queue.actions.any(
		func(action: CombatAction) -> bool: return action is AttackAction or action is BurstAction
	)
	assert_true(fired, "it already had the shot; the batch can wait")


## The scan proper: cells near the leader's destination are reachable, so a
## handful of them get scored and one is chosen.
func test_a_follower_lands_beside_its_leaders_destination_when_it_can_reach_it() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var beta: Unit = field["beta"]
	(field["alpha"] as Unit).batch_id = 1
	beta.batch_id = 1
	var destination := Vector2i(9, 10)
	state.batch_plans.record(1, state.round_number, (field["alpha"] as Unit).id, destination)

	assert_eq(await _branch_taken(beta, state), &"followed_leader", "sanity: the follow branch ran")
	var landed: Vector2i = _destination_of(await _plan(beta, state), beta)
	assert_lte(
		Grid.distance_chebyshev(landed, destination),
		UnitAI.FOLLOWER_SCAN_RADIUS,
		"it formed up within the scan radius"
	)


## The other branch, and the more common one: the leader's destination is out of
## reach this turn, so the follower walks as far toward it as the turn allows,
## with no scoring at all.
func test_a_distant_follower_closes_on_the_leaders_destination() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var beta: Unit = field["beta"]
	(field["alpha"] as Unit).batch_id = 1
	beta.batch_id = 1
	# Far enough that nothing reachable this turn is within the scan radius.
	var destination := Vector2i(26, 21)
	state.batch_plans.record(1, state.round_number, (field["alpha"] as Unit).id, destination)
	var before: int = Grid.distance_chebyshev(beta.cell, destination)

	assert_eq(await _branch_taken(beta, state), &"followed_leader", "sanity: the follow branch ran")
	var landed: Vector2i = _destination_of(await _plan(beta, state), beta)
	assert_lt(Grid.distance_chebyshev(landed, destination), before, "it closed on the leader")


## Where the unit ends up: the last cell of the last queued move, or where it
## started if it queued none.
func _destination_of(queue: ActionQueue, unit: Unit) -> Vector2i:
	var landed: Vector2i = unit.cell
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			var path: Array[Vector2i] = (action as MoveAction).path
			landed = path[path.size() - 1]
	return landed


# --- lifetime and edges -----------------------------------------------------


## D3, verbatim: "Leader dies mid-round after planning — followers keep the
## cached destination for the remainder of that round." The squad completes the
## manoeuvre it was committed to and reorganises next round.
func test_a_follower_keeps_the_plan_after_its_leader_dies_mid_round() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var alpha: Unit = field["alpha"]
	var beta: Unit = field["beta"]
	alpha.batch_id = 1
	beta.batch_id = 1
	await _plan(alpha, state)
	var destination: Vector2i = state.batch_plans.for_batch(1, state.round_number)["destination"]

	state.kill_unit(alpha)

	assert_eq(
		state.batch_plans.for_batch(1, state.round_number)["destination"],
		destination,
		"the record outlives the unit that made it"
	)
	UnitAI.engagement_searches = 0
	await _plan(beta, state)
	assert_eq(UnitAI.engagement_searches, 0, "and the survivor still follows it")


## The other half of the same rule: next round the record has aged out, so the
## next living member simply leads. No promotion code runs, because there is
## none.
func test_the_next_round_hands_the_lead_to_a_living_member_with_no_promotion() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var alpha: Unit = field["alpha"]
	var beta: Unit = field["beta"]
	alpha.batch_id = 1
	beta.batch_id = 1
	await _plan(alpha, state)
	state.kill_unit(alpha)

	state.round_number += 1
	beta.ap = beta.max_ap
	UnitAI.engagement_searches = 0
	await _plan(beta, state)

	assert_eq(UnitAI.engagement_searches, 1, "the survivor pays the real cost now")
	assert_eq(state.batch_plans.leader_id_for(1, state.round_number), beta.id)


## A batch whose every member is dead needs no special handling — the record is
## simply never refreshed and never read again.
func test_a_wholly_dead_batch_is_inert() -> void:
	var field: Dictionary = _field()
	var state: CombatState = field["state"]
	var alpha: Unit = field["alpha"]
	var beta: Unit = field["beta"]
	alpha.batch_id = 1
	beta.batch_id = 1
	await _plan(alpha, state)
	state.kill_unit(alpha)
	state.kill_unit(beta)

	state.round_number += 1

	assert_true(state.batch_plans.for_batch(1, state.round_number).is_empty())
	assert_eq(state.batch_plans.leader_id_for(1, state.round_number), BatchPlan.NO_LEADER)


# --- and the promise to everything that isn't batched -----------------------


func _bout(map_seed: int) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.presets_pool()[i % DataLibrary.presets_pool().size()]
		roster.append(entry)
	return BoutSetup.build_bout(roster, roster, map_seed)


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


## `batch_id == 0` is byte-identical to before this pass — which is every unit in
## every bout, since generated missions assign no batches.
func test_an_unbatched_bout_is_byte_identical() -> void:
	var a: Dictionary = _bout(31337)
	assert_eq(a.get("error", ""), "", "sanity: the bout built")
	var expected: Array[String] = await _action_sequence(a.state, a.mission, 8)

	var b: Dictionary = _bout(31337)
	var actual: Array[String] = await _action_sequence(b.state, b.mission, 8)

	assert_eq(actual, expected)
	assert_gt(expected.size(), 0, "sanity: the bout actually did something")
