extends GutTest

## taskblock-25 Pass F (docs/PLAN.md "Phase M — Melee"): melee-defined
## playstyles, finally expressible — PSYCHOTIC (prefers melee, closes to
## minimize distance, never flees) and TURTLE (keeps distance, flees
## rather than melee). Fixtures mirror test_unit_ai.gd's own `_armed_unit`
## almost verbatim, adding a POWER-capable, `&"stab"`-providing fist.


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


## `_armed_unit` plus a bare, POWER-capable fist providing its own stab
## (mirrors test_the_punch.gd's own fixture) and a real `shell_reach` — the
## melee counterpart of `_armed_unit`'s own ranged weapon.
func _melee_capable_unit(
	id: StringName, cell: Vector2i, squad_id: int, shell_reach: float, with_ranged_weapon: bool
) -> Unit:
	var unit: Unit = _armed_unit(
		id, cell, squad_id, &"%s_rifle" % id if with_ranged_weapon else &""
	)

	var fist := Part.new()
	fist.id = StringName("%s_fist" % id)
	fist.hp = 5
	fist.max_hp = 5
	fist.attaches_to = [&"WRIST"]
	fist.capabilities = [&"POWER"]
	fist.provides_actions = [&"stab"]
	fist.damage = 2.0
	fist.ap_cost = 1
	fist.scatter = [Ring.new(0.1, 1.0)]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = fist
	unit.shell.root.sockets.append(wrist)

	unit.shell.shell_reach = shell_reach
	return unit


func _last_move(queue: ActionQueue) -> MoveAction:
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			return action
	return null


## docs/PLAN.md Pass F: "prefers melee, closes to minimize distance" —
## adjacent to a living enemy, PSYCHOTIC must swing its fist rather than
## its own equipped rifle.
func test_psychotic_prefers_a_strike_over_a_shot_when_in_reach() -> void:
	var striker: Unit = _melee_capable_unit(&"striker", Vector2i(0, 0), 0, 1.5, true)
	var enemy := _armed_unit(&"enemy", Vector2i(1, 0), 1, &"enemy_rifle")
	var state := CombatState.new(Grid.new(10, 10), [striker, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(striker, state, null, &"PSYCHOTIC")

	var stabbed := false
	for action: CombatAction in queue.actions:
		assert_false(action is AttackAction, "psychotic in reach must never prefer its own gun")
		if action is StabAction:
			stabbed = true
	assert_true(stabbed, "psychotic in reach must land a real melee strike")


## "Closes to minimize distance" — out of melee reach entirely, PSYCHOTIC
## moves closer rather than opening fire with its own gun from range.
func test_psychotic_closes_distance_instead_of_firing_from_range() -> void:
	var striker: Unit = _melee_capable_unit(&"striker", Vector2i(0, 0), 0, 1.5, true)
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"enemy_rifle")
	var state := CombatState.new(Grid.new(10, 10), [striker, enemy])
	var before_distance: int = Grid.distance_chebyshev(striker.cell, enemy.cell)

	var queue: ActionQueue = UnitAI.plan_turn(striker, state, null, &"PSYCHOTIC")

	for action: CombatAction in queue.actions:
		assert_false(action is AttackAction, "psychotic must not open fire with its own gun")
	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "psychotic out of melee reach must move closer")
	var after_cell: Vector2i = move.path[move.path.size() - 1]
	assert_lt(Grid.distance_chebyshev(after_cell, enemy.cell), before_distance)


## docs/PLAN.md Pass F: "would rather flee than melee" — adjacent to a
## living enemy, TURTLE runs rather than swinging at all.
func test_turtle_flees_rather_than_melee() -> void:
	var striker: Unit = _melee_capable_unit(&"striker", Vector2i(0, 0), 0, 1.5, true)
	var enemy := _armed_unit(&"enemy", Vector2i(1, 0), 1, &"enemy_rifle")
	var state := CombatState.new(Grid.new(10, 5), [striker, enemy])
	var mission := MissionState.new(RunState.new(), state)
	mission.team_extraction_cells = {0: [Vector2i(9, 4)]}

	var queue: ActionQueue = UnitAI.plan_turn(striker, state, mission, &"TURTLE")

	for action: CombatAction in queue.actions:
		assert_false(action is StabAction, "turtle must never choose melee")
		assert_false(action is AttackAction, "fleeing, not fighting")
	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "turtle adjacent to a living enemy must flee")
	assert_eq(move.path[move.path.size() - 1], Vector2i(9, 4))


## A TURTLE that is NOT adjacent to anything behaves like an ordinary
## cover-weighting planner — the flee branch is adjacency-gated, not a
## blanket "TURTLE always flees."
func test_turtle_does_not_flee_when_not_adjacent_to_an_enemy() -> void:
	var striker: Unit = _melee_capable_unit(&"striker", Vector2i(0, 0), 0, 1.5, true)
	var enemy := _armed_unit(&"enemy", Vector2i(6, 0), 1, &"enemy_rifle")
	var state := CombatState.new(Grid.new(10, 10), [striker, enemy])
	var mission := MissionState.new(RunState.new(), state)
	mission.team_extraction_cells = {0: [Vector2i(9, 9)]}

	var queue: ActionQueue = UnitAI.plan_turn(striker, state, mission, &"TURTLE")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "sanity: a turtle far from the enemy still repositions")
	assert_ne(
		move.path[move.path.size() - 1],
		Vector2i(9, 9),
		"not adjacent to anything — must not be fleeing toward extraction"
	)
