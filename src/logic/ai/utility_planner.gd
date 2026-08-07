class_name UtilityPlanner
extends RefCounted

## `(unit, view, mission, profile, pacer) -> ActionQueue`. Pure, deterministic, no
## SceneTree, and an action-queue PRODUCER rather than a second turn system — human
## and AI paths emit the same queue through the same `CombatState.resolve_until`.
##
## `docs/11` has the model: scoring, resumability, why intelligence gates
## information, and why batches amortize rather than act together. What follows is
## how this file implements it and the three traps it has already fallen into.
##
## ## One loop, not a cascade
##
## Score every (cell, action) pair, take the best, do it. **Precedence is not
## written down anywhere** — it emerges from authored weights, so changing what a
## unit prefers is a `.tres` edit rather than a re-ordering of branches. The
## planner this replaced encoded precedence as a hand-ordered branch cascade with
## seven penalty constants each sized to dominate the one below it; that structure
## is why it reached 1400 lines and eight file-cap bumps.
##
## ## A turn is several selections, and each one can fail
##
## After committing a choice the planner re-scores from the settled cell and
## selects again, up to `MAX_SELECTIONS`. Three rules govern that loop, each
## learned the hard way:
##
## - **A candidate's cell is where the action HAPPENS, so committing to it means
##   going there first** — whatever the action is. `_commit` originally pathed only
##   when the executor was itself a move, so `shoot@(3,0)`, chosen for the standoff
##   at (3,0), was fired from wherever the unit already stood. Units traded shots
##   across a corridor forever, and the decision log said so in every line.
## - **A refused action removes one option; it does not end the turn.**
##   `ActionQueue.enqueue` is the only thing that knows what a unit can afford from
##   where it will be standing, so "the scorer wanted this and the executor said
##   no" is ordinary. Stopping there left a marksman whose shot was unaffordable
##   ending its turn without ever reaching the overwatch it should have held.
## - **An `ends_turn` action is a substitute for acting, not a coda to it.**
##   `HoldAction` keeps the unit current — that is what deferring means — so
##   queueing anything behind it, or letting it win after the unit has already
##   acted, livelocks the bout.
##
## ## No positive-utility action is a real answer, and it is named
##
## Everything can legitimately score at or below the veto floor — a state the
## branch cascade could not express, since a cascade always falls through to its
## last branch whether or not that branch made sense. That state is `Panic`: it is
## logged with a reason and takes a visible action, never a silent empty turn. See
## `panic.gd` for why the label matters more than the escape.

## The hard cap on selections in one turn. **Not a shot limit** — a limit on how
## many times the scorer is consulted before the turn is forced to end, so a
## repeatable action whose enqueue keeps succeeding cannot spin.
##
## **Deliberately above the AP ceiling** (`Unit.DEFAULT_MAX_AP` is 6, and a shot
## costs at least 1), so that in ordinary play the thing that stops a unit shooting
## is *running out of AP* and not this constant. It was 6 for one commit and the
## two were indistinguishable — a backstop sitting exactly at the real limit is a
## backstop you cannot tell apart from the design, and
## `test_the_shot_count_is_decided_by_ap_not_by_the_selection_cap` exists to keep
## them apart. Flagged, not a tuned design number.
const MAX_SELECTIONS := 10

## taskblock-45 Pass B: how many (cell, action) pairs were scored since the last
## reset, and how many turns ended with nothing above the veto floor. Diagnostics
## for tests and the Pass D bench; never read by planning.
static var candidates_scored: int = 0
static var empty_decisions: int = 0


static func plan_turn(
	unit: Unit,
	view: WorldView,
	mission: MissionState,
	profile_id: StringName = &"",
	pacer: PlanPacer = null
) -> ActionQueue:
	var state: CombatState = view.canonical_state_for_resolvers()
	var queue := ActionQueue.new(unit)
	if pacer != null:
		pacer.begin()

	# Before deciding anything, write down what this unit can currently see — a
	# no-op for a tier with no memory (`WorldView.record_sightings`). Done first so
	# a unit's own sighting is available to it this turn rather than next.
	view.record_sightings(unit)

	var profile: UtilityProfile = DataLibrary.get_utility_profile(profile_id)
	var pool: Array[UtilityActionDef] = _pool_for(unit)
	var context: UtilityContext = UtilityContext.build(unit, view, mission)
	# tb45 Pass C: the batch's coarse call, in force for the rest of this turn's
	# scoring. Dormant — and therefore fully neutral — for every `batch_id == 0`
	# unit, which is every unit until one is assigned by hand.
	context.set_batch_objective(_batch_objective(unit, view, context, profile))
	# taskblock-46 Pass E: an Elite unit looks a turn ahead before it decides
	# anything. A no-op — and free — for every other tier.
	await _apply_lookahead(context, pool, profile, pacer)
	var chosen_ids: Array[StringName] = []
	# Actions the scorer picked and the executor then refused. **Refusal is not the
	# end of the turn, it is the removal of one option.**
	var refused_ids: Array[StringName] = []

	for selection in range(MAX_SELECTIONS):
		var candidates: Array = await _score_all(
			context, pool, profile, chosen_ids, refused_ids, pacer
		)
		var scores: Array[float] = []
		for candidate: Dictionary in candidates:
			scores.append(float(candidate["score"]))
		var winner: int = UtilityScorer.best_index(scores)
		# Logged for EVERY selection, including the one that chooses nothing — "it
		# considered these and wanted none of them" is a decision, and the round
		# that produces no action is exactly the one someone will ask about.
		AiDecisionLog.emit_utility_decision(
			state,
			unit,
			candidates,
			winner,
			unit.intelligence_tier,
			profile_id,
			context.visible_unit_ids()
		)
		if winner < 0:
			if selection == 0:
				# taskblock-46 Pass D: nothing scored on the FIRST selection means the
				# turn produced no action at all — `Panic`, named and logged, rather
				# than a silent empty turn. A later selection finding nothing is
				# ordinary: it means the unit has finished acting.
				empty_decisions += 1
				var offered := 0
				for candidate: Dictionary in candidates:
					if bool(candidate["offered"]):
						offered += 1
				var reason: StringName = Panic.reason_for(offered, pacer != null and pacer.aborted)
				Panic.emit(state, unit, reason, offered)
				queue.enqueue(Panic.action_for(unit, mission, state), state)
				return queue
			break
		# A refused winner re-scores without it rather than ending the turn — see
		# the second of the three loop rules at the top of this file.
		var action_id: StringName = candidates[winner]["action_id"]
		if not _commit(candidates[winner], context, queue, state):
			refused_ids.append(action_id)
			continue
		chosen_ids.append(action_id)
		if _find_action(context, action_id).ends_turn:
			# Nothing may be queued behind it, including the backstop below.
			return queue

	# Always last, and always attempted: `EndTurnAction.is_legal` is deliberately
	# ALWAYS legal for the current unit, so a turn that queued nothing at all still
	# spins the board forward rather than stalling on a unit that cannot act.
	queue.enqueue(EndTurnAction.new(unit, mission), state)
	return queue


## taskblock-46 Pass E: runs the Elite lookahead and publishes its result onto the
## context, so the real selection loop below scores with the prediction in hand.
##
## ## Why this costs a whole extra scoring pass
##
## The lookahead's expensive ply is paid per candidate, so it can only run over a
## shortlist — and a shortlist is only worth having if it holds the cells that
## actually matter. Ordering by anything cheaper (distance to the enemy, say) would
## search the cells a unit is most likely to reject.
##
## So the pass below is a **throwaway scoring run with no prediction in it**, used
## for nothing except ranking cells. Its cost falls on Elite units alone; every
## other tier returns before the first candidate is scored. That is the whole trade:
## the tier that thinks hardest is the tier that thinks slowest, which is the tell
## `PlanPacer.thinking_label` was built to make legible rather than hide.
##
## **The throwaway scores are never reused.** They were taken against a context that
## did not know about threat, so keeping them would mean deciding partly on numbers
## the prediction was supposed to correct — the subtle version of scoring the same
## thing twice and believing the wrong copy.
static func _apply_lookahead(
	context: UtilityContext,
	pool: Array[UtilityActionDef],
	profile: UtilityProfile,
	pacer: PlanPacer
) -> void:
	if not UtilityLookahead.searches(context.unit):
		return
	var ranking: Array = await _score_all(
		context, pool, profile, [] as Array[StringName], [] as Array[StringName], pacer
	)
	# Best score per cell, then cells in descending order of it. Per CELL rather than
	# per candidate because the lookahead answers a question about a place, and a
	# cell that is good for three actions must not crowd two others off the list.
	var best_per_cell: Dictionary = {}
	for candidate: Dictionary in ranking:
		var cell: Vector2i = candidate["cell"]
		var score: float = float(candidate["score"])
		if score > float(best_per_cell.get(cell, -1.0)):
			best_per_cell[cell] = score
	var ordered: Array[Vector2i] = []
	for cell: Vector2i in best_per_cell:
		ordered.append(cell)
	ordered.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var left: float = float(best_per_cell[a])
			var right: float = float(best_per_cell[b])
			# Ties break on the cell itself, never on Dictionary iteration order —
			# same reason `SearchRoute` sorts before choosing. A search whose
			# shortlist depended on hash order would be reproducible today and
			# quietly not tomorrow.
			if left == right:
				return (a.x * 100000 + a.y) < (b.x * 100000 + b.y)
			return left > right
	)
	context.set_threats(await UtilityLookahead.threat_map(context, ordered, pacer))


## The objective this unit plans under (`docs/11`: batches amortize).
##
## **The branch below is not "am I the leader" but "has anyone led yet"** — the
## leader is derived, so a unit leads by virtue of asking first. Tier-gated before
## any work is done: a unit with no blackboard can neither read an objective nor
## record one, so it plans alone and does not pay to choose one that gets discarded.
static func _batch_objective(
	unit: Unit, view: WorldView, context: UtilityContext, profile: UtilityProfile
) -> StringName:
	if unit.batch_id == 0 or not view.has_blackboard(unit):
		return BatchPlan.NO_OBJECTIVE
	var following: Dictionary = view.batch_plan_for(unit)
	if not following.is_empty():
		return following.get("objective", BatchPlan.NO_OBJECTIVE)
	# taskblock-46 Pass E: reading a plan and MAKING one are different tier
	# capabilities. A Trained unit acting first follows nothing and sets nothing.
	if not view.may_set_objective(unit):
		return BatchPlan.NO_OBJECTIVE
	var chosen: StringName = BatchObjective.choose(context, profile)
	# The destination recorded alongside it is the leader's own cell and is NOT
	# what followers consume — that was taskblock-43 Pass D's model and this pass
	# replaces it. It stays because the old planner still reads it for this block
	# only, and because the board's leader badge derives from the same record.
	view.claim_batch_lead(unit, context.origin(), chosen)
	return chosen


## Every (cell, action) pair, scored. One `inputs`/`predicates` pair is built per
## CELL and shared across the pool — which is what makes considerations genuinely
## shared rather than recomputed per action.
static func _score_all(
	context: UtilityContext,
	pool: Array[UtilityActionDef],
	profile: UtilityProfile,
	chosen_ids: Array[StringName],
	refused_ids: Array[StringName],
	pacer: PlanPacer
) -> Array:
	var candidates: Array = []
	for cell: Vector2i in context.candidate_cells:
		# tb44 Pass D's slicing point, unchanged in shape: the per-candidate loop is
		# the only thing here big enough to be worth suspending inside.
		if pacer != null:
			if pacer.should_abort():
				break
			if pacer.note_candidate():
				await pacer.frame_signal
		var inputs: Dictionary = context.inputs_for(cell)
		var predicates: Dictionary = context.predicates_for(cell)
		for action: UtilityActionDef in pool:
			if action.id in refused_ids:
				continue
			if action.id in chosen_ids and not action.repeatable:
				continue
			# Only offered while the turn is still empty — a substitute for acting,
			# not a coda to it. See the third loop rule at the top of this file.
			if action.ends_turn and not chosen_ids.is_empty():
				continue
			candidates_scored += 1
			var offered: bool = UtilityScorer.preconditions_hold(action, predicates)
			var trace: Array = []
			# An unoffered action still gets a candidate entry, with `offered`
			# false and no trace — that is what lets the decision log answer "not
			# offered" distinctly from "offered and scored zero", which are
			# different answers to "why didn't it do that".
			var score: float = (
				UtilityScorer.score(action, inputs, profile, trace) if offered else 0.0
			)
			(
				candidates
				. append(
					{
						"label": "%s@(%d,%d)" % [action.id, cell.x, cell.y],
						"action_id": action.id,
						"cell": cell,
						"score": score,
						"offered": offered,
						"trace": trace,
					}
				)
			)
	return candidates


## Turns the winning candidate into real queued actions and re-bases the context on
## wherever the unit ends up. False when nothing could be enqueued, so the caller
## drops that option rather than re-selecting it forever.
##
## **The candidate's cell is where the action happens, so getting there is part of
## committing to it** — the first of the three loop rules at the top of this file.
static func _commit(
	winner: Dictionary, context: UtilityContext, queue: ActionQueue, state: CombatState
) -> bool:
	var action: UtilityActionDef = _find_action(context, winner["action_id"])
	if action == null:
		return false
	var cell: Vector2i = winner["cell"]
	var moved := false

	if cell != context.origin():
		# **The one pathfind per selection.** Scoring ranked candidates on a
		# chebyshev proxy; the real route is computed only for the cell that won —
		# one `astar` call per selection rather than one per candidate.
		var pathfinder := Pathfinder.for_unit(context.view.grid, context.unit)
		var path: Array[Vector2i] = pathfinder.astar(context.unit.cell, cell)
		if path.size() < 2:
			return false
		if not queue.enqueue(MoveAction.new(context.unit, path), state):
			return false
		moved = true
		context.settle_at(cell)

	if UtilityExecutors.needs_path(action):
		# The move WAS the action. Winning its own cell is a contradiction
		# `cell_is_elsewhere` already forbids, so arriving here without having moved
		# is a refusal rather than a no-op.
		return moved

	var built: CombatAction = UtilityExecutors.build(
		action, context.unit, context.target, [], context.weapon_id, context.mission
	)
	# A move that landed followed by an action that could not be built or could not
	# be paid for is still real progress — the turn keeps the move rather than
	# discarding it, and the caller re-scores from the new cell.
	if built == null:
		return moved
	if not queue.enqueue(built, state):
		return moved
	context.settle_at(cell)
	return true


static func _find_action(context: UtilityContext, action_id: StringName) -> UtilityActionDef:
	for action: UtilityActionDef in _pool_for(context.unit):
		if action.id == action_id:
			return action
	return null


## The authored pool, filtered to what `unit`'s tier is offered.
##
## An action with an empty `tiers` list is offered to every tier, which is the
## whole Pass B pool — the gap between `MINDLESS` and `TRAINED` is information, not
## the action list.
static func _pool_for(unit: Unit) -> Array[UtilityActionDef]:
	var pool: Array[UtilityActionDef] = []
	for action: UtilityActionDef in DataLibrary.utility_actions_pool():
		if action.tiers.is_empty() or unit.intelligence_tier in action.tiers:
			pool.append(action)
	return pool
