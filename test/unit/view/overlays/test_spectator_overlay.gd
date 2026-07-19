extends GutTest

## taskblock-14 Pass C / taskblock-15 Pass A: SpectatorOverlay — the
## structural/state-machine half of the watch loop that can actually be
## asserted headlessly (play/pause/step/speed transitions). The
## moment-to-moment visual result (camera framing, board mesh) is not
## something a headless test can read back meaningfully; those were
## confirmed by a single live check, per this project's own "you cannot
## see the game — read the real node back" discipline applied at the
## structural level instead.
##
## taskblock-15 Pass A: this overlay no longer builds its own world
## (BoutView used to) — every test below builds a real BattleScene,
## loads a bout into it, then swaps to SpectatorOverlay, exactly the path
## GenerateBoutOverlay itself uses.


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

	var link := Matrix.new()
	link.id = StringName("%s_link" % id)
	torso.hosted_matrix = link
	return Unit.new(link, Shell.new(torso), cell, squad_id)


func _bout(map_seed: int = 11) -> Dictionary:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(8, 0), 1, &"pistol", 5)
	var state := CombatState.new(Grid.new(12, 5), [jerry, enemy], map_seed)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	return {"state": state, "mission": mission}


## Every test's own real path: a real BattleScene, a bout loaded into it,
## then swapped to SpectatorOverlay — the exact sequence
## GenerateBoutOverlay itself drives (A2). Neutralizes _ready()'s own
## default SquadControlOverlay FIRST (a bare ControlOverlay — the base
## class's every method is already a real, working no-op) — loading an
## all-AI bout straight into a STILL-ATTACHED SquadControlOverlay would
## trigger ITS OWN battle_loaded reactivity and auto-resolve the whole
## bout via advance_ai_turns() before this function ever got to install
## SpectatorOverlay, exactly the hazard GenerateBoutOverlay itself avoids
## by never being the SquadControlOverlay in the first place.
func _spectate(built: Dictionary) -> SpectatorOverlay:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	battle.set_overlay(SpectatorOverlay.new())
	return battle.overlay as SpectatorOverlay


func test_setup_wires_a_bout_runner_against_the_loaded_battle() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	assert_not_null(overlay.runner)
	assert_eq(overlay.runner.state, overlay.battle.combat_state)


func test_play_starts_the_timer_and_pause_stops_it() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	overlay.play()
	assert_true(overlay.playing)
	assert_false(overlay._timer.is_stopped())

	overlay.pause()
	assert_false(overlay.playing)
	assert_true(overlay._timer.is_stopped())


## "Step-one-action" (this bout's own granularity: one unit's whole
## turn) advances exactly one turn and leaves the bout paused, never
## auto-continuing.
func test_step_once_advances_exactly_one_turn_and_stays_paused() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	overlay.step_once()

	assert_eq(overlay.runner.turns_taken, 1)
	assert_false(overlay.playing)
	assert_true(overlay._timer.is_stopped())


## "Speed (1x, 2x, 4x)" — three fixed steps, cycling back to 1x.
func test_speed_cycles_through_the_three_fixed_steps() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	assert_almost_eq(overlay.speed, 1.0, 0.0001)
	overlay._on_speed_button_pressed()
	assert_almost_eq(overlay.speed, 2.0, 0.0001)
	overlay._on_speed_button_pressed()
	assert_almost_eq(overlay.speed, 4.0, 0.0001)
	overlay._on_speed_button_pressed()
	assert_almost_eq(overlay.speed, 1.0, 0.0001)


## "Pause/step/speed don't alter the outcome, only its pacing" —
## verified at the BoutRunner level already (test_bout_runner.gd); this
## confirms the overlay's own pacing controls don't touch runner state
## beyond what step()/timer cadence already do: each step_once() call
## advances turns_taken by exactly one, never zero or more than one,
## regardless of speed (this fixture's own combat can finish before 3
## calls — set_speed must not change THAT either).
func test_a_faster_speed_never_skips_or_repeats_a_single_step() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())
	overlay.set_speed(4.0)

	for i in range(3):
		if overlay.runner.finished:
			break
		var before: int = overlay.runner.turns_taken
		overlay.step_once()
		assert_eq(
			overlay.runner.turns_taken, before + 1, "step %d must advance by exactly one turn" % i
		)


func test_the_bout_finishing_stops_playback() -> void:
	var overlay: SpectatorOverlay = _spectate(_bout())

	var guard := 0
	while not overlay.runner.finished and guard < 500:
		overlay.step_once()
		guard += 1

	assert_true(overlay.runner.finished)
	assert_false(overlay.playing)
	assert_true(overlay._timer.is_stopped())


## taskblock-15 Pass A's own TESTS list: "a spectator battle is identical
## in outcome to today's BoutRunner bout for the same seed (the overlay
## is cosmetic — prove it)." Two independently-built CombatStates from
## the same seed, one driven by a bare BoutRunner (taskblock-14's own
## path), one driven by SpectatorOverlay stepped to completion — same
## outcome, same turn count. True by construction (SpectatorOverlay IS a
## BoutRunner underneath), but locked in as a real regression test rather
## than left as an architectural claim nobody checks.
func test_a_spectated_bout_matches_a_bare_bout_runner_for_the_same_seed() -> void:
	var bare: Dictionary = _bout(42)
	var bare_runner := BoutRunner.new(bare.state, bare.mission)
	bare_runner.run_to_completion()

	var spectated: Dictionary = _bout(42)
	var overlay: SpectatorOverlay = _spectate(spectated)
	var guard := 0
	while not overlay.runner.finished and guard < 500:
		overlay.step_once()
		guard += 1

	assert_eq(spectated.mission.outcome, bare.mission.outcome)
	assert_eq(overlay.runner.turns_taken, bare_runner.turns_taken)
