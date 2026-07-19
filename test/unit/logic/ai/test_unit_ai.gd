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
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 6.0
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
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 6.0
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
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 15.0
	# taskblock-19 Pass E: distance 3, not adjacent (1) — this test is
	# about the preferred-range retreat pull in general, not about
	# suppression/opportunity-attack behavior at literal melee range,
	# which now has its own real cost that would otherwise fight this one.
	var enemy := _armed_unit(&"enemy", Vector2i(13, 1), 1, &"")
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
	skirmisher.shell.find_part(&"rifle").weapon_def.max_range = 6.0
	var enemy_a := _armed_unit(&"enemy_a", Vector2i(15, 1), 1, &"")
	var state_a := CombatState.new(Grid.new(20, 3), [skirmisher, enemy_a])

	var marksman := _armed_unit(&"marksman", Vector2i(0, 1), 0, &"rifle")
	marksman.shell.find_part(&"rifle").weapon_def.max_range = 6.0
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


## taskblock-19 Pass C3: "a unit in max-but-not-effective range moves
## closer to reach effective" — the weapon's own authored effective_range
## supersedes the flat, playstyle-level preferred_range once it's real
## data, not a flagged guess. No cover in this scene at all: proves the
## DISTANCE TARGET changed, independent of the cover-vs-distance tradeoff
## (covered separately below).
func test_effective_range_supersedes_the_flat_preferred_range_standoff() -> void:
	var grid := Grid.new(20, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 15.0
	self_unit.shell.find_part(&"rifle").weapon_def.effective_range = 3.0
	assert_ne(
		3, UnitAI.SKIRMISHER_PREFERRED_RANGE, "sanity: distinct from the flat playstyle standoff"
	)
	var enemy := _armed_unit(&"enemy", Vector2i(15, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "must reposition toward its own weapon's effective range")
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_eq(
		Grid.distance_chebyshev(destination, enemy.cell),
		3,
		"converges on effective_range, not SKIRMISHER_PREFERRED_RANGE"
	)


## taskblock-19 Pass C3: "...unless there's no cover available, in which
## case it holds and takes the degraded shot rather than exposing itself."
## Cover only exists FARTHER than effective_range here — COVER_SEEKER must
## still prefer the covered-but-degraded cell over an uncovered one right
## at effective_range, the same cover-dominance
## `test_cover_seeker_prefers_a_covered_cell_over_an_exposed_closer_one`
## already proves, now confirmed to survive the new distance target too.
func test_ai_holds_a_covered_degraded_position_over_an_exposed_effective_range_one() -> void:
	var grid := Grid.new(10, 5)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 10
	crate.max_hp = 10
	crate.is_destructible = false
	crate.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	# Same geometry as the existing cover test: covered cells sit at
	# (x<5, y=2), distance 5-9 from the enemy — all farther than the
	# effective_range=2 set below.
	grid.blockers[Vector2i(5, 2)] = crate

	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 15.0
	self_unit.shell.find_part(&"rifle").weapon_def.effective_range = 2.0
	var enemy := _armed_unit(&"enemy", Vector2i(9, 2), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"COVER_SEEKER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move, "must still reposition toward cover, not freeze")
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_true(
		UnitAI.is_covered_from(destination, enemy.cell, state, self_unit),
		"holds a covered-but-degraded position rather than exposing itself for a better shot"
	)


## taskblock-19 Pass C3: "a unit with a min_range only closes inside it if
## forced; it prefers to fire from >= min." The weapon's own
## effective_range (1.0) would otherwise pull the unit inside its own
## min_range (3.0) — the penalty must override that pull when a >= min
## cell is reachable too.
func test_ai_avoids_closing_inside_its_own_min_range() -> void:
	var grid := Grid.new(20, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var rifle: Part = self_unit.shell.find_part(&"rifle")
	rifle.weapon_def.max_range = 15.0
	rifle.weapon_def.effective_range = 1.0
	rifle.weapon_def.min_range = 3.0
	var enemy := _armed_unit(&"enemy", Vector2i(15, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move)
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_gte(
		Grid.distance_chebyshev(destination, enemy.cell),
		3,
		"the min_range penalty must beat the pull toward effective_range=1"
	)
	var shot: AttackAction = null
	for action: CombatAction in queue.actions:
		if action is AttackAction:
			shot = action
	assert_not_null(shot, "staying at/beyond min_range is what makes the shot legal at all")


## taskblock-19 Pass C3: "...unless forced" — when every reachable cell
## sits inside min_range, a dud-capable weapon (legal under min_range,
## see RangeModel.is_dud) must still fire from the least-bad reachable
## cell rather than doing nothing, the same posture ALLY_BLOCKED_PENALTY's
## own "least-bad cell still wins" already has for a blocked firing line.
## (A non-dud weapon has no such move: firing under its own min_range is
## flatly illegal, so "forced" there just means it correctly holds fire —
## a positioning preference can never make an illegal shot legal.)
func test_ai_fires_from_inside_min_range_when_forced_and_the_weapon_duds_instead_of_blocking(
) -> void:
	var grid := Grid.new(10, 3)
	# Wall off every neighbor of (1,1) but the enemy's own (occupied,
	# already-unwalkable) cell — Pathfinder.reachable always includes the
	# origin itself, so this boxes the unit into exactly one candidate.
	for cell: Vector2i in [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(1, 2),
		Vector2i(2, 2)
	]:
		grid.set_terrain(cell, Enums.TerrainType.WALL)
	var self_unit := _armed_unit(&"self_unit", Vector2i(1, 1), 0, &"rifle")
	var rifle: Part = self_unit.shell.find_part(&"rifle")
	rifle.weapon_def.max_range = 15.0
	rifle.weapon_def.min_range = 5.0
	rifle.weapon_def.min_range_failure = &"dud"
	var enemy := _armed_unit(&"enemy", Vector2i(2, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	assert_lt(
		Grid.distance_chebyshev(self_unit.cell, enemy.cell),
		5,
		"sanity: the only reachable cell is already inside min_range"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var shot: AttackAction = null
	for action: CombatAction in queue.actions:
		if action is AttackAction:
			shot = action
	assert_not_null(shot, "forced inside min_range on a dud-capable weapon, it must still fire")


## taskblock-19 Pass E: "treats adjacent to an enemy with a long gun as
## bad (won't close if it disarms itself)." effective_range=1.0 pulls the
## AI to want to touch the enemy — SUPPRESSION_PENALTY must stop it one
## cell short instead, at distance 2, where the two-handed weapon still
## fires.
func test_ai_avoids_closing_to_adjacency_with_a_two_handed_weapon_equipped() -> void:
	var grid := Grid.new(20, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var rifle: Part = self_unit.shell.find_part(&"rifle")
	rifle.weapon_def.max_range = 15.0
	rifle.weapon_def.effective_range = 1.0
	rifle.weapon_def.two_handed = true
	var enemy := _armed_unit(&"enemy", Vector2i(10, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(move)
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_eq(
		Grid.distance_chebyshev(destination, enemy.cell),
		2,
		"stops one cell short of adjacency rather than disarming itself"
	)
	var shot: AttackAction = null
	for action: CombatAction in queue.actions:
		if action is AttackAction:
			shot = action
	assert_not_null(shot, "distance 2 is not suppressed, so the two-handed weapon can still fire")


## taskblock-19 Pass E: "treats leaving an adjacent tile as costly (expects
## the free hit)." Starting adjacent (distance 1) to its only enemy, with
## a SHORT weapon (never suppressed, so staying and firing is always
## legal) whose effective_range (2.0) would otherwise pull the AI one
## cell farther out — OPPORTUNITY_ATTACK_PENALTY must outweigh that
## marginal 1-point distance gain and keep it from moving at all.
func test_ai_weights_leaving_adjacency_as_costly() -> void:
	var grid := Grid.new(10, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(5, 1), 0, &"pistol")
	var pistol: Part = self_unit.shell.find_part(&"pistol")
	pistol.weapon_def.max_range = 15.0
	pistol.weapon_def.effective_range = 2.0
	var enemy := _armed_unit(&"enemy", Vector2i(6, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	assert_eq(Grid.distance_chebyshev(self_unit.cell, enemy.cell), 1, "sanity: starts adjacent")

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	assert_null(
		_last_move(queue),
		"the marginal distance gain from moving is not worth the opportunity attack"
	)
	var shot: AttackAction = null
	for action: CombatAction in queue.actions:
		if action is AttackAction:
			shot = action
	assert_not_null(shot, "it still engages from where it started")


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
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 6.0
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


## taskblock17-1 Pass B: "the AI has no line-of-fire safety" — a queued
## shot must never fire straight through a living ally standing between
## muzzle and target. Ample open room and MP: the AI must find SOME clear
## firing position rather than shooting blind from where it started.
func test_an_ai_repositions_rather_than_firing_through_an_ally_in_the_line() -> void:
	var grid := Grid.new(20, 20)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"rifle")
	var ally := _armed_unit(&"ally", Vector2i(5, 10), 0, &"")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, ally, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	var shot: AttackAction = null
	for action: CombatAction in queue.actions:
		if action is AttackAction:
			shot = action
	assert_not_null(shot, "plenty of room to find a clear shot — must not just hold fire here")

	var fired_from: Vector2i = self_unit.cell
	var move: MoveAction = _last_move(queue)
	if move != null:
		fired_from = move.path[move.path.size() - 1]

	var plane: Array[Region] = ShotPlane.build(
		Vector2(fired_from.x, fired_from.y), Vector2(enemy.cell - fired_from).normalized(), state
	)
	var hit: Region = ShotPlane.resolve_projectile(plane, ShotPlane.center_of(plane, enemy))
	assert_not_null(hit)
	assert_ne(hit.body, ally, "the chosen firing position must not still have the ally in the way")


## taskblock17-1 Pass B: "if none is reachable this turn, hold fire." A
## 1-wide walled corridor leaves every reachable cell exactly collinear
## with the ally (blocked by its own occupied cell before it can even
## pass), so there is genuinely no clear cell to reposition to.
func test_an_ai_holds_fire_when_no_reachable_cell_clears_the_ally() -> void:
	var grid := Grid.new(20, 3)
	for x in range(20):
		grid.set_terrain(Vector2i(x, 0), Enums.TerrainType.WALL)
		grid.set_terrain(Vector2i(x, 2), Enums.TerrainType.WALL)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var ally := _armed_unit(&"ally", Vector2i(5, 1), 0, &"")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, ally, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	for action: CombatAction in queue.actions:
		assert_false(
			action is AttackAction, "walled into the ally's own line — must hold fire, not shoot"
		)


## taskblock-19 Pass F: "the AI holds when its best option is wait for an
## ally to move first" — the exact scenario above (walled into the ally's
## own firing line, nothing else to do) is precisely that case: the spot
## might clear up once the ally has actually moved.
func test_an_ai_holds_rather_than_just_facing_when_walled_into_the_allys_line() -> void:
	var grid := Grid.new(20, 3)
	for x in range(20):
		grid.set_terrain(Vector2i(x, 0), Enums.TerrainType.WALL)
		grid.set_terrain(Vector2i(x, 2), Enums.TerrainType.WALL)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var ally := _armed_unit(&"ally", Vector2i(5, 1), 0, &"")
	var enemy := _armed_unit(&"enemy", Vector2i(10, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, ally, enemy])

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	var held: bool = false
	for action: CombatAction in queue.actions:
		if action is HoldAction:
			held = true
	assert_true(held, "must hold rather than just face uselessly")
	assert_true(HoldAction.new(self_unit).is_legal(state), "sanity: holding really was legal here")


## taskblock17-1 Pass B: "friendly fire still mechanically possible — the
## check is AI choice, not a resolution block." The shot-plane geometry
## AttackAction/DamageResolver actually resolve against never special-
## cases squad membership: the only exclusion resolution itself ever
## applies is the shooter's own body (the same one `AttackAction.apply()`
## and `_ally_in_firing_line` both need), never anything squad-based.
func test_the_shot_plane_itself_does_not_special_case_squad_membership() -> void:
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"rifle")
	var ally := _armed_unit(&"ally", Vector2i(2, 10), 0, &"")
	var enemy := _armed_unit(&"enemy", Vector2i(4, 10), 1, &"")
	var state := CombatState.new(Grid.new(10, 20), [self_unit, ally, enemy])

	var origin := Vector2(self_unit.cell.x, self_unit.cell.y)
	var direction := Vector2(enemy.cell - self_unit.cell).normalized()
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)
	var downrange: Array[Region] = plane.filter(
		func(region: Region) -> bool: return region.body != self_unit
	)
	var hit: Region = ShotPlane.resolve_projectile(downrange, ShotPlane.center_of(plane, enemy))

	assert_not_null(hit)
	assert_eq(
		hit.body, ally, "resolution itself still hits whatever's in the way — friendly or not"
	)


## taskblock17-1 Pass C: walls all 8 neighbours of `cell` — nothing can
## ever path adjacent to it, sealing it off entirely regardless of
## movement budget.
func _seal_off(grid: Grid, cell: Vector2i) -> void:
	for offset: Vector2i in [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1)
	]:
		grid.set_terrain(cell + offset, Enums.TerrainType.WALL)


## taskblock17-1 Pass C: "chebyshev nearest ignores walls" — a bot fixated
## on the closer-as-the-crow-flies but fully sealed-off enemy would fail
## to path there every turn and freeze facing the wall forever. Must
## target and actually move toward the farther but reachable enemy
## instead — "moves toward the nearest reachable, doesn't freeze facing
## a wall."
func test_targets_and_moves_toward_a_reachable_enemy_over_a_closer_sealed_off_one() -> void:
	var grid := Grid.new(20, 20)
	_seal_off(grid, Vector2i(2, 2))

	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	# Short range: `reachable_enemy` starts well out of weapon range, so
	# the AI is forced to actually reposition rather than firing from
	# where it stands — the thing this test needs to see happen.
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 6.0
	var unreachable_enemy := _armed_unit(&"unreachable", Vector2i(2, 2), 1, &"")
	var reachable_enemy := _armed_unit(&"reachable", Vector2i(15, 15), 1, &"")
	var state := CombatState.new(grid, [self_unit, unreachable_enemy, reachable_enemy])
	assert_lt(
		Grid.distance_chebyshev(self_unit.cell, unreachable_enemy.cell),
		Grid.distance_chebyshev(self_unit.cell, reachable_enemy.cell),
		"sanity: the sealed-off enemy really is the closer one as the crow flies"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	var move: MoveAction = _last_move(queue)
	assert_not_null(
		move, "must reposition toward the reachable enemy, never freeze facing the wall"
	)
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_lt(
		Grid.distance_chebyshev(destination, reachable_enemy.cell),
		Grid.distance_chebyshev(self_unit.cell, reachable_enemy.cell),
		"must actually move toward the reachable enemy"
	)


## taskblock17-1 Pass C: same seed, same walled layout, same outcome —
## the reachability fallback is deterministic, not incidentally stable.
func test_reachable_enemy_targeting_is_deterministic() -> void:
	var results: Array = []
	for run in range(2):
		var grid := Grid.new(20, 20)
		_seal_off(grid, Vector2i(2, 2))
		var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
		self_unit.shell.find_part(&"rifle").weapon_def.max_range = 30.0
		var state := CombatState.new(
			grid,
			[
				self_unit,
				_armed_unit(&"unreachable", Vector2i(2, 2), 1, &""),
				_armed_unit(&"reachable", Vector2i(15, 15), 1, &"")
			],
			11
		)
		var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)
		var kinds: Array[String] = []
		for action: CombatAction in queue.actions:
			kinds.append(action.describe())
		results.append(kinds)

	assert_eq(results[0], results[1])


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


## taskblock-18 D2: "shared AI and player path — one implementation."
## Geometry verified live: a real WALL (opacity, not just a blocker —
## AttackAction.is_legal() only ever checks LoS, never Grid.blockers, so
## a plain blocker in the path is still a "legal" shot to attempt today
## and the AI's own existing fast path happily fires it uselessly into
## the blocker; only a genuine LoS break stops is_legal() from ever
## queuing the shot at all) at (3,2) blinds the origin (3,0) from an
## enemy far down the same column at (3,9), while both orthogonal
## neighbors keep clear LoS around it. Row y=1 is ALSO walled (pathing
## only — no opacity, so it never blocks vision) everywhere within reach
## except by stepping fully around via row 0: without this, a diagonal
## hop into row 1 (e.g. (4,1)) would cut chebyshev distance to the
## far-away enemy MORE than any step-out cell does, and AGGRESSIVE's own
## engagement scorer would reposition there instead of stepping out — a real
## trap this test fell into on the first attempt. With that escape
## closed, every reachable row-0 cell (including both step-out cells) ties
## on chebyshev distance (a lateral move never gets closer to a target
## almost directly ahead), so the scorer converges on staying at the
## blind origin — exactly the "nothing else found anything to do" case
## the step-out fallback exists for. A tight MP budget (just enough for
## the step out's own two single-cell moves) keeps this from being confused with
## a longer, ordinary reposition trek.
func test_a_covered_aggressive_unit_steps_out_instead_of_just_standing_and_facing() -> void:
	var grid := Grid.new(10, 10)
	for x in range(8):
		grid.set_terrain(Vector2i(x, 1), Enums.TerrainType.WALL)
	grid.set_terrain(Vector2i(3, 2), Enums.TerrainType.WALL)
	grid.set_opacity(Vector2i(3, 2), 1.0)

	var self_unit := _armed_unit(&"self_unit", Vector2i(3, 0), 0, &"rifle")
	self_unit.max_ap = 1
	var enemy := _armed_unit(&"enemy", Vector2i(3, 9), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])

	assert_true(
		UnitAI.is_covered_from(self_unit.cell, enemy.cell, state, self_unit),
		"sanity: the origin must actually be covered"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null)

	assert_eq(
		queue.actions.size(),
		4,
		"must step out (out, shoot, back, end turn) rather than just facing uselessly"
	)
	assert_true(queue.actions[0] is MoveAction)
	assert_true(queue.actions[1] is AttackAction)
	assert_true(queue.actions[2] is MoveAction)
	assert_true(queue.actions[3] is EndTurnAction)
	var out_move: MoveAction = queue.actions[0]
	var firing_cell: Vector2i = out_move.path[out_move.path.size() - 1]
	assert_eq(
		Grid.distance_manhattan(self_unit.cell, firing_cell), 1, "an orthogonal step-out cell"
	)
	var back_move: MoveAction = queue.actions[2]
	assert_eq(
		back_move.path[back_move.path.size() - 1], self_unit.cell, "the return leg lands on origin"
	)
