extends GutTest

## taskblock-14 Pass C: BoutRunner — an all-AI CombatState driven turn by
## turn through the same UnitAI.plan_turn + CombatState.resolve_until a
## human's own UI uses.


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
	weapon.weapon_max_range = 15.0
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
func test_step_does_nothing_for_a_human_controlled_squad() -> void:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(5, 0), 1, &"rifle", 30)
	var state := CombatState.new(Grid.new(10, 5), [jerry, enemy], 1)
	# Squad 0 left HUMAN (the default) on purpose.
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.extraction_cells = [Vector2i(0, 0)]
	var runner := BoutRunner.new(state, mission, 50)
	var ap_before: int = jerry.ap

	var finished: bool = runner.step()

	assert_false(finished)
	assert_eq(jerry.ap, ap_before, "a human squad's turn must never be auto-resolved")
	assert_eq(runner.turns_taken, 0)
