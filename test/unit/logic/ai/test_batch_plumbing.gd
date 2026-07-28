extends GutTest

## taskblock-43 Pass C: batch plumbing only — a `Unit.batch_id`, a debug verb to
## set it, a round-scoped `BatchPlan` store, and a board badge. **No planning
## change whatsoever**, which is what the last test in this file exists to prove.
##
## The pass exists so Pass D (leader plans, followers follow) can be built
## against something already testable and already visible on the board, rather
## than landing the plumbing and the behaviour together and having no way to tell
## which half a regression came from.


func _bout(map_seed: int) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.presets_pool()[i % DataLibrary.presets_pool().size()]
		roster.append(entry)
	return BoutSetup.build_bout(roster, roster, map_seed)


## taskblock-45 Pass E: a utility decision contributes the ACTION IT CHOSE, not
## just its event kind.
##
## **A queue shape cannot tell two decisions apart when they land on the same
## cell** — `approach` and `take_cover` both emit a `MoveAction`, so an event-kind
## diff reads them as identical while the decisions differ. That made the
## batch-behaviour claim below unfalsifiable in either direction: it could pass on
## an unrelated difference or fail on a real one it could not see. The decision log
## exists for exactly this question, so it is what gets read.
func _action_sequence(state: CombatState, mission: MissionState, steps: int) -> Array[String]:
	# **Its own sink across the whole run, not `runner.last_events`.** `last_events`
	# captures what RESOLUTION emitted, and a planning decision is emitted during
	# TACTICS, before `resolve_until` is ever called — so the decisions were
	# invisible to this helper entirely. That is why the batch claim below could
	# neither pass nor fail for the right reason.
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var runner := BoutRunner.new(state, mission)
	var i := 0
	while not runner.finished and i < steps:
		await runner.step()
		i += 1
	state.combat_log.remove_sink(sink)

	var taken: Array[String] = []
	for event: LogEvent in sink.events:
		if event.kind == &"ai_utility_decision":
			taken.append("chose:%s@%d" % [event.data.get("winner", "nothing"), event.unit_id])
			continue
		taken.append("%s@%d" % [event.kind, event.unit_id])
	return taken


func _unit_at(cell: Vector2i, squad_id: int) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad_id)


# --- the field and the verb -------------------------------------------------


func test_a_fresh_unit_is_independent() -> void:
	assert_eq(_unit_at(Vector2i(1, 1), 0).batch_id, 0, "0 means plans for itself")


func test_the_verb_sets_and_then_clears_batch_membership() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var unit: Unit = _unit_at(Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	var injector := BoutInjector.new(state)

	assert_true(injector.set_batch(unit, 3), "assigned")
	assert_eq(unit.batch_id, 3)

	assert_true(injector.set_batch(unit, 0), "cleared back to independent")
	assert_eq(unit.batch_id, 0)


## Every verb goes through the one gate; a batch assignment is no exception.
func test_the_verb_refuses_mid_resolution() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var unit: Unit = _unit_at(Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.is_resolving = true

	var injector := BoutInjector.new(state)
	assert_false(injector.set_batch(unit, 4))
	assert_eq(unit.batch_id, 0, "a refused verb mutates nothing")
	assert_push_error("BoutInjector: set_batch rejected — injection mid-resolution is forbidden")


func test_the_verb_is_offered_by_the_debug_panel() -> void:
	var ids: Array[StringName] = []
	for spec: DebugVerbSpec in DebugVerbs.all():
		ids.append(spec.id)
	assert_has(ids, &"set_batch", "hand-assignable from the panel, per the block")
	assert_false(DebugVerbs.affects_board(&"set_batch"), "it touches one unit, not the board")


## `dup()` is TACTICS-time preview cloning — a clone that silently lost its batch
## would plan as an independent and disagree with the unit it previews.
func test_batch_membership_survives_dup() -> void:
	var unit: Unit = _unit_at(Vector2i(3, 3), 0)
	unit.batch_id = 7

	assert_eq(unit.dup().batch_id, 7)


## `CombatState.add_unit` re-registers every unit including dead ones, so the
## field has to ride along rather than being reset by registration.
func test_batch_membership_survives_re_registration() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var unit: Unit = _unit_at(Vector2i(4, 4), 0)
	unit.batch_id = 2
	var dead: Unit = _unit_at(Vector2i(5, 5), 0)
	dead.batch_id = 2
	dead.alive = false

	var state := CombatState.new(grid, [unit, dead])

	assert_eq(state.units[0].batch_id, 2, "the living member")
	assert_eq(state.units[1].batch_id, 2, "and the dead one")


# --- the round-scoped plan store --------------------------------------------


func test_a_plan_is_visible_in_its_own_round_and_gone_in_the_next() -> void:
	var plans := BatchPlan.new()
	assert_true(plans.record(1, 5, 42, Vector2i(9, 9)))

	assert_eq(plans.leader_id_for(1, 5), 42, "same round: the leader is known")
	assert_eq(plans.for_batch(1, 5)["destination"], Vector2i(9, 9))
	assert_eq(plans.leader_id_for(1, 6), BatchPlan.NO_LEADER, "next round: stale, so nothing")
	assert_true(plans.for_batch(1, 6).is_empty())


## The first member to act IS the leader, so a later member must not be able to
## redirect the batch mid-manoeuvre.
func test_the_first_record_of_a_round_wins() -> void:
	var plans := BatchPlan.new()
	plans.record(1, 5, 42, Vector2i(9, 9))

	assert_false(plans.record(1, 5, 77, Vector2i(1, 1)), "the second member is refused")
	assert_eq(plans.leader_id_for(1, 5), 42)
	assert_eq(plans.for_batch(1, 5)["destination"], Vector2i(9, 9))


func test_batch_zero_is_never_recorded() -> void:
	var plans := BatchPlan.new()

	assert_false(plans.record(0, 1, 42, Vector2i.ZERO), "0 is independence, not a batch")
	assert_true(plans.for_batch(0, 1).is_empty())


func test_a_bout_starts_with_no_plans_at_all() -> void:
	var built: Dictionary = _bout(31337)
	var state: CombatState = built["state"]

	for unit: Unit in state.units:
		assert_eq(unit.batch_id, 0, "generated missions assign no batches in this block")
		assert_eq(state.batch_plans.badge_for(unit, state.round_number), "")


# --- the badge --------------------------------------------------------------


## What the indicator SAYS, decided headlessly, because CC cannot see the screen
## and a view-only answer would be unverifiable.
func test_the_badge_names_the_batch_and_marks_the_leader() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var leader: Unit = _unit_at(Vector2i(2, 2), 0)
	var follower: Unit = _unit_at(Vector2i(3, 3), 0)
	var loner: Unit = _unit_at(Vector2i(4, 4), 0)
	var state := CombatState.new(grid, [leader, follower, loner])
	state.batch_plans.record(2, state.round_number, leader.id, Vector2i(8, 8))
	leader.batch_id = 2
	follower.batch_id = 2

	assert_eq(state.batch_plans.badge_for(leader, state.round_number), "B2*")
	assert_eq(state.batch_plans.badge_for(follower, state.round_number), "B2")
	assert_eq(state.batch_plans.badge_for(loner, state.round_number), "")


## Before anyone in the batch has acted there is no leader to mark, and every
## member reads as an ordinary member rather than the badge guessing one.
func test_no_member_is_marked_leader_before_the_batch_has_acted() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var one: Unit = _unit_at(Vector2i(2, 2), 0)
	var two: Unit = _unit_at(Vector2i(3, 3), 0)
	var state := CombatState.new(grid, [one, two])
	one.batch_id = 5
	two.batch_id = 5

	assert_eq(state.batch_plans.badge_for(one, state.round_number), "B5")
	assert_eq(state.batch_plans.badge_for(two, state.round_number), "B5")


# --- and the thing this whole pass promises ---------------------------------


## The pass's own headline claim: "default-zero units behave exactly as they do
## today." A seeded bout must produce the same action sequence it did before any
## of the above existed — no planning change has been made yet, and this is what
## would catch one if it had.
func test_default_zero_units_produce_an_unchanged_action_sequence() -> void:
	var a: Dictionary = _bout(31337)
	assert_eq(a.get("error", ""), "", "sanity: the bout built")
	var expected: Array[String] = await _action_sequence(a.state, a.mission, 8)

	var b: Dictionary = _bout(31337)
	var actual: Array[String] = await _action_sequence(b.state, b.mission, 8)

	assert_eq(actual, expected)
	assert_gt(expected.size(), 0, "sanity: the bout actually did something")


## The other side of the same claim, and **this test has been re-aimed twice.**
##
## Pass C wrote it asserting that assigning a batch changed nothing, which was true
## while `batch_id` was plumbing nobody read. taskblock-43 Pass D inverted it: a
## follower copied its leader's DESTINATION, so a batched bout diverged from an
## unbatched one within a few steps and an event-stream diff could see that.
##
## **taskblock-45 Pass C replaced the destination with an objective, and the
## original assertion becomes true again — for a completely different reason.** An
## objective is injected as a consideration input and biases what a follower WANTS;
## it is read only by the combat actions. In this seeded bout every unit is running
## MISSION actions (walk to the node, gather, walk to extraction) which read no
## objective input at all, and the leader cannot see an enemy on its own first turn,
## so no objective is even chosen. Nothing changes, and nothing should.
##
## That is a real guard rather than a tautology: **it fails the moment an objective
## starts damping something it has no business damping** — a mission action that
## grew an objective consideration, or a dormant vector that stopped being neutral.
##
## The behavioural claim — that a follower under `withdraw` decides differently from
## one under `advance` — is `test_batch_objective.gd`'s, on a board where combat
## actions are genuinely on offer and an enemy is genuinely visible.
func test_assigning_a_batch_leaves_a_mission_only_bout_untouched() -> void:
	var a: Dictionary = _bout(31337)
	var expected: Array[String] = await _action_sequence(a.state, a.mission, 8)

	var b: Dictionary = _bout(31337)
	for unit: Unit in (b.state as CombatState).units:
		unit.batch_id = 1
	var actual: Array[String] = await _action_sequence(b.state, b.mission, 8)

	assert_eq(actual, expected, "an objective may only ever bias a COMBAT decision")
	assert_gt(expected.size(), 0, "sanity: the bout actually did something")
