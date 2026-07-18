extends GutTest

## taskblock-14 Pass C: BoutView — the structural/state-machine half of
## the watch loop that can actually be asserted headlessly (play/pause/
## step/speed transitions, unit-view population). The moment-to-moment
## visual result (camera framing, board mesh) is not something a
## headless test can read back meaningfully; those were confirmed by a
## single live check, per this project's own "you cannot see the game —
## read the real node back" discipline applied at the structural level
## instead.


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


func _bout() -> Dictionary:
	var jerry := _armed_unit(&"jerry", Vector2i(0, 0), 0, &"rifle", 30)
	var enemy := _armed_unit(&"enemy", Vector2i(8, 0), 1, &"pistol", 5)
	var state := CombatState.new(Grid.new(12, 5), [jerry, enemy], 11)
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)
	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = [Vector2i(0, 0)]
	return {"state": state, "mission": mission}


func test_setup_populates_one_hit_volume_view_per_unit() -> void:
	var view := BoutView.new()
	add_child_autofree(view)
	var built: Dictionary = _bout()

	view.setup(built.state, built.mission)

	assert_eq(view.unit_views.size(), 2)


func test_play_starts_the_timer_and_pause_stops_it() -> void:
	var view := BoutView.new()
	add_child_autofree(view)
	var built: Dictionary = _bout()
	view.setup(built.state, built.mission)

	view.play()
	assert_true(view.playing)
	assert_false(view._timer.is_stopped())

	view.pause()
	assert_false(view.playing)
	assert_true(view._timer.is_stopped())


## "Step-one-action" (this bout's own granularity: one unit's whole
## turn) advances exactly one turn and leaves the bout paused, never
## auto-continuing.
func test_step_once_advances_exactly_one_turn_and_stays_paused() -> void:
	var view := BoutView.new()
	add_child_autofree(view)
	var built: Dictionary = _bout()
	view.setup(built.state, built.mission)

	view.step_once()

	assert_eq(view.runner.turns_taken, 1)
	assert_false(view.playing)
	assert_true(view._timer.is_stopped())


## "Speed (1x, 2x, 4x)" — three fixed steps, cycling back to 1x.
func test_speed_cycles_through_the_three_fixed_steps() -> void:
	var view := BoutView.new()
	add_child_autofree(view)
	var built: Dictionary = _bout()
	view.setup(built.state, built.mission)

	assert_almost_eq(view.speed, 1.0, 0.0001)
	view._on_speed_button_pressed()
	assert_almost_eq(view.speed, 2.0, 0.0001)
	view._on_speed_button_pressed()
	assert_almost_eq(view.speed, 4.0, 0.0001)
	view._on_speed_button_pressed()
	assert_almost_eq(view.speed, 1.0, 0.0001)


## "Pause/step/speed don't alter the outcome, only its pacing" —
## verified at the BoutRunner level already (test_bout_runner.gd); this
## confirms the VIEW's own pacing controls don't touch runner state
## beyond what step()/timer cadence already do: each step_once() call
## advances turns_taken by exactly one, never zero or more than one,
## regardless of speed (this fixture's own combat can finish before 3
## calls — set_speed must not change THAT either).
func test_a_faster_speed_never_skips_or_repeats_a_single_step() -> void:
	var view := BoutView.new()
	add_child_autofree(view)
	var built: Dictionary = _bout()
	view.setup(built.state, built.mission)
	view.set_speed(4.0)

	for i in range(3):
		if view.runner.finished:
			break
		var before: int = view.runner.turns_taken
		view.step_once()
		assert_eq(
			view.runner.turns_taken, before + 1, "step %d must advance by exactly one turn" % i
		)


func test_the_bout_finishing_stops_playback() -> void:
	var view := BoutView.new()
	add_child_autofree(view)
	var built: Dictionary = _bout()
	view.setup(built.state, built.mission)

	var guard := 0
	while not view.runner.finished and guard < 500:
		view.step_once()
		guard += 1

	assert_true(view.runner.finished)
	assert_false(view.playing)
	assert_true(view._timer.is_stopped())
