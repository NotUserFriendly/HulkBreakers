extends GutTest

## taskblock-46 Pass C: **a unit that knows of nobody has something to do.**
##
## `BR45.03`'s named mechanism: every combat action gated on `enemy_known` and every
## mission action on `is_player_squad`, so a non-player squad that had seen nobody
## matched neither gate and was offered nothing at all — observed as `nothing over
## 488 candidates` on consecutive turns, then a shot the instant the other squad
## came into view. A squad that never moves never closes, and the bout runs to the
## cap. That is the `TERMINATED` shape the completion regression is made of.
##
## **One verb per unit is the diagnostic, not just scoping.** Each verb is a
## precondition on an ordinary utility action, so exactly one is ever offered to a
## given unit. If patrol is broken, only patrolling units misbehave and the failure
## names a verb rather than "the search behaviour" — which is why every test below
## isolates one verb instead of asserting over all four at once.

const AGGRESSIVE_PROFILE := &"aggressive"


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _armed_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
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


## A blind non-player unit: squad 1, restricted view, a wall between it and the
## only other unit on the board. Exactly the situation that produced nothing.
func _blind_enemy(behaviour: StringName) -> Dictionary:
	var grid: Grid = GridFixture.flat(24, 16)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(11, y))
	var hunter: Unit = _armed_unit(&"hunter", Vector2i(18, 8), 1)
	var other: Unit = _armed_unit(&"other", Vector2i(2, 8), 0)
	hunter.search_behaviour = behaviour
	var state := CombatState.new(grid, [hunter, other])
	state.force_current_unit(hunter.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	return {"state": state, "hunter": hunter, "view": view, "grid": grid}


func _shape(queue: ActionQueue) -> Array[String]:
	var shape: Array[String] = []
	for action: CombatAction in queue.actions:
		shape.append(action.get_script().get_global_name())
	return shape


# --- the hole is filled -------------------------------------------------------


## **The headline.** Asserted as a non-zero count of OFFERED candidates rather than
## as "it moved", because `nothing over 488 candidates` was the observed symptom —
## the candidates existed, none of them were on offer.
func test_a_unit_that_knows_of_nobody_has_an_action_available() -> void:
	for behaviour: StringName in [&"ROAM", &"HUNT", &"PUTTER", &"PATROL"]:
		var bout: Dictionary = _blind_enemy(behaviour)
		var context: UtilityContext = UtilityContext.build(bout.hunter, bout.view)
		assert_null(context.target, "sanity: %s unit genuinely knows of no enemy" % behaviour)

		var offered := 0
		for action: UtilityActionDef in DataLibrary.utility_actions_pool():
			for cell: Vector2i in context.candidate_cells:
				if UtilityScorer.preconditions_hold(action, context.predicates_for(cell)):
					offered += 1
					break
		gut.p(
			(
				"%s: %d action(s) offered over %d cells"
				% [behaviour, offered, context.candidate_cells.size()]
			)
		)
		assert_gt(offered, 0, "%s must have something to do" % behaviour)


## And it actually goes somewhere — the hole was a bout that never closed, so the
## end state that matters is movement, not merely a populated candidate list.
func test_a_blind_enemy_unit_actually_moves() -> void:
	for behaviour: StringName in [&"ROAM", &"HUNT", &"PUTTER", &"PATROL"]:
		var bout: Dictionary = _blind_enemy(behaviour)
		var queue: ActionQueue = await UtilityPlanner.plan_turn(
			bout.hunter, bout.view, null, AGGRESSIVE_PROFILE
		)
		gut.p("%s: %s" % [behaviour, _shape(queue)])
		assert_has(_shape(queue), "MoveAction", "%s must leave its cell" % behaviour)


# --- one verb per unit --------------------------------------------------------


## Exactly one search verb is ever offered, and it is the one assigned. This is what
## makes a broken verb attributable rather than a property of "search".
func test_each_verb_is_offered_only_to_the_unit_assigned_it() -> void:
	var verbs: Array[StringName] = [&"roam", &"hunt", &"putter", &"patrol"]
	for behaviour: StringName in [&"ROAM", &"HUNT", &"PUTTER", &"PATROL"]:
		var bout: Dictionary = _blind_enemy(behaviour)
		var context: UtilityContext = UtilityContext.build(bout.hunter, bout.view)
		var predicates: Dictionary = context.predicates_for(bout.hunter.cell + Vector2i(1, 0))

		var live: Array[StringName] = []
		for verb: StringName in verbs:
			for action: UtilityActionDef in DataLibrary.utility_actions_pool():
				if action.id != verb:
					continue
				if UtilityScorer.preconditions_hold(action, predicates):
					live.append(verb)
		assert_eq(
			live,
			[String(behaviour).to_lower()] as Array[StringName],
			"%s must offer exactly its own verb" % behaviour
		)


## The search verbs are gated on knowing nobody, so a unit that CAN see is back to
## fighting — searching must not compete with a shot.
func test_search_stops_being_offered_once_an_enemy_is_known() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var hunter: Unit = _armed_unit(&"hunter", Vector2i(4, 8), 1)
	var seen: Unit = _armed_unit(&"seen", Vector2i(12, 8), 0)
	var state := CombatState.new(grid, [hunter, seen])
	state.force_current_unit(hunter.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
	var view: WorldView = WorldView.full(state)
	view.restricted = true

	var context: UtilityContext = UtilityContext.build(hunter, view)
	assert_not_null(context.target, "sanity: it can see the other unit")

	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if action.id not in [&"roam", &"hunt", &"putter", &"patrol"]:
			continue
		for cell: Vector2i in context.candidate_cells:
			assert_false(
				UtilityScorer.preconditions_hold(action, context.predicates_for(cell)),
				"%s must not be offered while an enemy is known" % action.id
			)


# --- patrol ------------------------------------------------------------------


## **Oldest visit wins, and that is the whole scheduling rule.** The failure this
## guards against is the one an advance-the-index scheme produces: two points
## alternating while a third is never reached.
func test_patrol_visits_every_point_rather_than_alternating_two() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	var unit: Unit = _armed_unit(&"walker", Vector2i(12, 8), 0)
	unit.patrol_points = [Vector2i(4, 4), Vector2i(20, 4), Vector2i(12, 14)]

	var chosen: Array[Vector2i] = []
	for round_number in range(6):
		var target: Variant = SearchRoute.next_point(unit)
		assert_not_null(target, "a unit with points always has a next one")
		chosen.append(target)
		# Simulate arriving there.
		unit.cell = target
		SearchRoute.record_arrival(unit, round_number)

	gut.p("patrol order: %s" % [chosen])
	for point: Vector2i in unit.patrol_points:
		assert_has(chosen, point, "every point must be visited")
	assert_eq(
		chosen.slice(0, 3).size(),
		3,
		"and all three come up before any repeats — oldest-first cycles them"
	)
	var first_three: Array[Vector2i] = chosen.slice(0, 3)
	for point: Vector2i in unit.patrol_points:
		assert_has(first_three, point, "no point waits while two others alternate")


## A never-visited point outranks a visited one, which is what makes "every point
## gets visited" fall out rather than needing to be arranged.
func test_a_never_visited_point_outranks_a_visited_one() -> void:
	var unit: Unit = _armed_unit(&"walker", Vector2i(0, 0), 0)
	unit.patrol_points = [Vector2i(4, 4), Vector2i(9, 9)]
	unit.patrol_visits[Vector2i(4, 4)] = 5

	assert_eq(SearchRoute.next_point(unit), Vector2i(9, 9))


## Routes are derived from the map with no RNG, so the same map lays out the same
## route — `docs/00`'s same-seed-same-battle rule reaches this too.
func test_route_generation_is_deterministic() -> void:
	var grid: Grid = GridFixture.flat(24, 16)

	var first: Array[Vector2i] = SearchRoute.generate(grid, Vector2i(12, 8))
	var second: Array[Vector2i] = SearchRoute.generate(grid, Vector2i(12, 8))

	assert_eq(first, second)
	assert_gt(first.size(), 1, "an open map supports a real route")


## Points must be spread, not clustered — a route of three neighbours is pacing.
func test_route_points_are_spread_apart() -> void:
	var grid: Grid = GridFixture.flat(24, 16)

	var points: Array[Vector2i] = SearchRoute.generate(grid, Vector2i(12, 8))

	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			assert_gt(
				Grid.distance_chebyshev(points[i], points[j]),
				SearchRoute.ARRIVAL_RADIUS,
				"two points close enough to count as the same place are one point"
			)


## A unit boxed into a corner has nowhere to patrol, and that is an empty route
## rather than an error — the caller falls through to having no patrol action
## offered, which the other verbs and the turn-end backstop already cover.
func test_a_unit_with_nowhere_to_go_gets_an_empty_route() -> void:
	var grid: Grid = GridFixture.flat(24, 16)
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		GridFixture.place_wall(grid, cell)

	assert_eq(SearchRoute.generate(grid, Vector2i(0, 0)), [] as Array[Vector2i])
