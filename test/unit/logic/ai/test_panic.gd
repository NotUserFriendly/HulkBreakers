extends GutTest

## taskblock-46 Pass D: the scorer wanting nothing at all, made visible.
##
## **An escape hatch nobody can see is indistinguishable from a bug.** "The AI just
## stood there" and "the AI panicked" look identical from outside the game and want
## completely different responses, so a panic is named, carries a reason, and takes
## a real action rather than quietly ending the turn.

const AGGRESSIVE_PROFILE := &"aggressive"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _bare_unit(id: StringName, cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = id
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


## A unit with no weapon, no mission, nobody to see, **and a search behaviour no
## authored verb answers to** — so every gate in the pool fails and nothing is
## offered at all.
##
## That last part is the honest way to reach this state now that taskblock-46 Pass C
## filled the pool: a unit assigned `NONE` genuinely has a hole where its search
## verb should be, which is exactly the `nothing_offered` case Panic reports. Before
## Pass C every blind unit was in this state; the fixture has to work harder now,
## which is the point of that pass.
func _stranded_unit() -> Dictionary:
	var unit: Unit = _bare_unit(&"lone_torso", Vector2i(2, 2))
	unit.search_behaviour = &"NONE"
	var other: Unit = _bare_unit(&"other_torso", Vector2i(9, 9))
	var grid: Grid = GridFixture.flat(12, 12)
	var state := CombatState.new(grid, [unit, other])
	state.force_current_unit(unit.id)
	for each: Unit in state.units:
		each.ap = each.max_ap
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	return {"state": state, "unit": unit, "view": view}


# --- the reason is the diagnostic --------------------------------------------


## `nothing_offered` and `all_vetoed` are different failures wanting different
## fixes — a hole in the action pool versus a judgement that everything was bad —
## and they used to be the same silent shrug.
func test_the_reason_distinguishes_an_empty_pool_from_a_considered_refusal() -> void:
	assert_eq(Panic.reason_for(0, false), Panic.REASON_NOTHING_OFFERED)
	assert_eq(Panic.reason_for(4, false), Panic.REASON_ALL_VETOED)


## **The budget wins over both**, because a scan that stopped early cannot honestly
## claim to have looked at everything. Reporting `all_vetoed` for a cut-short scan
## would be a judgement the planner never actually made.
func test_an_aborted_scan_reports_the_budget_not_a_verdict() -> void:
	assert_eq(Panic.reason_for(0, true), Panic.REASON_BUDGET_ABORTED)
	assert_eq(Panic.reason_for(9, true), Panic.REASON_BUDGET_ABORTED)


# --- a panic is never an empty turn ------------------------------------------


## The load-bearing one. An empty queue never calls `advance_turn`, so a unit that
## panicked into nothing would stall the entire bout on the one unit with the least
## to offer.
func test_a_panicking_unit_produces_a_real_action_rather_than_an_empty_turn() -> void:
	var bout: Dictionary = _stranded_unit()
	var sink := MemorySink.new()
	bout.state.combat_log.add_sink(sink)

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.unit, bout.view, null, AGGRESSIVE_PROFILE
	)
	bout.state.combat_log.remove_sink(sink)

	assert_gt(queue.actions.size(), 0, "a panic still queues something")
	var panics: Array[LogEvent] = sink.events_of_kind(&"panic")
	assert_eq(panics.size(), 1, "and says so exactly once")
	gut.p("panic: %s" % panics[0].text)


## Visible in the combat log, with the reason machine-readable rather than only
## spelled out in prose — a reader grepping for why a unit did nothing should not
## have to parse a sentence.
func test_a_panic_is_visible_in_the_combat_log_with_a_reason() -> void:
	var bout: Dictionary = _stranded_unit()
	var sink := MemorySink.new()
	bout.state.combat_log.add_sink(sink)

	await UtilityPlanner.plan_turn(bout.unit, bout.view, null, AGGRESSIVE_PROFILE)
	bout.state.combat_log.remove_sink(sink)

	var panic: LogEvent = sink.events_of_kind(&"panic")[0]
	assert_eq(panic.unit_id, bout.unit.id)
	assert_has(
		[Panic.REASON_NOTHING_OFFERED, Panic.REASON_ALL_VETOED, Panic.REASON_BUDGET_ABORTED],
		panic.data["reason"],
		"the reason is one of the named ones, not free text"
	)
	assert_true(panic.text.contains("panics"), "and reads as something a player can see")


## Shutting down is the honest "this unit has nothing to contribute" — visible on
## the board and narratively true. It must be a real, legal action rather than a
## label on inaction.
func test_a_panic_prefers_a_visible_shutdown_when_that_is_legal() -> void:
	var bout: Dictionary = _stranded_unit()

	var action: CombatAction = Panic.action_for(bout.unit, null, bout.state)

	assert_true(action is ShutdownAction, "a stalled unit gives up visibly")
	assert_true(action.is_legal(bout.state), "and it is a legal action, not a gesture")


## **A unit that panics twice must not stall the board.** `ShutdownAction.is_legal`
## refuses an already-shutdown unit, so the second panic has to fall through to
## something that is always legal.
func test_a_panic_falls_back_to_ending_the_turn_once_shutdown_is_impossible() -> void:
	var bout: Dictionary = _stranded_unit()
	bout.unit.shutdown = true

	var action: CombatAction = Panic.action_for(bout.unit, null, bout.state)

	assert_true(action is EndTurnAction, "always legal for the current unit")


# --- the turn budget ends the turn -------------------------------------------


## The budget is what makes a visible "thinking…" label a promise rather than a
## hope: whatever the planner is doing, the turn ends rather than the plan running
## longer.
func test_an_exhausted_turn_budget_still_ends_the_turn() -> void:
	var bout: Dictionary = _stranded_unit()
	var pacer := PlanPacer.new()
	pacer.budget_msec = 0
	pacer.frame_signal = get_tree().process_frame

	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		bout.unit, bout.view, null, AGGRESSIVE_PROFILE, pacer
	)

	assert_true(pacer.aborted, "sanity: the budget really did fire")
	assert_gt(queue.actions.size(), 0, "the turn ends rather than extending")


## **A unit holding its extraction cell is not stalled**, and shutting it down takes
## a unit that was about to extract cleanly out of the mission. It looks identical
## to a stalled unit from the scorer's side — nothing is offered, because there is
## nothing it should be doing except stand there.
##
## The retired planner carried this exact guard, with its own note that it had been
## caught live. Panic re-introduced the bug by preferring shutdown without it.
func test_a_unit_holding_its_extraction_cell_is_never_shut_down() -> void:
	var unit: Unit = _bare_unit(&"extractor", Vector2i(0, 0))
	var other: Unit = _bare_unit(&"mate", Vector2i(5, 5))
	var grid: Grid = GridFixture.flat(12, 12)
	var state := CombatState.new(grid, [unit, other])
	state.force_current_unit(unit.id)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	assert_true(EndTurnAction.is_holding_position(unit, mission), "sanity: it is on its own cell")
	assert_true(
		Panic.action_for(unit, mission, state) is EndTurnAction,
		"holding must mature into an extraction, not a shutdown"
	)
