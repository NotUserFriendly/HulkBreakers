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
## taskblock-19 Pass C3: "only closes inside min_range if forced" —
## dominant over COVER_SCORE_BONUS (so cover alone never lures a unit
## inside its own weapon's min_range), but far below ALLY_BLOCKED_PENALTY
## (a forced close, when every reachable cell is under min_range or
## nothing else is even in range, must still be pickable as the least-bad
## option, the same posture ALLY_BLOCKED_PENALTY's own doc comment
## describes). Flagged, not a tuned design number.
const MIN_RANGE_PENALTY := 20.0
## taskblock-19 Pass E: "treats adjacent to an enemy with a long gun as
## bad (won't close if it disarms itself)." Dominant over MIN_RANGE_PENALTY
## and COVER_SCORE_BONUS — being unable to fire at all is worse than a
## merely degraded shot — but still a penalty, not an exclusion, for the
## same "forced" reason every other penalty here stays soft. Flagged, not
## a tuned design number.
const SUPPRESSION_PENALTY := 25.0
## taskblock-19 Pass E: "treats leaving an adjacent tile as costly (expects
## the free hit)." Real but slightly below SUPPRESSION_PENALTY — a one-time
## stub hit is a lesser cost than standing somewhere that disarms the
## weapon outright for the whole turn. Flagged, not a tuned design number.
const OPPORTUNITY_ATTACK_PENALTY := 15.0
## taskblock-26 Pass B2: "a standoff cell with no line is not a valid
## standoff." Dominant over EVERY other term here, including
## ALLY_BLOCKED_PENALTY — without LOS there's no shot to weigh an ally
## being in the way OF at all, so lacking one has to outrank every softer
## consideration. Still just a penalty, not a hard exclusion: if nothing
## reachable has real LOS, the least-bad cell still wins rather than the
## planner freezing in place facing a wall.
const NO_LOS_PENALTY := 2000.0
## taskblock-27 (CC, re-diagnosing B2 a second time): per-unit-of-
## `LoS.obstruction_count` weight, applied only when no reachable cell
## has real LOS at all — see `_engagement_score`'s own doc comment.
## Flagged, not a tuned design number; only "large enough to dominate any
## plausible `distance_penalty` spread on a real map" is specified —
## `distance_penalty` is itself unweighted (a plain Chebyshev delta), so
## even a big map's worst-case spread stays two orders of magnitude
## below this.
const OBSTRUCTION_PENALTY_WEIGHT := 1000.0

## taskblock-26 Pass C1: "populate the bout maker's AI dropdown from the
## actual playstyle set... so new playstyles appear automatically, not a
## hardcoded menu list." The one maintained list of every id
## `_plan_turn_before_shutdown_check`'s own `match` recognizes by name
## (PSYCHOTIC/TURTLE fall through its default arm too, but still route to
## real, distinct behavior — see `_plan_ranged`'s own PSYCHOTIC branch and
## the TURTLE dispatch arm) — GDScript has no reflection over a `match`
## statement's own arms, so this is the seam every OTHER caller (a UI
## dropdown, a test) reads instead of hand-copying its own list that could
## silently drift from what the planner actually dispatches on.
const PLAYSTYLES: Array[StringName] = [
	&"AGGRESSIVE",
	&"COVER_SEEKER",
	&"SKIRMISHER",
	&"MARKSMAN",
	&"PSYCHOTIC",
	&"TURTLE",
]


## `playstyle` biases decisions; unrecognised/empty falls back to
## AGGRESSIVE (today's own only behaviour) rather than erroring — an
## open StringName vocabulary (CLAUDE.md), not an enum, so a fifth
## playstyle is one more `match` arm and new data, never a rewrite.
##
## taskblock-21 Pass D2: "no functional weapon -> flee — a new top-priority
## branch, above the ranged/cover planners." Checked before the playstyle
## dispatch, not folded into `_plan_ranged`'s own `enemy == null` fallback
## — a disarmed unit STILL facing a live enemy must flee too, not just one
## that's run out of targets. `mission == null` (most headless unit tests,
## and any non-bout combat) has nowhere defined to flee TO — falls through
## to normal planning unchanged, same as today.
## taskblock-22 Pass C: "NPCs use shutdown when they can't move or act
## (stalled)." Checked LAST, against whatever queue every planner above
## already built — a queue that ended up with literally nothing but
## EndTurnAction (no move, no attack, no hold, no flee — every planner's
## own "nothing else found anything to do" fallback) IS "can't move and
## can't act," the same proxy every one of those planners already uses
## internally to reach that exact fallback. Swaps the trailing
## EndTurnAction for ShutdownAction rather than appending — Shutdown ends
## the turn itself, the same "this IS the last action" shape
## HoldAction/EndTurnAction already have.
##
## `not unit.shutdown` guards a REAL bug this pass introduced and then
## caught live: once every unit on the board is dead-or-shutdown,
## `CombatState.advance_turn()`'s own candidates list goes empty and it
## no-ops, leaving `current_unit()` stuck replaying the SAME already-
## shutdown unit forever. `EndTurnAction.is_legal()` is deliberately
## ALWAYS legal for the current unit (its own doc comment: "or every
## subsequent turn would stall on a corpse") specifically so a stuck
## board still spins forward one no-op turn at a time toward whatever
## safety net eventually fires (BoutRunner's own turn_cap, a caller's own
## guard). `ShutdownAction.is_legal()` is NOT always-legal (it rejects an
## already-shut-down unit) — swapping in a second one here would silently
## fail to enqueue, leaving an EMPTY queue that never calls
## advance_turn() again at all, breaking that guarantee outright. An
## already-shutdown unit keeps producing its own plain, always-legal
## EndTurnAction instead, preserving it.
##
## `not EndTurnAction.is_holding_position(...)` guards a SECOND real bug
## caught the same way: a unit standing on its own extraction tile with
## nothing else queued is not "stalled" — it's actively holding
## (Pass A2's own passive hold, matured by EndTurnAction itself the
## instant it actually resolves). Swapping it for Shutdown here would
## fire BEFORE the hold ever got a chance to start or mature, permanently
## taking a unit that was about to extract cleanly out of consideration
## instead — reproduced live (a lone landing-squad survivor already on its
## own tile got shut down on arrival instead of holding, then never
## resolved again since it was now the board's only remaining unit).
static func plan_turn(
	unit: Unit, state: CombatState, mission: MissionState, playstyle: StringName = &"AGGRESSIVE"
) -> ActionQueue:
	var queue: ActionQueue = _plan_turn_before_shutdown_check(unit, state, mission, playstyle)
	var should_shut_down: bool = (
		not unit.shutdown
		and not EndTurnAction.is_holding_position(unit, mission)
		and queue.actions.size() == 1
		and queue.actions[0] is EndTurnAction
	)
	if should_shut_down:
		queue.actions.clear()
		queue.enqueue(ShutdownAction.new(unit), state)
	return queue


static func _plan_turn_before_shutdown_check(
	unit: Unit, state: CombatState, mission: MissionState, playstyle: StringName
) -> ActionQueue:
	if mission != null and not _has_functional_weapon(unit):
		return _plan_flee(unit, state, mission)
	match playstyle:
		&"SKIRMISHER":
			return _plan_ranged(unit, state, mission, SKIRMISHER_PREFERRED_RANGE, false, playstyle)
		&"MARKSMAN":
			return _plan_ranged(unit, state, mission, MARKSMAN_PREFERRED_RANGE, false, playstyle)
		&"COVER_SEEKER":
			# taskblock-16 D2: "a cover-seeker is a skirmisher that also
			# weights cover" — its own preferred standoff is SKIRMISHER's,
			# not a fourth, independently-tuned number.
			return _plan_ranged(unit, state, mission, SKIRMISHER_PREFERRED_RANGE, true, playstyle)
		&"PSYCHOTIC":
			# taskblock-25 Pass F (docs/PLAN.md "Phase M — Melee"): "prefers
			# melee, closes to minimize distance, never flees." Reuses
			# `_plan_ranged` with AGGRESSIVE's own preferred_range 0 (the
			# distance-closing logic is unchanged — only WHICH weapon it
			# fires with differs, see `_plan_ranged`'s own PSYCHOTIC branch)
			# — never a second, independently-tuned closing behavior.
			return _plan_ranged(unit, state, mission, AGGRESSIVE_PREFERRED_RANGE, false, playstyle)
		&"TURTLE":
			# taskblock-25 Pass F: "keeps distance, would rather flee than
			# melee, uses cover." Melee weighted as a last resort — reached
			# only by being adjacent to a living enemy at all
			# (`Suppression.is_suppressed`, the same adjacency predicate
			# suppression's own melee-opportunity trigger already reads),
			# not a hardcoded distance number of its own. Otherwise an
			# ordinary cover-weighting planner, same standoff COVER_SEEKER
			# already uses.
			if mission != null and Suppression.is_suppressed(state, unit):
				return _plan_flee(unit, state, mission)
			return _plan_ranged(unit, state, mission, SKIRMISHER_PREFERRED_RANGE, true, playstyle)
		_:
			return _plan_ranged(unit, state, mission, AGGRESSIVE_PREFERRED_RANGE, false, playstyle)


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
	unit: Unit,
	state: CombatState,
	mission: MissionState,
	preferred_range: int,
	weight_cover: bool,
	playstyle: StringName = &"AGGRESSIVE"
) -> ActionQueue:
	var queue := ActionQueue.new(unit)
	var enemy: Unit = _nearest_living_enemy(unit, state)

	if enemy == null:
		return _plan_non_combat_turn(unit, state, mission, queue)

	var weapon_id: StringName = _find_weapon_id(unit)
	# taskblock-25 Pass F: "prefers the melee action... uses ranged only if
	# it can't reach melee" — PSYCHOTIC only, and only when it actually has
	# one (`ActionCatalog.provider_for`, the same seam every other weapon
	# pick in this file already reads, never a hardcoded id). Every other
	# playstyle's own `_find_weapon_id` pick is completely untouched.
	if playstyle == &"PSYCHOTIC":
		var melee_weapon: Part = ActionCatalog.provider_for(unit, &"stab")
		if melee_weapon != null:
			weapon_id = melee_weapon.id
	var weapon: Part = unit.shell.find_part(weapon_id) if weapon_id != &"" else null
	# taskblock-19 Pass C3: beyond the weapon's own effective_range (when
	# authored), firing without moving is never the fast path's call to
	# make — the repositioning branch's own range-aware, cover-dominant
	# scorer below is what decides "close in" vs "hold and take the
	# degraded shot," not a flat "already legal, so good enough" check.
	# `within_effective` degrades gracefully to always-true for an
	# unauthored weapon, matching this planner's pre-existing behaviour
	# exactly.
	var within_effective: bool = (
		weapon == null
		or weapon.weapon_def == null
		or weapon.weapon_def.effective_range <= 0.0
		or Grid.distance_chebyshev(unit.cell, enemy.cell) <= weapon.weapon_def.effective_range
	)
	var far_enough: bool = (
		Grid.distance_chebyshev(unit.cell, enemy.cell) >= preferred_range and within_effective
	)
	var covered_enough: bool = (
		not weight_cover or is_covered_from(unit.cell, enemy.cell, state, unit)
	)
	# taskblock17-1 Pass B: an AI never CHOOSES to shoot through its own
	# ally — friendly fire is still mechanically possible (a player can
	# still line one up), this only stops the AI from picking it.
	var clear_from_here: bool = not _ally_in_firing_line(unit, enemy, unit.cell, state)
	var firing_action: CombatAction = (
		_firing_action_for(unit, weapon_id, enemy.cell, state) if weapon_id != &"" else null
	)
	var fired_without_moving: bool = (
		firing_action != null
		and far_enough
		and covered_enough
		and clear_from_here
		and queue.enqueue(firing_action, state)
	)

	if fired_without_moving:
		_fire_remaining_shots(unit, weapon_id, enemy, state, queue, 1)
	else:
		var queued_before: int = queue.actions.size()
		var best_cell: Vector2i = _pick_engagement_position(
			unit, enemy, state, preferred_range, weight_cover, weapon
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
			var repositioned_firing_action: CombatAction = _firing_action_for(
				unit, weapon_id, enemy.cell, state
			)
			if repositioned_firing_action != null:
				queue.enqueue(repositioned_firing_action, state)
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
			# taskblock-24 Pass A: which action id to step out and fire WITH
			# — `_provided_firing_action_id`, NOT `_preferred_firing_action_id`:
			# this branch is only ever reached when firing from HERE is
			# already illegal (that's why nothing above queued a shot), so
			# gating on is_legal at the pre-move cell would always fail and
			# this fallback could never trigger at all. Real legality
			# (AP/LoS/range from the stepped-out cell) is still validated
			# for real inside `build_triple`'s own `queue.enqueue`.
			var step_out_action_id: StringName = _provided_firing_action_id(unit, weapon_id)
			if step_out_action_id != &"":
				var step_out_queue: ActionQueue = StepOutPlanner.assemble_for_shoot(
					state, unit, step_out_action_id, weapon_id, enemy
				)
				if step_out_queue != null:
					for action: CombatAction in step_out_queue.actions:
						queue.enqueue(action, state)
		# taskblock-19 Pass F: "the AI holds when its best option is wait
		# for an ally to move first." Triggers whenever the turn ends with
		# NO shot fired specifically because its own ally was in the way —
		# independent of whether it also repositioned (moving to a better
		# defensive spot and deferring the shot are not in conflict). A
		# real HoldAction (not a heuristic-only weight): `queue.enqueue`
		# re-validates it can legally hold before committing.
		# taskblock-24 Pass A: "did the AI fire" broadens from `is
		# AttackAction` to `is AttackAction or is BurstAction` — a bursting
		# AI must count as having fired, not read as having done nothing.
		var attack_fired: bool = queue.actions.slice(queued_before).any(
			func(action: CombatAction) -> bool:
				return action is AttackAction or action is BurstAction
		)
		# taskblock-24 Pass C: "if I can't improve my shot by moving/
		# firing this turn, and an enemy is likely to enter my arc, hold
		# overwatch instead of wasting the turn." `not attack_fired`, not
		# "nothing queued at all" — a repositioning move that still can't
		# fire is exactly the "moving didn't help either" case this covers,
		# and holding overwatch from wherever it ended up is strictly
		# better than a move that goes nowhere useful.
		if not attack_fired:
			var overwatch_action: OverwatchAction = _consider_overwatch(
				unit, enemy, state, playstyle, weight_cover
			)
			if overwatch_action != null and queue.enqueue(overwatch_action, state):
				return queue
		var held: bool = false
		if not attack_fired and final_blocked:
			held = queue.enqueue(HoldAction.new(unit), state)
		if not held:
			_face_if_nothing_else_queued(unit, enemy, state, queue, queued_before)
			queue.enqueue(EndTurnAction.new(unit, mission), state)
		return queue

	queue.enqueue(EndTurnAction.new(unit, mission), state)
	return queue


## "Otherwise, if this is a landing-squad unit with the gather objective
## still open -> walk to the resource node and gather it; otherwise walk
## to extraction and call it." Shared by every playstyle — none of this
## is combat behaviour.
static func _plan_non_combat_turn(
	unit: Unit, state: CombatState, mission: MissionState, queue: ActionQueue
) -> ActionQueue:
	if unit.squad_id != 0:
		queue.enqueue(EndTurnAction.new(unit, mission), state)
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
		# taskblock-22 Pass A2: the player squad has no fast extract button —
		# it walks to its own tile and simply ends its turn there, same as
		# any other turn; EndTurnAction's own hold-check picks up "still on
		# the tile" from here and starts/advances the passive hold.
		var extraction_cell: Vector2i = mission.extraction_cells[0]
		if unit.cell != extraction_cell:
			_path_toward(unit, extraction_cell, state, queue)

	queue.enqueue(EndTurnAction.new(unit, mission), state)
	return queue


## taskblock-21 Pass D2: true only if some attached weapon part can ACTUALLY
## fire right now — reuses `WeaponRows.build`'s own `active` computation
## (hp, wounds, and a real operable manipulator, taskblock-20 D) verbatim,
## never a re-derived "does a weapon-ish part merely exist" check. This is
## deliberately a different, stricter question than `_find_weapon_id`'s own
## "first living part with damage > 0" (used elsewhere by the combat
## planners to pick WHICH weapon to fire) — a destroyed manipulator or a
## disabling wound leaves a weapon part alive but genuinely unusable, and
## "no functional weapon" must catch that too.
static func _has_functional_weapon(unit: Unit) -> bool:
	for row: WeaponRow in WeaponRows.build(unit):
		if row.active:
			return true
	return false


## "Paths to its nearest team extraction tile and escapes... the escape
## uses the existing EXTRACTED path, not a new outcome." No reachable
## extraction cells at all (a mission this pass's own team-coded field was
## never populated for) simply ends the turn — the same degenerate
## "nowhere to go" case `_plan_non_combat_turn` already accepts.
##
## `mission.extraction_cells` is only a valid fallback for the player's own
## squad — it's the pre-Pass-D, squad-agnostic-in-name-only field every
## single-player mission already populates with the LANDING squad's zone.
## An enemy squad with no team-coded entry has no defined extraction tile
## of its own at all; falling back to the player's own zone would send a
## disarmed enemy walking toward the player's landing point — never
## correct, and exactly the degenerate "nowhere to go" case above already
## covers correctly.
##
## taskblock-22 Pass A2: the asymmetry means what happens once ON the tile
## now differs by squad. A non-player squad still queues `ExtractAction`
## verbatim (its own fast, 1-AP, immediate path — unchanged from tb21).
## The player's own squad gets no such button at all: it just stands there
## and ends its turn like any other — `EndTurnAction`'s own hold-check
## picks up "still on the tile" from here and starts/advances the hold
## automatically, no separate action to queue.
static func _plan_flee(unit: Unit, state: CombatState, mission: MissionState) -> ActionQueue:
	var queue := ActionQueue.new(unit)
	var cells: Array = mission.team_extraction_cells.get(unit.squad_id, [])
	if cells.is_empty() and unit.squad_id == mission.player_squad_id:
		cells = mission.extraction_cells
	if cells.is_empty():
		queue.enqueue(EndTurnAction.new(unit, mission), state)
		return queue

	var target_cell: Vector2i = _nearest_cell(unit.cell, cells)
	if unit.cell == target_cell:
		if unit.squad_id != mission.player_squad_id:
			queue.enqueue(ExtractAction.new(mission, unit), state)
	else:
		_path_toward(unit, target_cell, state, queue)

	queue.enqueue(EndTurnAction.new(unit, mission), state)
	return queue


## Plain chebyshev distance, no reachability weighting (mirrors
## `_path_toward`'s own internal distance metric) — extraction tiles sit at
## a team's own spawn, typically open ground, so this stays a simple
## nearest-by-distance pick rather than a full pathfind-every-candidate
## search.
static func _nearest_cell(from: Vector2i, cells: Array) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_dist: int = Grid.distance_chebyshev(from, best)
	for cell: Vector2i in cells:
		var d: int = Grid.distance_chebyshev(from, cell)
		if d < best_dist:
			best_dist = d
			best = cell
	return best


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
	while fired < MAX_SHOTS_PER_TURN:
		var firing_action: CombatAction = _firing_action_for(unit, weapon_id, enemy.cell, state)
		if firing_action == null or not queue.enqueue(firing_action, state):
			break
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
	# taskblock-19 Pass C: the same predicate AttackAction.is_legal() uses
	# for range — never a second, independently-maintained range check the
	# planner's own picks could legally-fail against at resolve time.
	return (
		RangeModel.is_in_max_range(weapon, range_cells)
		and not RangeModel.blocks_min_range(weapon, range_cells)
	)


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
##
## taskblock-19 Pass C3: `weapon`'s own authored `effective_range`
## (`_target_distance`) supersedes the flat `preferred_range` pull when
## present — "moves closer to reach effective." This alone reproduces
## "...unless there's no cover available, in which case it holds and
## takes the degraded shot": COVER_SCORE_BONUS already dominates the
## distance penalty (its own doc comment), so a covered-but-degraded cell
## still outscores an uncovered cell that's merely closer to effective —
## no separate "hold" branch needed, the existing cover-first scorer
## already produces it once the pull target is the real weapon range.
static func _pick_engagement_position(
	unit: Unit,
	enemy: Unit,
	state: CombatState,
	preferred_range: int,
	weight_cover: bool,
	weapon: Part = null
) -> Vector2i:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	if not reachable.has(unit.cell):
		reachable.append(unit.cell)

	# taskblock-26 (CC, re-diagnosing B2): on a map where the enemy sits
	# around a bend no single turn's own movement budget can clear (a real,
	# common shape on generated maps — confirmed on live bouts, not just a
	# hand-built fixture), NOT ONE reachable cell has real LOS this turn.
	# `NO_LOS_PENALTY`'s own self-cell exemption then makes "stay exactly
	# where I am" categorically beat every other candidate regardless of
	# real progress, because only the self cell escapes the penalty — the
	# unit freezes forever, never taking the first step around the bend,
	# which is precisely the frozen-at-a-wall behavior B2 was reported
	# against. `any_reachable_has_los` gates the whole penalty on there
	# being an actual LOS cell to prefer AT ALL — with none reachable, every
	# cell (including the self cell) scores on plain progress toward
	# `preferred_range` instead, so advancing around the bend genuinely
	# outscores standing still.
	var any_reachable_has_los := false
	for cell: Vector2i in reachable:
		if LoS.has_los(state.grid, cell, enemy.cell):
			any_reachable_has_los = true
			break

	var best_cell: Vector2i = unit.cell
	var best_score: float = _engagement_score(
		unit.cell, enemy, state, unit, preferred_range, weight_cover, weapon, any_reachable_has_los
	)
	for cell: Vector2i in reachable:
		var score: float = _engagement_score(
			cell, enemy, state, unit, preferred_range, weight_cover, weapon, any_reachable_has_los
		)
		if score > best_score:
			best_score = score
			best_cell = cell
	return best_cell


## taskblock-19 Pass C3: the distance the scorer pulls toward — the
## weapon's own `effective_range` when authored (a real, concrete number
## beats the flagged flat `preferred_range` guess), else `preferred_range`
## unchanged (an un-migrated/undecorated weapon keeps the old behaviour
## exactly).
static func _target_distance(weapon: Part, preferred_range: int) -> float:
	if weapon != null and weapon.weapon_def != null and weapon.weapon_def.effective_range > 0.0:
		return weapon.weapon_def.effective_range
	return float(preferred_range)


static func _engagement_score(
	cell: Vector2i,
	enemy: Unit,
	state: CombatState,
	self_unit: Unit,
	preferred_range: int,
	weight_cover: bool,
	weapon: Part = null,
	any_reachable_has_los: bool = true
) -> float:
	var distance: int = Grid.distance_chebyshev(cell, enemy.cell)
	var distance_penalty: float = absf(float(distance) - _target_distance(weapon, preferred_range))
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
	# taskblock-19 Pass C3: "only closes inside min_range if forced" —
	# penalized, not excluded, so a genuinely forced close (nothing else
	# reachable clears min_range either) still wins as the least-bad cell.
	var min_range_penalty: float = (
		MIN_RANGE_PENALTY if RangeModel.blocks_min_range(weapon, distance) else 0.0
	)
	# taskblock-19 Pass E: landing adjacent to a living enemy with a
	# two-handed weapon disarms it for the whole turn (Suppression.
	# blocks_weapon) — the AI avoids CHOOSING that, same "penalty, not
	# exclusion" posture as every other term here.
	var suppression_penalty: float = (
		SUPPRESSION_PENALTY
		if (
			Suppression.is_long_gun(weapon)
			and not Suppression.adjacent_living_enemies(state, self_unit, cell).is_empty()
		)
		else 0.0
	)
	# taskblock-19 Pass E / taskblock-25 Pass E: leaving the unit's OWN
	# current adjacency to reach `cell` draws a real melee attack of
	# opportunity — weighted here through the exact same speculative query
	# the real mid-move hook resolves against, never a second notion of
	# "who's leaving whom."
	var opportunity_penalty: float = (
		OPPORTUNITY_ATTACK_PENALTY
		if not (
			Suppression
			. would_trigger_opportunity_attack(state, self_unit, self_unit.cell, cell)
			. is_empty()
		)
		else 0.0
	)
	# taskblock-26 Pass B2: "a standoff cell with no line is not a valid
	# standoff." Dominant over every other term here, even
	# ALLY_BLOCKED_PENALTY (without LOS there's no shot to weigh an ally
	# being in the way OF at all) — but still a PENALTY, not an exclusion:
	# if truly nothing reachable has LOS, the least-bad cell still wins
	# rather than the planner freezing in place. The same `LoS.has_los`
	# primitive `is_covered_from`/`AttackAction.is_legal` already read,
	# never a second, parallel visibility test.
	#
	# `cell == self_unit.cell` is exempt ONLY when some OTHER reachable
	# cell actually has real LOS this turn (`any_reachable_has_los`):
	# staying put is free, and a covered ORIGIN specifically is what
	# `StepOutPlanner`'s own move/fire/return triple exists to handle
	# (tb18) — that mechanism only engages at all when `best_cell ==
	# unit.cell` (`_plan_ranged`'s own fallback branch). Penalizing the
	# origin in THAT case would make this generic scorer grab the first
	# LOS-having cell it can merely REACH instead, even when it can't
	# actually afford to fire from there once it's spent its move —
	# starving the smarter, budget-validated fallback of the "didn't
	# reposition" signal it's gated on.
	#
	# taskblock-26 (CC, re-diagnosing B2): re-fought on a real generated
	# map — a wall/corridor bend a single turn's own movement can't clear
	# has NO reachable cell with LOS at all. Exempting the self cell
	# there too made "stand still" categorically beat every other
	# candidate (only the self cell escaped the penalty), freezing the
	# unit at its own spawn turn after turn — never taking the first step
	# around the bend, the exact "squares off... never takes space"
	# symptom the bug was reported against, just on a map big enough that
	# one turn can't reach LOS at all. With NO real LOS cell reachable
	# this turn, the penalty doesn't fire for ANY cell (self included),
	# so plain progress toward `preferred_range` — moving around the bend
	# — genuinely outscores freezing in place.
	var no_los_penalty: float = (
		0.0
		if (
			not any_reachable_has_los
			or cell == self_unit.cell
			or LoS.has_los(state.grid, cell, enemy.cell)
		)
		else NO_LOS_PENALTY
	)
	# taskblock-27 (CC, re-diagnosing B2 a SECOND time — confirmed still
	# frozen on a real 6-unit bout's own combat.log, every playstyle, from
	# Turn 2 onward): the previous fix's own "plain progress toward
	# preferred_range" fallback plateaus the instant a unit reaches its
	# own preferred numeric distance band — even fully walled off, since
	# moving further doesn't reduce |distance-preferred| once it's
	# already at its minimum. That's precisely the common steady state:
	# most spawns close to roughly the right distance within a turn or
	# two, then freeze there forever, still blind. When nothing reachable
	# has real LOS, this replaces `distance_penalty` as the PRIMARY signal
	# with `LoS.obstruction_count` — how many opaque cells stand between
	# `cell` and the enemy — which strictly decreases as a unit works its
	# way around a corner even while raw distance briefly plateaus or
	# worsens (the one thing a "match this number" metric can't express).
	# Weighted to dominate any plausible `distance_penalty` spread on a
	# real map, so this always wins the tiebreak when a genuinely
	# less-obstructed cell is reachable; `distance_penalty` itself still
	# applies underneath (unweighted here) to rank equally-obstructed
	# candidates by the ordinary standoff preference.
	var obstruction_penalty: float = (
		0.0
		if any_reachable_has_los
		else float(LoS.obstruction_count(state.grid, cell, enemy.cell)) * OBSTRUCTION_PENALTY_WEIGHT
	)
	return (
		cover_bonus
		- distance_penalty
		- obstruction_penalty
		- blocked_penalty
		- min_range_penalty
		- suppression_penalty
		- opportunity_penalty
		- no_los_penalty
	)


static func _find_weapon_id(unit: Unit) -> StringName:
	for part: Part in unit.shell.living_parts():
		if part.damage > 0.0:
			return part.id
	return &""


## taskblock-24 Pass A/B1: which firing action id `weapon_id`'s own part
## should fire WITH right now — the same `ActionCatalog.provider_for`
## seam the player's own action bar reads (never a re-derived notion of
## what this weapon provides), preferring `&"burst"` when the weapon
## provides it AND it's actually legal right now (`is_legal` is the one
## true afford/range/LoS check, never a re-derived guess that could drift
## from it) — falling back to `&"shoot"` only when burst itself isn't.
## `&""` if the weapon provides no legal firing action at all.
static func _preferred_firing_action_id(
	unit: Unit, weapon_id: StringName, target_cell: Vector2i, state: CombatState
) -> StringName:
	var weapon: Part = unit.shell.find_part(weapon_id)
	if weapon == null:
		return &""
	if ActionCatalog.provider_for(unit, &"burst") == weapon:
		var burst: CombatAction = ActionCatalog.build_firing_action(
			&"burst", unit, weapon_id, target_cell
		)
		if burst != null and burst.is_legal(state):
			return &"burst"
	if ActionCatalog.provider_for(unit, &"shoot") == weapon:
		var shot: CombatAction = ActionCatalog.build_firing_action(
			&"shoot", unit, weapon_id, target_cell
		)
		if shot != null and shot.is_legal(state):
			return &"shoot"
	# taskblock-25 Pass F: a weapon that provides neither shoot nor burst
	# (a melee-only stab provider, e.g. PSYCHOTIC's own preferred weapon
	# or the baseline punch) falls through to here — the same
	# ActionCatalog seam, never a second, hardcoded "this is melee" branch.
	if ActionCatalog.provider_for(unit, &"stab") == weapon:
		var stab: CombatAction = ActionCatalog.build_firing_action(
			&"stab", unit, weapon_id, target_cell
		)
		if stab != null and stab.is_legal(state):
			return &"stab"
	return &""


## The same burst-over-shoot preference as `_preferred_firing_action_id`,
## but WITHOUT requiring it to already be legal from here — for a caller
## (the step-out fallback) that's reached PRECISELY because firing from
## here is currently illegal; gating on is_legal at the pre-move cell
## would make this always return `&""` and the fallback could never
## trigger. `&""` only when the weapon provides no firing action at all.
static func _provided_firing_action_id(unit: Unit, weapon_id: StringName) -> StringName:
	var weapon: Part = unit.shell.find_part(weapon_id)
	if weapon == null:
		return &""
	if ActionCatalog.provider_for(unit, &"burst") == weapon:
		return &"burst"
	if ActionCatalog.provider_for(unit, &"shoot") == weapon:
		return &"shoot"
	return &""


## The real `CombatAction` instance for `_preferred_firing_action_id`'s own
## pick — null if the weapon provides no legal firing action at all,
## same "nothing to enqueue" contract every other speculative pick in
## this planner already has.
static func _firing_action_for(
	unit: Unit, weapon_id: StringName, target_cell: Vector2i, state: CombatState
) -> CombatAction:
	var action_id: StringName = _preferred_firing_action_id(unit, weapon_id, target_cell, state)
	if action_id == &"":
		return null
	return ActionCatalog.build_firing_action(action_id, unit, weapon_id, target_cell)


## taskblock-24 Pass C: "AGGRESSIVE never — closes and fires, doesn't
## wait." Every other playstyle at least SITUATIONALLY considers holding
## overwatch instead of wasting a turn with nothing better to do — this is
## the one hard exclusion; `_consider_overwatch`'s own remaining checks
## (catalog-gated, cover for COVER_SEEKER, a real threatened enemy) decide
## the rest.
static func _playstyle_considers_overwatch(playstyle: StringName) -> bool:
	return playstyle != &"AGGRESSIVE"


## Whether declaring overwatch with `weapon_id` right now would ALREADY
## threaten some living enemy at its own current cell — reuses
## `Overwatch.would_trigger_at` (the exact predicate the mechanic itself
## fires on) rather than re-deriving arc/range/LoS geometry a second time,
## the same "no second, drifted answer" posture this codebase applies
## everywhere else. A real, concrete proxy for "an enemy is likely to
## advance into my arc": if one is already within it, or close enough that
## a single further step keeps it there, this is as good a signal as this
## codebase has without inventing a movement-prediction system outright.
## Temporarily arms `unit`'s own `overwatch_weapon_id` to ask, then
## restores whatever it was — never mutates state a caller didn't already
## choose to commit to.
static func _overwatch_would_threaten_a_living_enemy(
	unit: Unit, weapon_id: StringName, state: CombatState
) -> bool:
	var previous_weapon_id: StringName = unit.overwatch_weapon_id
	unit.overwatch_weapon_id = weapon_id
	var threatens := false
	for candidate: Unit in state.units:
		if candidate.squad_id == unit.squad_id or not candidate.alive:
			continue
		if Overwatch.would_trigger_at(state, candidate, candidate.cell).has(unit):
			threatens = true
			break
	unit.overwatch_weapon_id = previous_weapon_id
	return threatens


## taskblock-24 Pass C: the AI's own consideration of a PROVIDED,
## non-firing tactical action — overwatch is the first real consumer of
## this scaffold, not a bot-type hardcode. Gated by the SAME
## `ActionCatalog.provider_for` seam the player's own action bar reads
## (`&"overwatch"`, requires_action `&"shoot"` — a weaponless unit, or one
## whose weapon doesn't provide it, can't, for free); COVER_SEEKER
## (`weight_cover`) additionally requires actually holding from cover,
## matching its own "overwatches from cover when holding position" — the
## same `weight_cover` flag that already distinguishes it from
## SKIRMISHER/MARKSMAN elsewhere in this planner. Returns null (never
## invents an action) unless every check, including a final real
## `is_legal`, passes.
static func _consider_overwatch(
	unit: Unit, enemy: Unit, state: CombatState, playstyle: StringName, weight_cover: bool
) -> OverwatchAction:
	if not _playstyle_considers_overwatch(playstyle):
		return null
	# taskblock-24 Pass C: `ActionCatalog.actions_for` itself, not a bare
	# `provider_for` lookup — `provider_for` alone doesn't honor overwatch's
	# own `requires_action == &"shoot"` (docs/07 E3: "the instrument still
	# needs it even once its provider moves off the gun"), and this must
	# see EXACTLY what the player's own action bar would offer, never a
	# looser AI-only reading of "catalog-gated."
	var offered := false
	for def: ActionDef in ActionCatalog.actions_for(unit):
		if def.id == &"overwatch":
			offered = true
			break
	if not offered:
		return null
	var weapon: Part = ActionCatalog.provider_for(unit, &"overwatch")
	if weapon == null:
		return null
	if weight_cover and not is_covered_from(unit.cell, enemy.cell, state, unit):
		return null
	if not _overwatch_would_threaten_a_living_enemy(unit, weapon.id, state):
		return null
	var action := OverwatchAction.new(unit, weapon.id)
	return action if action.is_legal(state) else null


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
