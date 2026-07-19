extends GutTest

## taskblock-14 Pass B: UnitAI.plan_turn — pure, deterministic, the same
## action-queue producer a human's own UI would feed through
## CombatState.resolve_until. AGGRESSIVE's own exact-behaviour proof lives
## in test_full_mission.gd (the extraction target itself: same seed, same
## outcome numbers, before and after the extraction).


func _armed_unit(
	id: StringName, cell: Vector2i, squad_id: int, weapon_id: StringName, torso_hp: int = 10
) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = torso_hp
	torso.max_hp = torso_hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	if weapon_id != &"":
		var weapon := Part.new()
		weapon.id = weapon_id
		weapon.hp = 3
		weapon.max_hp = 3
		weapon.attaches_to = [&"GRIP"]
		weapon.requires = {&"TRIGGER": 1}
		weapon.damage = 5.0
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
		torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


func test_plan_turn_is_pure_and_deterministic() -> void:
	var results: Array = []
	for run in range(2):
		var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
		var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"")
		var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 42)

		var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)
		var kinds: Array[String] = []
		for action: CombatAction in queue.actions:
			kinds.append(action.describe())
		results.append(kinds)

	assert_eq(results[0], results[1])


## taskblock-17 Pass B: "an AI unit that ends its turn aiming at an enemy
## faces that enemy" — checked against the REAL composed geometry
## (`BodyProjector.forward_for` on the unit's own resolved
## `Unit.orientation`, compared to the actual cell-to-cell direction),
## never against `FaceAction.orientation_toward` itself: that was the bug
## (`WORLD_FORWARD.angle_to(delta)`, the mirrored rotation convention
## this codebase's own `rotate_by_orientation` deliberately departs
## from) — a test re-deriving its own expected value from the same
## buggy formula would have agreed with it and caught nothing, exactly
## what let this ship. Enemy cells are deliberately off-axis (never due
## north/east/south/west) since the bug's error was 0 degrees dead ahead
## and grew from there.
func test_an_ai_unit_ends_its_turn_facing_the_enemy_it_fired_at() -> void:
	var offsets: Array[Vector2i] = [
		Vector2i(5, 3), Vector2i(-4, 6), Vector2i(-3, -5), Vector2i(6, -2)
	]
	for offset: Vector2i in offsets:
		var self_unit := _armed_unit(&"self_unit", Vector2i(20, 20), 0, &"rifle")
		var enemy := _armed_unit(&"enemy", Vector2i(20, 20) + offset, 1, &"")
		var state := CombatState.new(Grid.new(40, 40), [self_unit, enemy], 3)

		var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)
		state.resolve_until(queue)

		var real_self: Unit = state.find_unit(self_unit.id)
		var forward: Vector2 = BodyProjector.forward_for(real_self.orientation)
		var expected_direction: Vector2 = Vector2(offset).normalized()
		var error_deg: float = rad_to_deg(absf(forward.angle_to(expected_direction)))
		assert_lt(
			error_deg,
			5.0,
			(
				"offset %s: forward %s should point at %s, off by %.1f degrees"
				% [offset, forward, expected_direction, error_deg]
			)
		)


## "COVER_SEEKER prefers a covered cell over an exposed closer one."
func test_cover_seeker_prefers_a_covered_cell_over_an_exposed_closer_one() -> void:
	var grid := Grid.new(10, 5)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 10
	crate.max_hp = 10
	crate.is_destructible = false
	crate.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	# On row 2's own line to the enemy — candidates at (x<5, y=2) read as
	# covered; the self unit's own start cell (off row 2 entirely) does
	# not, so this can't be satisfied by just staying put.
	grid.blockers[Vector2i(5, 2)] = crate

	# Weapon range (6) is short enough that the starting distance (9) is
	# genuinely out of range — COVER_SEEKER must actually reposition,
	# never just fire from an already-good spot.
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_max_range = 6.0
	var enemy := _armed_unit(&"enemy", Vector2i(9, 2), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	assert_false(
		UnitAI.is_covered_from(self_unit.cell, enemy.cell, state, self_unit),
		"sanity: the starting cell itself must not already read as covered"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"COVER_SEEKER")

	var move: MoveAction = null
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			move = action
	assert_not_null(move, "COVER_SEEKER must reposition toward the covered side")
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_true(
		UnitAI.is_covered_from(destination, enemy.cell, state, self_unit),
		"the chosen destination must actually read as covered from the enemy"
	)


func _last_move(queue: ActionQueue) -> MoveAction:
	var move: MoveAction = null
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			move = action
	return move


## taskblock-16 D1: "advance if farther" — out of weapon range AND
## farther than SKIRMISHER's own preferred standoff, so repositioning is
## forced regardless of the "stay and fire" gate (there's nothing to
## fire at from here).
func test_skirmisher_advances_when_out_of_weapon_range_and_farther_than_preferred() -> void:
	var grid := Grid.new(20, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_max_range = 6.0
	var enemy := _armed_unit(&"enemy", Vector2i(15, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(
		move, "a SKIRMISHER out of weapon range and farther than preferred must advance"
	)
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_eq(
		Grid.distance_chebyshev(destination, enemy.cell),
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		"reachable this turn: must converge exactly onto its own preferred standoff"
	)


## taskblock-16 D1: "back off if closer... willing to move away from the
## enemy to open distance." Already well within weapon range — the only
## reason to move at all is the preferred-range gate itself.
func test_skirmisher_retreats_when_standing_closer_than_its_preferred_range() -> void:
	var grid := Grid.new(20, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(10, 1), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_max_range = 15.0
	var enemy := _armed_unit(&"enemy", Vector2i(11, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	var starting_distance: int = Grid.distance_chebyshev(self_unit.cell, enemy.cell)
	assert_lt(
		starting_distance,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		"sanity: must start closer than preferred"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "a SKIRMISHER standing too close must reposition, not just fire")
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_gt(
		Grid.distance_chebyshev(destination, enemy.cell),
		starting_distance,
		"the SKIRMISHER must move AWAY from the enemy to open distance"
	)


## taskblock-16 D1: "a MARKSMAN holds greater standoff" than a
## SKIRMISHER, from an identical starting position/range — the only
## difference between the two calls is `preferred_range`, proving the
## planner really is parameterised, not three copies with different
## constants baked in.
func test_marksman_holds_greater_standoff_than_skirmisher() -> void:
	var skirmisher := _armed_unit(&"skirmisher", Vector2i(0, 1), 0, &"rifle")
	skirmisher.shell.find_part(&"rifle").weapon_max_range = 6.0
	var enemy_a := _armed_unit(&"enemy_a", Vector2i(15, 1), 1, &"")
	var state_a := CombatState.new(Grid.new(20, 3), [skirmisher, enemy_a])

	var marksman := _armed_unit(&"marksman", Vector2i(0, 1), 0, &"rifle")
	marksman.shell.find_part(&"rifle").weapon_max_range = 6.0
	var enemy_b := _armed_unit(&"enemy_b", Vector2i(15, 1), 1, &"")
	var state_b := CombatState.new(Grid.new(20, 3), [marksman, enemy_b])

	var skirmisher_move: MoveAction = _last_move(
		UnitAI.plan_turn(skirmisher, state_a, null, &"SKIRMISHER")
	)
	var marksman_move: MoveAction = _last_move(
		UnitAI.plan_turn(marksman, state_b, null, &"MARKSMAN")
	)
	assert_not_null(skirmisher_move)
	assert_not_null(marksman_move)

	var skirmisher_distance: int = Grid.distance_chebyshev(
		skirmisher_move.path[skirmisher_move.path.size() - 1], enemy_a.cell
	)
	var marksman_distance: int = Grid.distance_chebyshev(
		marksman_move.path[marksman_move.path.size() - 1], enemy_b.cell
	)

	assert_eq(skirmisher_distance, UnitAI.SKIRMISHER_PREFERRED_RANGE)
	assert_eq(marksman_distance, UnitAI.MARKSMAN_PREFERRED_RANGE)
	assert_gt(
		marksman_distance,
		skirmisher_distance,
		"MARKSMAN must hold a greater standoff than SKIRMISHER"
	)


## taskblock-16 D2: "with cover objects present (Pass B), COVER_SEEKER
## moves to a covered cell rather than standing still" — proven here with
## a REAL Pass B field object loaded through DataLibrary (not an ad-hoc
## fixture Part), the actual thing `is_covered_from` reads once cover
## objects are real, placed, blocking geometry rather than a cell scalar.
func test_cover_seeker_relocates_to_a_real_pass_b_cover_object() -> void:
	var grid := Grid.new(10, 5)
	var crate: Part = DataLibrary.get_part(&"crate")
	grid.blockers[Vector2i(5, 2)] = crate

	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_max_range = 6.0
	var enemy := _armed_unit(&"enemy", Vector2i(9, 2), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	assert_false(
		UnitAI.is_covered_from(self_unit.cell, enemy.cell, state, self_unit),
		"sanity: the starting cell itself must not already read as covered"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"COVER_SEEKER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "COVER_SEEKER must actually relocate, not stand still")
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_true(
		UnitAI.is_covered_from(destination, enemy.cell, state, self_unit),
		"the destination must read as covered by the real cover object"
	)


## "a unit with no valid action ends its turn cleanly" — no enemy, no
## mission, nothing to gather/extract, not this unit's landing squad.
func test_a_unit_with_no_valid_action_ends_its_turn_cleanly() -> void:
	var lone_unit := _armed_unit(&"lone_unit", Vector2i(0, 0), 1, &"")
	var state := CombatState.new(Grid.new(5, 5), [lone_unit])

	var queue: ActionQueue = UnitAI.plan_turn(lone_unit, state, null)

	assert_eq(queue.actions.size(), 1)
	assert_true(queue.actions[0] is EndTurnAction)


## "human and AI queues both resolve through the same resolve_until" —
## an AI-produced queue is a plain ActionQueue, resolved exactly the way
## a human-built one would be, no special-cased path.
func test_an_ai_produced_queue_resolves_through_the_normal_resolve_until() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	# Generous HP (test_full_mission.gd's own convention): must survive the
	# AI's own up-to-3-shot volley so resolution actually COMPLETES rather
	# than legitimately aborting mid-queue on a target that died early —
	# a real, correct outcome (docs/09: "the world moved"), just not the
	# one this test is about.
	var enemy := _armed_unit(&"enemy", Vector2i(3, 0), 1, &"", 1000)
	var state := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 7)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)
	var outcome: Dictionary = state.resolve_until(queue)

	assert_eq(outcome.kind, Enums.ResolveOutcome.COMPLETED)
	assert_eq(state.current_unit(), enemy, "the turn must have actually advanced past self_unit")


## An unrecognised playstyle falls back to AGGRESSIVE rather than
## erroring — open StringName vocabulary, never a closed enum.
func test_an_unknown_playstyle_falls_back_to_aggressive() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(3, 0), 1, &"")
	var state_a := CombatState.new(Grid.new(10, 5), [self_unit, enemy], 3)
	var state_b := CombatState.new(
		Grid.new(10, 5),
		[
			_armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle"),
			_armed_unit(&"enemy", Vector2i(3, 0), 1, &"")
		],
		3
	)

	var default_queue: ActionQueue = UnitAI.plan_turn(self_unit, state_a, null)
	var unknown_queue: ActionQueue = UnitAI.plan_turn(
		state_b.units[0], state_b, null, &"SOMETHING_MADE_UP"
	)

	assert_eq(default_queue.actions.size(), unknown_queue.actions.size())
