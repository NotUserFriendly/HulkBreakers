extends GutTest

## taskblock-18 D3: "a step out is a gamble, not a safe poke — the firing step
## exposes the unit; if an overwatcher drops the stepper mid-step-out, it dies
## in the firing cell, the return never happens." No new resolver
## plumbing needed for this (confirmed by design research): a step out's
## Move(->firing)+Attack+Move(->origin) queue is ONE ordinary ActionQueue,
## and CombatState.resolve_until()'s own existing re-validation rule
## (taskblock-06 D: stop the instant the next step is no longer legal,
## Overwatch.check_trigger plugged in as its mid_move_hook) already means
## a triggered overwatch freezes the outbound move before the queued
## Attack/return Move are ever reached — the same mechanism a plain
## queued move already uses, no step-out-specific interrupt code required.
## This test is the proof.


func _overwatcher(cell: Vector2i, orientation: float, squad_id: int, damage: float) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.damage = damage
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.0, 0.01)]  # effectively dead-center, for a reliable kill in tests
	pistol.requires = {&"TRIGGER": 1}
	pistol.weapon_def = WeaponDef.new()
	pistol.weapon_def.max_range = 15.0

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)
	unit.orientation = orientation
	return unit


func _stepper(cell: Vector2i, squad_id: int, torso_hp: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 1.0, 0.0), Vector3(0.5, 1.0, 0.5))]

	var weapon := Part.new()
	weapon.id = &"rifle"
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 15.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = &"hand"
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


## Verified geometry (matches test_step_out_planner.gd's own _covered_scene):
## a blocker at (3,1) covers the stepper's origin (3,0) from a target at
## (3,9); (4,0) and (2,0) are both legal, exposed step-out cells. A hostile
## overwatcher at (8,0) — off the stepper-target sightline entirely, so it
## never itself reads as "cover" blocking either candidate — facing west
## with a short 5-tile weapon range triggers on (4,0) specifically
## (distance 4) but not (2,0) (distance 6, out of range). The step out is
## deliberately built against the UNSAFE cell, bypassing
## assemble_for_shoot's own safest-pick, to exercise the interrupt itself
## rather than the cell-choice logic (already covered separately).
func test_a_stepper_killed_mid_step_out_freezes_in_the_firing_cell_and_never_returns() -> void:
	var grid := Grid.new(10, 10)
	var blocker := Part.new()
	blocker.id = &"cover"
	blocker.is_destructible = false
	blocker.material = &"hull_plate"
	blocker.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.blockers[Vector2i(3, 1)] = blocker

	var stepper := _stepper(Vector2i(3, 0), 0, 2)
	var target := _stepper(Vector2i(3, 9), 1, 10)
	var overwatcher := _overwatcher(
		Vector2i(8, 0), BodyProjector.orientation_for(Vector2(-1, 0)), 1, 20.0
	)
	overwatcher.shell.find_part(&"pistol").weapon_def.max_range = 5.0
	var state := CombatState.new(grid, [stepper, target, overwatcher], 7)
	overwatcher.overwatch_weapon_id = &"pistol"
	stepper.ap = 6

	assert_true(
		StepOutPlanner.is_legal_step_out(state, stepper, Vector2i(3, 0), Vector2i(4, 0), target),
		"sanity: the chosen firing cell must actually be a legal step out"
	)
	assert_eq(
		Overwatch.would_trigger_at(state, stepper, Vector2i(4, 0)).size(),
		1,
		"sanity: the overwatcher must actually threaten this specific firing cell"
	)

	var queue := ActionQueue.new(stepper)
	var assembled: bool = StepOutPlanner.build_triple(
		queue, state, stepper, &"rifle", target, Vector2i(3, 0), Vector2i(4, 0)
	)
	assert_true(
		assembled, "sanity: the triple must assemble legally before the interrupt is tested"
	)
	assert_eq(queue.actions.size(), 3)

	var outcome: Dictionary = state.resolve_until(queue, Overwatch.check_trigger)

	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED)
	assert_eq(outcome.reason, &"mid_move_interrupt")
	assert_eq(
		stepper.cell, Vector2i(4, 0), "frozen in the firing cell, never reaching the return leg"
	)
	# A dead-center 20-damage hit on the torso's own 2 hp destroys the
	# torso outright — a real lethal-caliber hit landed. `unit.alive`
	# itself stays true a beat longer (Overwatch._fire's own rule: the
	# WHOLE unit only dies once every part is gone, and this single shot
	# never touched the stepper's own separate hand/weapon parts) — that's
	# damage-mechanics territory already covered elsewhere, not what this
	# interrupt test is about.
	assert_true(stepper.shell.root.hp <= 0, "the torso itself must be destroyed by the hit")
	assert_eq(
		overwatcher.overwatch_weapon_id,
		&"",
		"the overwatch that triggered must actually have fired, not just frozen the move for free"
	)


## The same shape, but survivable — proves the freeze/no-return outcome
## doesn't depend on death specifically: ANY triggered overwatch
## unconditionally freezes the move (MoveAction.apply_stepwise's own
## mid_move_hook contract), independent of whether that shot happens to
## kill.
func test_a_stepper_who_survives_the_trigger_still_freezes_and_never_returns() -> void:
	var grid := Grid.new(10, 10)
	var blocker := Part.new()
	blocker.id = &"cover"
	blocker.is_destructible = false
	blocker.material = &"hull_plate"
	blocker.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	grid.blockers[Vector2i(3, 1)] = blocker

	var stepper := _stepper(Vector2i(3, 0), 0, 1000)  # generous — must survive to prove the point
	var target := _stepper(Vector2i(3, 9), 1, 10)
	var overwatcher := _overwatcher(
		Vector2i(8, 0), BodyProjector.orientation_for(Vector2(-1, 0)), 1, 1.0
	)
	overwatcher.shell.find_part(&"pistol").weapon_def.max_range = 5.0
	var state := CombatState.new(grid, [stepper, target, overwatcher], 7)
	overwatcher.overwatch_weapon_id = &"pistol"
	stepper.ap = 6

	var queue := ActionQueue.new(stepper)
	assert_true(
		StepOutPlanner.build_triple(
			queue, state, stepper, &"rifle", target, Vector2i(3, 0), Vector2i(4, 0)
		)
	)

	var outcome: Dictionary = state.resolve_until(queue, Overwatch.check_trigger)

	assert_true(stepper.alive, "sanity: a generous torso against 1 damage must survive")
	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED)
	assert_eq(stepper.cell, Vector2i(4, 0), "still frozen in the firing cell despite surviving")
