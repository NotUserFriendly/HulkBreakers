extends GutTest

## taskblock-14 Pass C: BoutRunner — an all-AI CombatState driven turn by
## turn through the same UnitAI.plan_turn + CombatState.resolve_until a
## human's own UI uses.
##
## taskblock-15 Pass A: generalized into every ControlOverlay's shared
## turn driver via an injectable `wants_turn_for` Callable — every test
## above constructs BoutRunner with no such Callable, proving the default
## (today's exact controller_for check) is completely unchanged.


func _armed_unit(
	id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName, torso_hp: int = 10
) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = weapon_id
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 6.0
	weapon.ap_cost = 1
	# taskblock-24 Pass A: the AI now asks ActionCatalog what this weapon
	# actually provides before firing — without this, no bout unit here
	# ever fires at all, and a bout that can never resolve by combat runs
	# to its own turn cap instead of a normal few-turn finish.
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
	torso.sockets = [hand_socket, Socket.new(&"MATRIX")]

	# A docked matrix (test_full_mission.gd's own _landing_unit convention)
	# is what makes destroying the torso actually kill the unit — Phase 7's
	# real matrix-ejection rule fires on the SPECIFIC part hosting it,
	# strictly earlier than the Phase 6 "no living parts left AT ALL"
	# fallback AttackAction/BurstAction still carry, which a torso-only
	# hit alone can never satisfy while an unrelated hand/weapon survives.
	var link := Matrix.new()
	link.id = StringName("%s_link" % id)
	torso.hosted_matrix = link
	return Unit.new(link, Shell.new(torso), cell, squad_id)


## A 2-vs-1 bout: squad 0 (strong) should overwhelm squad 1 (weak) and
## then walk to a real extraction cell — a real EXTRACTED ending, not a
## stalemate safety net.
func _winning_bout(turn_cap: int = 200) -> Dictionary:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var alice := _armed_unit(&"alice", Vector2i(1, 0), 0, &"rifle", 30)
	var weak_enemy := _armed_unit(&"weak_enemy", Vector2i(8, 0), 1, &"pistol", 5)
	var state := CombatState.new(Grid.new(12, 5), [jerry, alice, weak_enemy], 11)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)

	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]

	var runner := BoutRunner.new(state, mission, turn_cap)
	return {"runner": runner, "state": state, "mission": mission}


func test_a_winning_bout_runs_to_a_terminal_state_and_never_loops_forever() -> void:
	var built: Dictionary = _winning_bout()
	var runner: BoutRunner = built.runner

	runner.run_to_completion()

	assert_true(runner.finished)
	assert_lt(runner.turns_taken, runner.turn_cap, "must terminate well inside the cap")
	assert_ne(built.mission.outcome, Enums.MissionOutcome.UNDECIDED)


## "Every AI turn resolves through resolve_until" — by construction
## (`step()` calls it directly), asserted here via the queue's own
## real, non-trivial effect (AP actually spent) rather than trusting the
## implementation.
func test_every_step_resolves_a_real_turn_through_resolve_until() -> void:
	var built: Dictionary = _winning_bout()
	var runner: BoutRunner = built.runner
	var state: CombatState = built.state
	var acting_unit: Unit = state.current_unit()
	var ap_before: int = acting_unit.ap

	runner.step()

	assert_eq(runner.last_unit, acting_unit)
	assert_true(runner.last_outcome.has("kind"))
	assert_lt(acting_unit.ap, ap_before, "a real action must have actually spent AP")


## "The bout is deterministic for a seed (same bout -> same outcome)."
func test_the_bout_is_deterministic_for_the_same_seed() -> void:
	var results: Array = []
	for run in range(2):
		var built: Dictionary = _winning_bout()
		var runner: BoutRunner = built.runner
		runner.run_to_completion()
		results.append([built.mission.outcome, runner.turns_taken])

	assert_eq(results[0], results[1])


## The turn-cap safety net: even a bout that can never resolve on its
## own (here, forced by a cap of 0) still finishes, via TERMINATED —
## the same voluntary "give up" a human could choose, just triggered by
## the watcher instead of a player. Never an infinite loop.
func test_the_turn_cap_guarantees_termination_via_the_terminated_outcome() -> void:
	var built: Dictionary = _winning_bout(0)
	var runner: BoutRunner = built.runner

	var finished: bool = runner.step()

	assert_true(finished)
	assert_eq(built.mission.outcome, Enums.MissionOutcome.TERMINATED)


## STRANDED: the player squad wiped out first.
func test_the_player_squads_own_defeat_ends_the_bout_stranded() -> void:
	var doomed := _armed_unit(&"doomed", Vector2i(0, 0), 0, &"pistol", 1)
	var strong_enemy := _armed_unit(&"strong_enemy", Vector2i(1, 0), 1, &"rifle", 200)
	var state := CombatState.new(Grid.new(10, 5), [doomed, strong_enemy], 5)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(0, 0)]
	var runner := BoutRunner.new(state, mission, 200)

	runner.run_to_completion()

	assert_eq(mission.outcome, Enums.MissionOutcome.STRANDED)


## "Pause/step/speed don't alter the outcome, only its pacing" — a bout
## driven one step() at a time (with arbitrary gaps between calls,
## simulating pause) must reach the exact same outcome as one driven in
## a tight loop, since pacing is purely a view-layer/timer concern
## BoutRunner itself has no notion of.
func test_stepping_one_call_at_a_time_reaches_the_same_outcome_as_a_tight_loop() -> void:
	var tight: Dictionary = _winning_bout()
	tight.runner.run_to_completion()

	var stepped: Dictionary = _winning_bout()
	var guard := 0
	while not stepped.runner.step():
		guard += 1
		if guard > 1000:
			fail_test("stepped runner never finished")
			break

	assert_eq(stepped.mission.outcome, tight.mission.outcome)
	assert_eq(stepped.runner.turns_taken, tight.runner.turns_taken)


## A human-controlled squad's turn is never auto-resolved — step()
## stays inert (returns false, does nothing) rather than acting for a
## squad this bout doesn't own, even though this block's own bouts
## always set every squad to AI.
## tb31 Pass B: BR30.09's root cause was a bout path assigning nothing and
## silently inheriting a default controller, which then read as a genuine
## hang. `UNASSIGNED` (the real zero-default now) makes this structurally
## impossible: constructing a runner over a squad still unset is a hard,
## loud construction error, never a guess.
func test_constructing_a_runner_over_an_unassigned_squad_is_a_hard_error() -> void:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(5, 0), 1, &"rifle", 30)
	var state := CombatState.new(Grid.new(10, 5), [jerry, enemy], 1)
	state.set_squad_controller(0, Enums.SquadController.AI)
	# Squad 1 deliberately left UNASSIGNED.
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(0, 0)]

	var runner := BoutRunner.new(state, mission, 50)

	assert_push_error("squad controller", "must fail loudly, not silently run")
	assert_true(runner.finished, "an ill-defined bout must never actually drive a turn")


func test_step_does_nothing_for_a_human_controlled_squad() -> void:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(5, 0), 1, &"rifle", 30)
	var state := CombatState.new(Grid.new(10, 5), [jerry, enemy], 1)
	# tb31 Pass B: HUMAN is no longer a silent default — assigned explicitly.
	state.set_squad_controller(0, Enums.SquadController.HUMAN)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(0, 0)]
	var runner := BoutRunner.new(state, mission, 50)
	var ap_before: int = jerry.ap

	var finished: bool = runner.step()

	assert_false(finished)
	assert_eq(jerry.ap, ap_before, "a human squad's turn must never be auto-resolved")
	assert_eq(runner.turns_taken, 0)


## taskblock-15 Pass B: `last_events` is exactly this step's own events —
## a fresh MemorySink wired around just this resolve_until call, not
## every event ever emitted (log_sink/file_sink-style accumulation would
## defeat the point: a view needs to know what THIS turn did).
func test_last_events_carries_exactly_this_steps_own_events_not_everyones() -> void:
	var built: Dictionary = _winning_bout()
	var runner: BoutRunner = built.runner

	runner.step()
	var first_step_events: Array[LogEvent] = runner.last_events
	assert_false(first_step_events.is_empty(), "a real turn must emit at least turn_start")

	runner.step()
	var second_step_events: Array[LogEvent] = runner.last_events
	assert_ne(
		second_step_events,
		first_step_events,
		"the second step's own events must not still be the first step's"
	)


## taskblock-15 Pass A: a caller-supplied `wants_turn_for` overrides the
## default squad-controller check entirely — even a squad flagged AI here
## stays inert once the injected predicate claims its current unit,
## proving `ControlOverlay.wants_turn_for`-style per-UNIT (not just
## per-squad) control is real, not just documented.
func test_an_injected_wants_turn_for_overrides_the_default_squad_check() -> void:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(5, 0), 1, &"rifle", 30)
	var state := CombatState.new(Grid.new(10, 5), [jerry, enemy], 1)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(0, 0)]
	var claims_jerry := func(unit: Unit) -> bool: return unit == jerry
	var runner := BoutRunner.new(state, mission, 50, claims_jerry)
	var ap_before: int = jerry.ap

	var finished: bool = runner.step()

	assert_false(finished)
	assert_eq(jerry.ap, ap_before, "the injected predicate must claim jerry even though AI owns it")
	assert_eq(runner.turns_taken, 0)


## Mirrors test_step_out_planner.gd's own `_overwatcher` (torso -[WRIST]-
## hand(TRIGGER) -[GRIP]- weapon) — `UnitGeometry.muzzle_point`'s own
## placement math specifically depends on a WRIST socket, unlike this
## file's own plain `_armed_unit` (HAND socket).
func _overwatch_capable_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var weapon := Part.new()
	weapon.id = &"rifle"
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	# Genuinely unaffordable as a plain shot (vs. this fixture's own 3
	# max_ap below) — OverwatchAction's own flat 1-AP declare cost stays
	# affordable regardless, so this weapon's only real option each turn
	# is holding overwatch, not firing or improving its own position.
	weapon.ap_cost = 5
	weapon.provides_actions = [&"shoot", &"overwatch"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 15.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	var matrix := Matrix.new()
	matrix.playstyle = &"MARKSMAN"
	return Unit.new(matrix, Shell.new(torso), cell, squad_id)


## taskblock-24 Pass C: "a bout now contains held overwatch that triggers
## on an advancing enemy (the dormant layer is live)" — a real, entirely
## AI-vs-AI bout, driven only through `BoutRunner.step()` (never a hand-
## built resolve_until/Overwatch.check_trigger call): a MARKSMAN holds
## overwatch (nothing better to do — its own shot is genuinely
## unaffordable), then the enemy's own ordinary AGGRESSIVE advance (a
## straight, 1-wide corridor leaves no other route) walks it into the
## held arc and the trigger actually fires — proof `BoutRunner.step()`
## itself now wires `Overwatch.check_trigger` as its own resolve_until
## mid_move_hook; before this pass, overwatch could be validly declared
## by the AI and still never once trigger in any real bout.
func test_a_bout_contains_held_overwatch_that_triggers_on_an_advancing_enemy() -> void:
	var grid := Grid.new(20, 3)
	for x in range(20):
		grid.set_terrain(Vector2i(x, 0), Enums.TerrainType.WALL)
		grid.set_terrain(Vector2i(x, 2), Enums.TerrainType.WALL)
	var self_unit := _overwatch_capable_unit(&"self_unit", Vector2i(0, 1), 0)
	self_unit.max_ap = 3
	self_unit.orientation = FaceAction.orientation_toward(Vector2i(0, 1), Vector2i(7, 1))
	var enemy := _armed_unit(&"enemy", Vector2i(15, 1), 1, &"pistol")
	# A short-range weapon (vs. self_unit's own 15.0) forces the enemy to
	# actually close most of the corridor's own distance before it can
	# fire back at all, instead of sniping from just outside the arc.
	enemy.shell.find_part(&"pistol").weapon_def.max_range = 3.0
	var state := CombatState.new(grid, [self_unit, enemy])
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []

	var runner := BoutRunner.new(state, mission, 60)
	var declared := false
	var triggered := false
	while not runner.finished:
		runner.step()
		for event: LogEvent in runner.last_events:
			if event.kind == &"overwatch_declared":
				declared = true
			if event.kind == &"overwatch_triggered":
				triggered = true
		if triggered:
			break

	assert_true(declared, "sanity: the MARKSMAN must actually hold overwatch first")
	assert_true(
		triggered, "an advancing enemy must actually trigger the held overwatch in a real bout"
	)
