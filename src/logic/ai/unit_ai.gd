class_name UnitAI
extends RefCounted

## taskblock-14 Pass B: the block's own spine. "There is no AI system" —
## the only decision-maker for a non-human unit's turn used to be a
## ~60-line `_queue_turn` trapped inside test_full_mission.gd. Extracted
## here verbatim in spirit (AGGRESSIVE reproduces its behaviour exactly —
## the full mission test still passes unchanged) so it's a real, driveable
## module instead of test-only scaffolding.
##
## Pure: `(unit, state, mission, playstyle) -> ActionQueue`. No SceneTree,
## no view, deterministic — same seed + same state always produces the
## same queue. Human and AI paths emit the same `ActionQueue` through the
## same `CombatState.resolve_until` — this is not a parallel turn system,
## it's an action-queue PRODUCER the same as the human UI, which is what
## keeps AI-verified combat identical to human-played combat.

## Up to this many shots fired at the same target in one turn once
## already in range — same flagged number test_full_mission.gd's own
## `_queue_turn` used (enough AP-budget headroom that a target dying to
## the first real shot leaves a second queued shot to abort for real at
## resolution).
const MAX_SHOTS_PER_TURN := 3
## taskblock-16 Pass D1: preferred standoff per playstyle — flagged, not
## tuned; the behaviour (hold ~this distance: advance if farther while
## out of range, retreat if closer, never invented beyond the "~"
## approximate the taskblock itself specified) is what's specified, not
## the exact cell counts. AGGRESSIVE's own 0 is what makes `_plan_ranged`
## below collapse to exactly its old pre-Pass-D behaviour — see that
## function's own doc comment.
const AGGRESSIVE_PREFERRED_RANGE := 0
const SKIRMISHER_PREFERRED_RANGE := 5
const MARKSMAN_PREFERRED_RANGE := 7
## Dominant over any plausible distance-penalty difference on a normal
## map, so a covered cell always outscores an uncovered one closer to
## the preferred distance — cover is the primary signal, distance a
## tiebreaker among covered cells.
const COVER_SCORE_BONUS := 10.0
## taskblock17-1 Pass B: dominant over COVER_SCORE_BONUS itself, not just
## the distance penalty — a cell with an ally in the firing line must lose
## to literally any clear cell, covered or not. Still just a penalty, not
## a hard exclusion: if every reachable cell is blocked, the least-bad one
## still "wins" the comparison, and `_plan_ranged` catches that case
## afterward and holds fire rather than firing through an ally anyway.
const ALLY_BLOCKED_PENALTY := 1000.0


## `playstyle` biases decisions; unrecognised/empty falls back to
## AGGRESSIVE (today's own only behaviour) rather than erroring — an
## open StringName vocabulary (CLAUDE.md), not an enum, so a fifth
## playstyle is one more `match` arm and new data, never a rewrite.
static func plan_turn(
	unit: Unit, state: CombatState, mission: MissionState, playstyle: StringName = &"AGGRESSIVE"
) -> ActionQueue:
	match playstyle:
		&"SKIRMISHER":
			return _plan_ranged(unit, state, mission, SKIRMISHER_PREFERRED_RANGE, false)
		&"MARKSMAN":
			return _plan_ranged(unit, state, mission, MARKSMAN_PREFERRED_RANGE, false)
		&"COVER_SEEKER":
			# taskblock-16 D2: "a cover-seeker is a skirmisher that also
			# weights cover" — its own preferred standoff is SKIRMISHER's,
			# not a fourth, independently-tuned number.
			return _plan_ranged(unit, state, mission, SKIRMISHER_PREFERRED_RANGE, true)
		_:
			return _plan_ranged(unit, state, mission, AGGRESSIVE_PREFERRED_RANGE, false)


## taskblock-16 Pass D: the one ranged planner every playstyle above
## drives, parameterised by `preferred_range` (a target standoff to
## converge on) and `weight_cover` (COVER_SEEKER's own extra signal on
## the same distance logic).
##
## `far_enough`/`covered_enough` gate whether the unit is already good
## enough to fire from right where it stands, without moving first — for
## AGGRESSIVE (`preferred_range` 0, `weight_cover` false) both are always
## true (`distance >= 0` always holds; `not false` is always true), which
## collapses this gate to exactly `queue.enqueue(the attack)` — the same
## single check the old, since-retired `_plan_aggressive` used as its own
## "already_in_range" fast path. That's not a coincidence: it's what
## makes AGGRESSIVE's own behaviour genuinely unchanged rather than just
## similar, still verified end to end by test_full_mission.gd's own fixed
## seed. For a positive `preferred_range`, `far_enough` false means "too
## close" — skip straight to repositioning (retreat) without ever
## attempting to fire from here, satisfying "back off if closer." The
## repositioning branch below scores every reachable cell toward
## `preferred_range` regardless of why it's reached (out of range, too
## close, or just uncovered) — the same mechanism handles "advance"
## and "retreat" as opposite pulls on one scorer, not two behaviours.
##
## Flagged design choice, not a spec literal: a unit already inside
## weapon range but standing FARTHER than `preferred_range` does not
## walk closer purely to hit the exact preferred number — it stays and
## fires. Chasing an arbitrary preferred distance while already able to
## hit the target would make MARKSMAN behave less like a marksman, and
## "advance if farther" is fully satisfied by the far-more-common case of
## actually being out of weapon range (below).
static func _plan_ranged(
	unit: Unit, state: CombatState, mission: MissionState, preferred_range: int, weight_cover: bool
) -> ActionQueue:
	var queue := ActionQueue.new(unit)
	var enemy: Unit = _nearest_living_enemy(unit, state)

	if enemy == null:
		return _plan_non_combat_turn(unit, state, mission, queue)

	var weapon_id: StringName = _find_weapon_id(unit)
	var far_enough: bool = Grid.distance_chebyshev(unit.cell, enemy.cell) >= preferred_range
	var covered_enough: bool = (
		not weight_cover or is_covered_from(unit.cell, enemy.cell, state, unit)
	)
	# taskblock17-1 Pass B: an AI never CHOOSES to shoot through its own
	# ally — friendly fire is still mechanically possible (a player can
	# still line one up), this only stops the AI from picking it.
	var clear_from_here: bool = not _ally_in_firing_line(unit, enemy, unit.cell, state)
	var fired_without_moving: bool = (
		weapon_id != &""
		and far_enough
		and covered_enough
		and clear_from_here
		and queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
	)

	if fired_without_moving:
		_fire_remaining_shots(unit, weapon_id, enemy, state, queue, 1)
	else:
		var queued_before: int = queue.actions.size()
		var best_cell: Vector2i = _pick_engagement_position(
			unit, enemy, state, preferred_range, weight_cover
		)
		if best_cell != unit.cell:
			var pf := Pathfinder.new(state.grid, state.terrain_costs)
			var path: Array[Vector2i] = pf.astar(unit.cell, best_cell)
			if path.size() >= 2:
				queue.enqueue(MoveAction.new(unit, path), state)
		var final_blocked: bool = _ally_in_firing_line(unit, enemy, best_cell, state)
		if (
			weapon_id != &""
			and _in_weapon_range(unit, weapon_id, enemy, best_cell)
			and not final_blocked
		):
			queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
		# taskblock-18 D2 (taskblock-19 Pass B: Lean -> Step Out rename):
		# "shared AI and player path — one implementation." A last resort,
		# tried only when nothing above found anything to do this turn at
		# all (no reposition move queued — best_cell == unit.cell, since
		# re-enqueuing a step-out's own outbound Move against a queue that
		# already moved the unit elsewhere would path from the wrong cell
		# — and no attack either): a genuinely free upgrade from "stand
		# and face uselessly" to "pop out, shoot, come back," through the
		# exact same StepOutPlanner.assemble_for_shoot() a human's own
		# SHOOT click uses, never a second AI-only notion of stepping out.
		if queue.actions.size() == queued_before and weapon_id != &"" and best_cell == unit.cell:
			var step_out_queue: ActionQueue = StepOutPlanner.assemble_for_shoot(
				state, unit, weapon_id, enemy
			)
			if step_out_queue != null:
				for action: CombatAction in step_out_queue.actions:
					queue.enqueue(action, state)
		_face_if_nothing_else_queued(unit, enemy, state, queue, queued_before)

	queue.enqueue(EndTurnAction.new(unit), state)
	return queue


## "Otherwise, if this is a landing-squad unit with the gather objective
## still open -> walk to the resource node and gather it; otherwise walk
## to extraction and call it." Shared by every playstyle — none of this
## is combat behaviour.
static func _plan_non_combat_turn(
	unit: Unit, state: CombatState, mission: MissionState, queue: ActionQueue
) -> ActionQueue:
	if unit.squad_id != 0:
		queue.enqueue(EndTurnAction.new(unit), state)
		return queue

	var incomplete: bool = mission.objectives.any(
		func(o: StringName) -> bool: return o not in mission.completed_objectives
	)
	if incomplete:
		var node_cell: Vector2i = mission.resource_nodes.keys()[0]
		if unit.cell == node_cell:
			queue.enqueue(GatherAction.new(mission, unit, node_cell), state)
		else:
			_path_toward(unit, node_cell, state, queue)
	else:
		var extraction_cell: Vector2i = mission.extraction_cells[0]
		if unit.cell == extraction_cell:
			queue.enqueue(ExtractAction.new(mission, unit), state)
		else:
			_path_toward(unit, extraction_cell, state, queue)

	queue.enqueue(EndTurnAction.new(unit), state)
	return queue


## Continues firing `weapon_id` at `enemy` up to `MAX_SHOTS_PER_TURN`
## total (`already_fired` counts the shot the caller already queued),
## stopping the instant a queued shot is refused (out of AP, most often).
static func _fire_remaining_shots(
	unit: Unit,
	weapon_id: StringName,
	enemy: Unit,
	state: CombatState,
	queue: ActionQueue,
	already_fired: int
) -> void:
	var fired := already_fired
	while (
		fired < MAX_SHOTS_PER_TURN
		and queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
	):
		fired += 1


## PLAN.md's own carried finding (taskblock-13's predecessor block): a
## unit that queued nothing else this turn instead turns to face its
## threat square-on — an ordinary defensive reaction, not new tactical
## sophistication — which drives the incidence angle toward 0, and
## STOP_DEAD is what geometry gives you at 0 (docs/03: DEFLECT never
## damages the plate the way STOP_DEAD does, so a frozen orientation
## could otherwise deflect the same shot forever).
static func _face_if_nothing_else_queued(
	unit: Unit, enemy: Unit, state: CombatState, queue: ActionQueue, queued_before: int
) -> void:
	if queue.actions.size() == queued_before:
		queue.enqueue(
			FaceAction.new(unit, FaceAction.orientation_toward(unit.cell, enemy.cell)), state
		)


static func _in_weapon_range(
	unit: Unit, weapon_id: StringName, enemy: Unit, from_cell: Variant = null
) -> bool:
	var weapon: Part = unit.shell.find_part(weapon_id)
	if weapon == null:
		return false
	var origin: Vector2i = from_cell if from_cell != null else unit.cell
	var range_cells: int = Grid.distance_chebyshev(origin, enemy.cell)
	return weapon.weapon_max_range <= 0.0 or range_cells <= int(weapon.weapon_max_range)


## taskblock-14 Pass B1: "is a field object / ally / wall between it and
## the threat" — the same shape as Overwatch's own torso-visibility check
## (docs/09 taskblock06 F2: an intervening-object query along a line),
## simplified to a bare cell walk since this is a movement HEURISTIC
## scoring many candidate cells per turn, not a live shot resolution:
## true if the line is fully opaque (no LoS at all — maximally covered)
## or a real blocker/another unit sits strictly between the two cells.
static func is_covered_from(
	candidate_cell: Vector2i, threat_cell: Vector2i, state: CombatState, self_unit: Unit
) -> bool:
	if candidate_cell == threat_cell:
		return false
	if not LoS.has_los(state.grid, threat_cell, candidate_cell):
		return true
	var cells: Array[Vector2i] = Grid.line(threat_cell, candidate_cell)
	for i in range(1, cells.size() - 1):
		var cell: Vector2i = cells[i]
		if state.grid.blockers.has(cell):
			return true
		for unit: Unit in state.units:
			if unit != self_unit and unit.alive and unit.cell == cell:
				return true
	return false


## taskblock17-1 Pass B: "test whether a friendly unit sits on the firing
## line between muzzle and target — reuse the shot-plane path, the same
## geometry that would hit them, asked in advance." Builds the exact same
## plane/aim-point `AttackAction.apply()` itself resolves against
## (`ShotPlane.build` + `center_of`, the shot's own nominal center-mass
## point before scatter) and asks what it would actually hit first — never
## a re-derived approximation of that geometry, so this can't disagree
## with what firing for real would do. `from_cell` is a candidate
## (possibly not yet occupied) cell, so `unit`'s own real body — still
## registered in `state.units` at its true `unit.cell` — is explicitly
## excluded from counting as a blocker of itself.
static func _ally_in_firing_line(
	unit: Unit, target: Unit, from_cell: Vector2i, state: CombatState
) -> bool:
	var direction := Vector2(target.cell - from_cell)
	if direction.is_zero_approx():
		return false
	var origin := Vector2(from_cell.x, from_cell.y)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	var region: Region = _first_hit_excluding(plane, aim_point, unit)
	if region == null or not (region.body is Unit):
		return false
	var hit_unit: Unit = region.body as Unit
	return hit_unit != target and hit_unit.alive and hit_unit.squad_id == unit.squad_id


## docs/09 taskblock07 Pass A1: `ShotPlane.resolve_projectile` is
## shot_plane.gd's own internal lookup — every other caller in `src/` is
## forbidden from reaching it directly (`test_resolve_projectile_is_
## called_only_from_shot_plane_itself`), the same rule `DamageResolver`'s
## own `_find_next` already exists to honor rather than break. Same
## rect-lookup, just excluding one body by identity instead of a part
## list — needed here because the shooter's own body sits at the ray's
## own origin (depth <= 0) and would otherwise satisfy the point-
## containment check before anything actually downrange of it (the same
## reason `AttackAction.apply()` excludes its own shell's parts).
static func _first_hit_excluding(
	plane: Array[Region], point: Vector2, exclude_body: Unit
) -> Region:
	for region: Region in plane:
		if region.body == exclude_body:
			continue
		if region.rect.has_point(point):
			return region
	return null


## The best reachable-this-turn cell to fight from: if `weight_cover`,
## covered cells always beat uncovered ones; among cells tied on cover
## (or always, when `weight_cover` is false), the one closest to
## `preferred_range` from `enemy` wins — pulls toward that distance from
## EITHER side, so the same scorer drives advancing when farther and
## retreating when closer. Staying put is always a candidate
## (`Pathfinder.reachable` already includes the origin cell at zero cost).
static func _pick_engagement_position(
	unit: Unit, enemy: Unit, state: CombatState, preferred_range: int, weight_cover: bool
) -> Vector2i:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	if not reachable.has(unit.cell):
		reachable.append(unit.cell)

	var best_cell: Vector2i = unit.cell
	var best_score: float = _engagement_score(
		unit.cell, enemy, state, unit, preferred_range, weight_cover
	)
	for cell: Vector2i in reachable:
		var score: float = _engagement_score(
			cell, enemy, state, unit, preferred_range, weight_cover
		)
		if score > best_score:
			best_score = score
			best_cell = cell
	return best_cell


static func _engagement_score(
	cell: Vector2i,
	enemy: Unit,
	state: CombatState,
	self_unit: Unit,
	preferred_range: int,
	weight_cover: bool
) -> float:
	var distance: int = Grid.distance_chebyshev(cell, enemy.cell)
	var distance_penalty: float = absf(float(distance - preferred_range))
	var cover_bonus: float = (
		COVER_SCORE_BONUS
		if weight_cover and is_covered_from(cell, enemy.cell, state, self_unit)
		else 0.0
	)
	# taskblock17-1 Pass B: a clear line always outscores cover — see
	# ALLY_BLOCKED_PENALTY's own doc comment.
	var blocked_penalty: float = (
		ALLY_BLOCKED_PENALTY if _ally_in_firing_line(self_unit, enemy, cell, state) else 0.0
	)
	return cover_bonus - distance_penalty - blocked_penalty


static func _find_weapon_id(unit: Unit) -> StringName:
	for part: Part in unit.shell.living_parts():
		if part.damage > 0.0:
			return part.id
	return &""


## taskblock17-1 Pass C: raw chebyshev distance ignores walls — a bot
## could fixate on an enemy that's close as the crow flies but walled off
## entirely, fail to path there every turn, and sit facing that wall
## forever. Ranks candidates by distance first, then walks the list
## checking reachability, returning the first candidate that's actually
## pathable — in the common unobstructed case that's the very first
## (nearest) candidate, so only one reachability check ever runs; the
## fallback loop only costs more when the nearest candidates genuinely
## are walled off.
static func _nearest_living_enemy(unit: Unit, state: CombatState) -> Unit:
	var living_enemies: Array[Unit] = []
	for candidate: Unit in state.units:
		if candidate.squad_id != unit.squad_id and candidate.alive:
			living_enemies.append(candidate)
	if living_enemies.is_empty():
		return null
	living_enemies.sort_custom(
		func(a: Unit, b: Unit) -> bool:
			return (
				Grid.distance_chebyshev(unit.cell, a.cell)
				< Grid.distance_chebyshev(unit.cell, b.cell)
			)
	)
	for candidate: Unit in living_enemies:
		if _has_path_toward(unit, candidate, state):
			return candidate
	# Nothing is reachable at all — the nearest-by-distance candidate is
	# still the most sensible fallback (unchanged from the old behaviour)
	# rather than returning null and going fully idle.
	return living_enemies[0]


## "Is there a path at all" — structural reachability, not this-turn MP
## budget: whether the unit could EVER walk to `target`, ignoring how
## many turns it would take. `target`'s own cell is always occupied (so
## never walkable, `Pathfinder.move_cost`), so this checks its
## neighbours instead: reachable if there's a real path to at least one
## cell adjacent to it. "Cheapest correct version" — `Pathfinder.astar`
## per neighbour, not a full-grid flood fill, and only ever called on
## candidates that actually need it (the common unobstructed case never
## reaches this at all — see `_nearest_living_enemy`'s own doc comment).
static func _has_path_toward(unit: Unit, target: Unit, state: CombatState) -> bool:
	if Grid.distance_chebyshev(unit.cell, target.cell) <= 1:
		return true
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	for neighbor: Vector2i in state.grid.neighbors(target.cell):
		if not pf.astar(unit.cell, neighbor).is_empty():
			return true
	return false


## Greedily closes the distance to `target_cell` by one reachable-this-turn
## step, queuing a MoveAction if that step actually goes anywhere.
static func _path_toward(
	unit: Unit, target_cell: Vector2i, state: CombatState, queue: ActionQueue
) -> void:
	if unit.cell == target_cell:
		return
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	var best_cell: Vector2i = unit.cell
	var best_dist: int = Grid.distance_chebyshev(unit.cell, target_cell)
	for cell: Vector2i in reachable:
		var d: int = Grid.distance_chebyshev(cell, target_cell)
		if d < best_dist:
			best_dist = d
			best_cell = cell
	if best_cell != unit.cell:
		var path: Array[Vector2i] = pf.astar(unit.cell, best_cell)
		if path.size() >= 2:
			queue.enqueue(MoveAction.new(unit, path), state)
