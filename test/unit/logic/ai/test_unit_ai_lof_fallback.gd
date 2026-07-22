extends GutTest

## tb33 Pass B (BR32.10): "when no reachable cell has a shot, walk toward one
## that does." Split from `test_unit_ai_engagement_lof.gd` (Pass A's own fire-
## gate/scorer coverage) — this file is specifically the approach-fallback's
## own behavior (`LineOfFire.approach_path`, wired into `_plan_ranged`'s
## `not any_reachable_has_lof` branch), not the scorer it replaces when a shot
## IS reachable this turn.


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
		weapon.weapon_def.max_range = 30.0
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


func _wall_at(grid: Grid, cell: Vector2i) -> void:
	grid.set_terrain(cell, Enums.TerrainType.WALL)
	grid.set_opacity(cell, 1.0)
	grid.blockers[cell] = DataLibrary.get_part(&"wall")


## A concave pocket: a narrow 2-wide, 13-tall channel (x=9/x=11, y=3..16)
## closed at the bottom (y=16) with the enemy inside, near the closed end.
## Reaching any cell with real LOF requires skirting the channel's outer
## wall past the enemy's own row before curving back in from the open top —
## the genuine "moves away before it gets closer" detour a raw per-turn
## distance scorer can't make (that's `_engagement_score`'s own structural
## limit, not this fallback's).
func _concave_pocket() -> Grid:
	var grid := Grid.new(20, 20)
	for x in range(9, 12):
		_wall_at(grid, Vector2i(x, 16))
	for y in range(3, 17):
		_wall_at(grid, Vector2i(9, y))
		_wall_at(grid, Vector2i(11, y))
	return grid


func test_ai_takes_a_step_that_increases_chebyshev_distance_before_it_decreases() -> void:
	var grid := _concave_pocket()
	var self_unit := _armed_unit(&"self_unit", Vector2i(10, 18), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(
		self_unit.cell, self_unit.mp_per_ap() * self_unit.ap
	)
	assert_false(
		UnitAI._any_reachable_has_lof(
			self_unit, enemy, state, reachable, self_unit.shell.find_part(&"rifle")
		),
		"sanity: nothing reachable this turn has a real shot"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")
	var move: MoveAction = null
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			move = action
	assert_not_null(move, "must queue a move toward the nearest cell that would have a shot")

	var distances: Array[int] = []
	for cell: Vector2i in move.path:
		distances.append(Grid.distance_chebyshev(cell, enemy.cell))
	var found_an_increase := false
	for i in range(1, distances.size()):
		if distances[i] > distances[i - 1]:
			found_an_increase = true
	assert_true(
		found_an_increase,
		(
			"the path must include a step that moves farther from the enemy before it curves "
			+ "back in -- the move a greedy per-turn distance scorer never makes: %s" % [distances]
		)
	)
	# The queued path is THIS TURN's own affordable prefix (`truncate_to_budget`)
	# toward the real target, not necessarily the target itself -- the same
	# fallback re-fires next turn to cover the rest (Pass B's own contract).
	# Read the real, untruncated target `nearest_matching` resolved (the same
	# call `LineOfFire.approach_path` makes internally) and confirm THAT cell
	# genuinely has a shot.
	var real_target: Variant = pf.nearest_matching(
		self_unit.cell,
		self_unit.shell.find_part(&"rifle").weapon_def.max_range + LineOfFire.APPROACH_MARGIN,
		func(cell: Vector2i) -> bool:
			return LineOfFire.has_clear_line_of_fire(self_unit, enemy, cell, state)
	)
	assert_true(
		(
			real_target != null
			and LineOfFire.has_clear_line_of_fire(self_unit, enemy, real_target, state)
		),
		"the real approach target (beyond this turn's own budget) must actually have a shot"
	)


func test_the_approach_fallback_is_deterministic_across_repeated_plans() -> void:
	var grid := _concave_pocket()
	var self_unit_a := _armed_unit(&"self_unit", Vector2i(10, 18), 0, &"rifle")
	var enemy_a := _armed_unit(&"enemy", Vector2i(10, 10), 1, &"")
	var state_a := CombatState.new(grid, [self_unit_a, enemy_a], 7)
	var queue_a: ActionQueue = UnitAI.plan_turn(self_unit_a, state_a, null, &"SKIRMISHER")

	var grid_b := _concave_pocket()
	var self_unit_b := _armed_unit(&"self_unit", Vector2i(10, 18), 0, &"rifle")
	var enemy_b := _armed_unit(&"enemy", Vector2i(10, 10), 1, &"")
	var state_b := CombatState.new(grid_b, [self_unit_b, enemy_b], 7)
	var queue_b: ActionQueue = UnitAI.plan_turn(self_unit_b, state_b, null, &"SKIRMISHER")

	var move_a: MoveAction = null
	var move_b: MoveAction = null
	for action: CombatAction in queue_a.actions:
		if action is MoveAction:
			move_a = action
	for action: CombatAction in queue_b.actions:
		if action is MoveAction:
			move_b = action
	assert_not_null(move_a)
	assert_eq(move_a.path, move_b.path, "same seed, same fixture -- the fallback path must match")


## The fallback re-fires turn after turn, walking the rest of the path each
## time, until a reachable cell genuinely has LOF and Pass A's normal fire
## path takes over -- simulated here by replaying `plan_turn` against the
## SAME unit, applying its own queued move and refreshing AP each round
## (the one thing a real per-round turn advance does that matters to
## `_plan_ranged`'s own budget calc), never re-deriving the fallback's own
## pathing logic.
func test_the_approach_fallback_eventually_reaches_a_lof_cell_and_fires() -> void:
	var grid := _concave_pocket()
	var self_unit := _armed_unit(&"self_unit", Vector2i(10, 18), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var fired := false
	for round_index in range(10):
		var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")
		if queue.actions.any(
			func(a: CombatAction) -> bool: return a is AttackAction or a is BurstAction
		):
			fired = true
			break
		var move: MoveAction = null
		for action: CombatAction in queue.actions:
			if action is MoveAction:
				move = action
		assert_not_null(move, "round %d must still be making progress, not stuck" % round_index)
		self_unit.cell = move.path[-1]
		self_unit.ap = self_unit.max_ap

	assert_true(fired, "the fallback must eventually reach a real shot and fire, not loop forever")


## BR32.10's own explicit edge: an enemy with NO reachable LOF cell anywhere
## within the fallback's own search radius must fall through to the existing
## hold/end-turn behavior -- never freeze, crash, or throw on an empty
## `nearest_matching` result.
func test_a_fully_walled_off_enemy_falls_through_to_hold_without_freezing() -> void:
	var grid := Grid.new(20, 20)
	for y in range(20):
		_wall_at(grid, Vector2i(10, y))
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(19, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	assert_false(
		queue.actions.any(
			func(a: CombatAction) -> bool: return a is AttackAction or a is BurstAction
		),
		"a fully sealed enemy must never be fired at"
	)
	assert_true(
		queue.actions.any(
			func(a: CombatAction) -> bool: return a is HoldAction or a is EndTurnAction
		),
		"a hopeless fallback must still end the turn cleanly, not freeze with nothing queued"
	)


## Regression: an ordinary open-field engagement never needs the fallback at
## all -- `_any_reachable_has_lof` is true, so `_plan_ranged`'s normal
## engagement-scoring path handles it exactly as before this pass.
func test_open_field_never_enters_the_approach_fallback() -> void:
	var grid := Grid.new(20, 20)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(19, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(
		self_unit.cell, self_unit.mp_per_ap() * self_unit.ap
	)

	assert_true(
		UnitAI._any_reachable_has_lof(
			self_unit, enemy, state, reachable, self_unit.shell.find_part(&"rifle")
		),
		"an open field always has a reachable clear cell -- the fallback must never trigger"
	)
