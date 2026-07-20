extends GutTest

## taskblock-26 (CC, re-diagnosing B2 "skirmisher squares off through
## walls"): split out of test_unit_ai.gd (which was already at the
## file-length cap — the same reason test_damage_resolver_deflect_modes.gd
## split out of test_damage_resolver.gd) — the LOS-engagement-scoring
## regression coverage for `_pick_engagement_position`/`_engagement_score`'s
## `any_reachable_has_los` gate.


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


func _last_move(queue: ActionQueue) -> MoveAction:
	var move: MoveAction = null
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			move = action
	return move


## taskblock-26 (CC, re-diagnosing B2): confirmed on 60 REAL generated
## maps (MapGen), not just this hand-built fixture — a wall/corridor bend
## no single turn's own movement budget can clear left NOT ONE reachable
## cell with real LOS. `NO_LOS_PENALTY`'s own self-cell exemption then
## made "stand still" categorically beat every other candidate (only the
## self cell escaped the penalty), freezing the unit at its own spawn
## turn after turn — the exact "squares off... never takes space" symptom
## B2 was reported against, on a map big enough that one turn can't reach
## LOS at all. A wall tall enough that going around exceeds one turn's
## own movement budget, with the units sharing a row squarely blocked by
## it, reproduces this without needing a whole generated map.
func test_skirmisher_advances_around_a_wall_even_when_no_reachable_cell_has_los_yet() -> void:
	var grid := Grid.new(20, 20)
	for y in range(20):  # a FULLY sealed column -- no reachable cell ever has LOS across it
		grid.set_terrain(Vector2i(8, y), Enums.TerrainType.WALL)
		grid.set_opacity(Vector2i(8, y), 1.0)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 30.0
	var enemy := _armed_unit(&"enemy", Vector2i(19, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	assert_false(
		LoS.has_los(grid, self_unit.cell, enemy.cell), "sanity: the wall blocks the shared row"
	)
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(
		self_unit.cell, self_unit.mp_per_ap() * self_unit.ap
	)
	var any_reachable_has_los := false
	for cell: Vector2i in reachable:
		if LoS.has_los(grid, cell, enemy.cell):
			any_reachable_has_los = true
	assert_false(
		any_reachable_has_los, "sanity: the wall band really is too tall for one turn to clear"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(
		move, "must advance toward the wall even without LOS this turn, never freeze at spawn"
	)
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_lt(
		Grid.distance_chebyshev(destination, enemy.cell),
		Grid.distance_chebyshev(self_unit.cell, enemy.cell),
		"must actually make progress toward the enemy, not just face uselessly at the origin"
	)


## taskblock-26 (CC, re-diagnosing B2): the narrower, direct proof —
## `_engagement_score`'s own self-cell exemption must NOT apply when
## `any_reachable_has_los` is false, so a cell making genuine progress
## outscores standing still even though neither has real LOS. With
## `any_reachable_has_los` true (the ordinary case — some OTHER reachable
## cell really does have LOS), the self cell keeps its exemption exactly
## as before, unchanged from taskblock-26 Pass B2's own original fix.
func test_engagement_score_self_exemption_only_applies_when_some_cell_actually_has_los() -> void:
	var grid := Grid.new(20, 3)
	for x in range(5, 15):
		grid.set_terrain(Vector2i(x, 1), Enums.TerrainType.WALL)
		grid.set_opacity(Vector2i(x, 1), 1.0)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(19, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	var weapon: Part = self_unit.shell.find_part(&"rifle")
	var progress_cell := Vector2i(4, 1)  # closer to preferred range, still behind the same wall
	assert_false(LoS.has_los(grid, self_unit.cell, enemy.cell), "sanity")
	assert_false(LoS.has_los(grid, progress_cell, enemy.cell), "sanity: still behind the wall")

	var self_score_when_nothing_has_los: float = UnitAI._engagement_score(
		self_unit.cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		false
	)
	var progress_score_when_nothing_has_los: float = UnitAI._engagement_score(
		progress_cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		false
	)
	assert_gt(
		progress_score_when_nothing_has_los,
		self_score_when_nothing_has_los,
		"with no LOS cell reachable at all, real progress must outscore the exempted self cell"
	)

	var self_score_when_something_has_los: float = UnitAI._engagement_score(
		self_unit.cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		true
	)
	var progress_score_when_something_has_los: float = UnitAI._engagement_score(
		progress_cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		true
	)
	assert_gt(
		self_score_when_something_has_los,
		progress_score_when_something_has_los,
		"unchanged from Pass B2: the self cell keeps its exemption once some cell truly has LOS"
	)
