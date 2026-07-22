extends GutTest

## taskblock-26 (CC, re-diagnosing B2 "skirmisher squares off through
## walls"): split out of test_unit_ai.gd (which was already at the
## file-length cap — the same reason test_damage_resolver_deflect_modes.gd
## split out of test_damage_resolver.gd) — the engagement-scoring
## regression coverage for `_pick_engagement_position`/`_engagement_score`'s
## own line gate.
## tb33 Pass A: renamed from `test_unit_ai_engagement_los.gd` — that gate
## reads `LineOfFire.has_clear_line_of_fire` now, not `LoS.has_los`
## (BR30.10: a "clear" line of SIGHT isn't the same claim as a clear shot).
## Every fixture below now places a REAL wall blocker `Part` alongside its
## opacity, not opacity alone — `ShotPlane` (what LOF actually resolves
## against) never reads opacity at all, so a hand-built wall needs both to
## faithfully stand in for a real `MapGen`-generated one.


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


## tb33 Pass A: a real wall — terrain, opacity, AND a real blocker `Part`
## (`ShotPlane` only ever reads `state.grid.blockers`/`state.units`, never
## opacity) — one cell at a time, since `DataLibrary.get_part` hands back
## a fresh `.duplicate()` every call and sharing one instance across
## multiple cells would make "destroying" one destroy all of them.
func _wall_at(grid: Grid, cell: Vector2i) -> void:
	grid.set_terrain(cell, Enums.TerrainType.WALL)
	grid.set_opacity(cell, 1.0)
	grid.blockers[cell] = DataLibrary.get_part(&"wall")


## taskblock-26 (CC, re-diagnosing B2): confirmed on 60 REAL generated
## maps (MapGen), not just this hand-built fixture — a wall/corridor bend
## no single turn's own movement budget can clear left NOT ONE reachable
## cell with a real line. `NO_LOF_PENALTY`'s own self-cell exemption then
## made "stand still" categorically beat every other candidate (only the
## self cell escaped the penalty), freezing the unit at its own spawn
## turn after turn — the exact "squares off... never takes space" symptom
## B2 was reported against, on a map big enough that one turn can't clear
## it at all. A wall tall enough that going around exceeds one turn's own
## movement budget, with the units sharing a row squarely blocked by it,
## reproduces this without needing a whole generated map. tb33: a single
## gap at the far bottom edge (y=19), not a fully sealed column — Pass
## B's own approach-fallback genuinely walks toward a real opening
## (matching what a real generated map always has SOMEWHERE), unlike the
## old greedy obstruction_count scorer, which made "progress" toward an
## obstruction regardless of whether the far side was ever reachable at
## all.
func test_skirmisher_advances_around_a_wall_even_when_no_reachable_cell_has_lof_yet() -> void:
	var grid := Grid.new(20, 20)
	for y in range(19):  # sealed except one gap at y=19, far from the shared row (y=10)
		_wall_at(grid, Vector2i(8, y))
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 10), 0, &"rifle")
	self_unit.shell.find_part(&"rifle").weapon_def.max_range = 30.0
	var enemy := _armed_unit(&"enemy", Vector2i(19, 10), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	# tb33: the default budget (mp_per_ap * ap, ~12 cells) can already reach
	# close enough to the single-cell gap to find LOF -- shrunk here (AFTER
	# construction -- CombatState.new()'s own _begin_turn() refreshes AP to
	# full for whichever unit goes first, so setting it any earlier gets
	# silently overwritten) so "too tall for ONE TURN" is genuinely true
	# regardless of exactly how far away the gap is.
	self_unit.ap = 1
	assert_false(
		LineOfFire.has_clear_line_of_fire(self_unit, enemy, self_unit.cell, state),
		"sanity: the wall blocks the shared row"
	)
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(
		self_unit.cell, self_unit.mp_per_ap() * self_unit.ap
	)
	assert_false(
		UnitAI._any_reachable_has_lof(
			self_unit, enemy, state, reachable, self_unit.shell.find_part(&"rifle")
		),
		"sanity: the wall band really is too tall for one turn to clear"
	)

	var queue: ActionQueue = UnitAI.plan_turn(self_unit, state, null, &"SKIRMISHER")

	var move: MoveAction = _last_move(queue)
	assert_not_null(
		move, "must advance toward the wall even without a line this turn, never freeze at spawn"
	)
	var destination: Vector2i = move.path[move.path.size() - 1]
	assert_lt(
		Grid.distance_chebyshev(destination, enemy.cell),
		Grid.distance_chebyshev(self_unit.cell, enemy.cell),
		"must actually make progress toward the enemy, not just face uselessly at the origin"
	)


## taskblock-26 (CC, re-diagnosing B2): the narrower, direct proof —
## `_engagement_score`'s own self-cell exemption must NOT apply when
## `any_reachable_has_lof` is false, so a cell making genuine progress
## outscores standing still even though neither has a real line. With
## `any_reachable_has_lof` true (the ordinary case — some OTHER reachable
## cell really does have one), the self cell keeps its exemption exactly
## as before, unchanged from taskblock-26 Pass B2's own original fix.
func test_engagement_score_self_exemption_only_applies_when_some_cell_actually_has_lof() -> void:
	var grid := Grid.new(20, 3)
	for x in range(5, 15):
		_wall_at(grid, Vector2i(x, 1))
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(19, 1), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	var weapon: Part = self_unit.shell.find_part(&"rifle")
	var progress_cell := Vector2i(4, 1)  # closer to preferred range, still behind the same wall
	assert_false(
		LineOfFire.has_clear_line_of_fire(self_unit, enemy, self_unit.cell, state), "sanity"
	)
	assert_false(
		LineOfFire.has_clear_line_of_fire(self_unit, enemy, progress_cell, state),
		"sanity: still behind the wall"
	)

	var self_score_when_nothing_has_lof: float = UnitAI._engagement_score(
		self_unit.cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		false
	)
	var progress_score_when_nothing_has_lof: float = UnitAI._engagement_score(
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
		progress_score_when_nothing_has_lof,
		self_score_when_nothing_has_lof,
		"with no LOF cell reachable at all, real progress must outscore the exempted self cell"
	)

	var self_score_when_something_has_lof: float = UnitAI._engagement_score(
		self_unit.cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		true
	)
	var progress_score_when_something_has_lof: float = UnitAI._engagement_score(
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
		self_score_when_something_has_lof,
		progress_score_when_something_has_lof,
		"unchanged from Pass B2: the self cell keeps its exemption once some cell truly has LOF"
	)


## taskblock-27 (CC, re-diagnosing B2 a SECOND time — confirmed still
## frozen on a real 6-unit bout's own combat.log, every playstyle, from
## Turn 2 onward): the first re-diagnosis's own "plain progress toward
## preferred_range" fallback plateaus the instant a unit reaches its own
## preferred numeric distance band, even fully walled off — moving
## further doesn't reduce |distance-preferred| once it's already at its
## minimum, so the unit freezes there forever, still blind. A cell
## further from `preferred_range` but with FEWER opaque cells between it
## and the enemy (`LoS.obstruction_count`) must now outscore a cell
## exactly at the preferred distance but more obstructed — genuine
## progress toward a real line beats matching a number. tb33: this signal
## stays genuinely opacity-based (`LoS.obstruction_count`, unchanged) —
## only the GATE deciding whether to lean on it moved from LOS to LOF, so
## this fixture stays opacity-only, no real blocker needed.
func test_obstruction_count_beats_raw_distance_when_nothing_reachable_has_lof() -> void:
	var grid := Grid.new(25, 5)
	# A short, thick wall segment directly on the near cell's own line to
	# the enemy; the far cell's own line clears it by going around instead.
	for x in range(16, 20):
		grid.set_terrain(Vector2i(x, 0), Enums.TerrainType.WALL)
		grid.set_opacity(Vector2i(x, 0), 1.0)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 0), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(20, 0), 1, &"")
	var state := CombatState.new(grid, [self_unit, enemy])
	var weapon: Part = self_unit.shell.find_part(&"rifle")
	# Exactly at SKIRMISHER_PREFERRED_RANGE (5) from the enemy, but its own
	# line back to the enemy crosses the whole 4-wide wall segment head-on
	# (obstruction_count 4).
	var near_but_obstructed := Vector2i(15, 0)
	# One further from the preferred range, but its own line to the enemy
	# (a different row) crosses far less of the wall (obstruction_count 1)
	# — genuinely closer to a real line, even though farther by the number.
	var far_but_clear := Vector2i(14, 4)
	assert_false(LoS.has_los(grid, near_but_obstructed, enemy.cell), "sanity")
	var near_obstruction: int = LoS.obstruction_count(grid, near_but_obstructed, enemy.cell)
	var far_obstruction: int = LoS.obstruction_count(grid, far_but_clear, enemy.cell)
	assert_lt(far_obstruction, near_obstruction, "sanity: the far cell really is less obstructed")

	var near_score: float = UnitAI._engagement_score(
		near_but_obstructed,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		false
	)
	var far_score: float = UnitAI._engagement_score(
		far_but_clear,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		false
	)
	assert_gt(
		far_score,
		near_score,
		"a less-obstructed cell must outscore one merely closer to the numeric preferred range"
	)


## tb33 Pass A: the direct proof the LOS->LOF swap exists for — a cell can
## SEE the enemy (no opaque cell on the line: `LoS.has_los` true) while a
## real wall blocker `Part` still stops the actual shot (`LineOfFire.
## has_clear_line_of_fire` false). Scoring on `has_los` would have called
## this cell just as good as a genuinely clear one; scoring on LOF must not.
func test_scorer_ranks_a_clear_lof_cell_above_a_los_but_wall_blocked_cell() -> void:
	var grid := Grid.new(10, 3)
	var self_unit := _armed_unit(&"self_unit", Vector2i(0, 1), 0, &"rifle")
	var enemy := _armed_unit(&"enemy", Vector2i(9, 1), 1, &"")
	var blocked_cell := Vector2i(5, 1)
	# A wall Part with no opacity change: ShotPlane (LOF) blocks it, LoS
	# (opacity-only) does not -- the exact tb31-C gap this pass closes.
	grid.blockers[blocked_cell] = DataLibrary.get_part(&"wall")
	var clear_cell := Vector2i(5, 0)
	var state := CombatState.new(grid, [self_unit, enemy])
	var weapon: Part = self_unit.shell.find_part(&"rifle")

	assert_true(LoS.has_los(grid, blocked_cell, enemy.cell), "sanity: nothing opaque blocks sight")
	assert_false(
		LineOfFire.has_clear_line_of_fire(self_unit, enemy, blocked_cell, state),
		"sanity: the real wall Part still stops the shot"
	)
	assert_true(LineOfFire.has_clear_line_of_fire(self_unit, enemy, clear_cell, state), "sanity")

	var blocked_score: float = UnitAI._engagement_score(
		blocked_cell,
		enemy,
		state,
		self_unit,
		UnitAI.SKIRMISHER_PREFERRED_RANGE,
		false,
		weapon,
		true
	)
	var clear_score: float = UnitAI._engagement_score(
		clear_cell, enemy, state, self_unit, UnitAI.SKIRMISHER_PREFERRED_RANGE, false, weapon, true
	)
	assert_gt(
		clear_score,
		blocked_score,
		"a genuinely clear shot must outscore one that only LOOKS clear over opacity alone"
	)
