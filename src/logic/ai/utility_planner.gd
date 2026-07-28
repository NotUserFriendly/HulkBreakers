class_name UtilityPlanner
extends RefCounted

## taskblock-45 Pass B: **the planner the block exists to build.**
##
## `(unit, view, mission, profile, pacer) -> ActionQueue`, the identical signature
## and identical contract the old engagement-score planner has: pure, deterministic,
## no SceneTree, and an action-queue PRODUCER rather than a second turn system.
## Human and AI paths still emit the same queue through the same
## `CombatState.resolve_until` (CLAUDE.md: no parallel systems).
##
## ## What replaces what
##
## The old planner decided a turn with a hand-ordered cascade of branches — fire in
## place, else approach-fallback, else closing-fallback, else engagement search,
## else step out, else overwatch, else hold — each with its own penalty constants
## dominating the one below it. That structure is why it reached 1400 lines and
## eight file-cap bumps: every new consideration had to be inserted at the right
## height in a total order, and the order was the design.
##
## Here there is **one loop**: score every (cell, action) pair, take the best, do
## it. Precedence is not written down at all — it emerges from weights, and a
## profile changing which action wins is a `.tres` edit rather than a re-ordering
## of branches.
##
## ## Two selections per turn, not one
##
## A turn is not one action: a unit repositions and then shoots. Rather than a
## hardcoded "and then fire" step, the planner **re-scores from the settled cell**
## (`UtilityContext.settle_at`) and selects again, up to `MAX_SELECTIONS`. That is
## `PLAN.md`'s "depth 1 — score post-move", and it is what makes "fire until the AP
## runs out" fall out of `ActionQueue.enqueue` refusing the shot that cannot be
## paid for, instead of out of a `MAX_SHOTS_PER_TURN` constant.
##
## ## Resumable from the first line, because it cannot be retrofitted
##
## The candidate loop yields through `PlanPacer` exactly where the old one did. A
## conditional `await` is a **parse error** in GDScript, so "make it resumable
## later" means converting the whole call chain again — measured, not assumed
## (taskblock-44 Pass D). Aborting mid-scan is safe by construction: candidates are
## only ever appended, and `UtilityScorer.best_index` over a partial list returns
## the best of what was actually scored, which is a legitimate answer at every
## point rather than a partial one.
##
## ## No positive-utility action is a real answer
##
## A scorer can genuinely rate everything at or below the veto floor — an unarmed
## unit with no enemy known and nobody to defer to. The turn then ends, which is
## honest rather than a fallback: `PLAN.md`'s *Panic* item is what eventually gives
## that state its own behaviour, and this block only needs the turn to end.

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
				empty_decisions += 1
			break
		# **A refused winner re-scores without it rather than ending the turn.**
		# `ActionQueue.enqueue` is the only place that knows what a unit can
		# actually afford from where it will actually be standing, so "the scorer
		# wanted this and the executor said no" is ordinary and must fall through to
		# the next-best option. Stopping instead was a real defect: a marksman whose
		# own shot was unaffordable picked `shoot`, had it refused, and ended its
		# turn — never reaching the overwatch it should have held, because overwatch
		# was simply never scored again.
		var action_id: StringName = candidates[winner]["action_id"]
		if not _commit(candidates[winner], context, queue, state):
			refused_ids.append(action_id)
			continue
		chosen_ids.append(action_id)
		if _find_action(context, action_id).ends_turn:
			# `HoldAction`/`ShutdownAction` ARE the end of the turn. Selecting again
			# would queue behind something that already ended it, and the backstop
			# below would overwrite the deferral it just chose.
			return queue

	# Always last, and always attempted: `EndTurnAction.is_legal` is deliberately
	# ALWAYS legal for the current unit, so a turn that queued nothing at all still
	# spins the board forward rather than stalling on a unit that cannot act.
	queue.enqueue(EndTurnAction.new(unit, mission), state)
	return queue


## taskblock-45 Pass C: the objective this unit plans under.
##
## **The leader is derived, never assigned** — it is whichever member of the batch
## takes a turn first this round, which `BatchPlan.record` captures by refusing
## every claim after the first. So the branch below is not "am I the leader" but
## "has anyone led yet": if nobody has, this unit is leading by virtue of asking.
## That is what makes leader death free — the next-fastest living member is simply
## first next round, with no promotion code and no field to keep in sync.
##
## A leader that dies mid-round leaves the record untouched, so its followers keep
## the round's objective and finish the manoeuvre they were committed to.
##
## **Tier-gated, and checked before any work is done.** A unit with no blackboard
## can neither read an objective nor record one, so it plans for itself — correct
## behaviour for it rather than a gap — and does not pay to choose an objective
## that would be discarded.
static func _batch_objective(
	unit: Unit, view: WorldView, context: UtilityContext, profile: UtilityProfile
) -> StringName:
	if unit.batch_id == 0 or not view.has_blackboard(unit):
		return BatchPlan.NO_OBJECTIVE
	var following: Dictionary = view.batch_plan_for(unit)
	if not following.is_empty():
		return following.get("objective", BatchPlan.NO_OBJECTIVE)
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
			# **An `ends_turn` action is a substitute for acting, not a coda to it.**
			# Holding means "I would rather act after someone else moves"; a unit that
			# has already spent its whole turn shooting has nothing left to defer, and
			# `HoldAction` keeps it the current unit rather than yielding — so a unit
			# that shot six times and then held never handed the turn on at all. Only
			# offered while the turn is still empty.
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


## Turns the winning candidate into real queued actions, and re-bases the context
## on wherever the unit ends up. Returns false when nothing could be enqueued, so
## the caller stops rather than re-selecting the same refused action forever.
##
## ## The candidate cell is where the action HAPPENS, so getting there is part of
## committing to it
##
## A candidate is a (cell, action) pair and the cell is where the unit is standing
## when the action is performed — that is the whole premise the scoring rests on,
## since `standoff_match`, `cover` and `line_of_fire` are all read AT that cell. So
## a winning candidate whose cell is not the unit's current one must **move there
## first**, whatever the action is.
##
## **This was missed in Pass B and it was the block's worst bug.** `_commit` built
## a path only when the executor was itself a move, so `shoot@(3,0)` — chosen
## because (3,0) sits at a good standoff — was enqueued from wherever the unit
## already stood. The unit scored a cell it liked, never went there, and fired from
## the wrong place; next turn it scored the same cell again and did the same thing.
## Two units plinking at each other across a corridor forever, neither closing,
## which is exactly the `TERMINATED`-not-`STRANDED` signature behind taskblock-45
## Pass D's completion drop. The decision log is what found it: every entry read
## `shoot@(3,0)` while the unit sat at (1,0), and the mismatch between those two
## coordinates is the whole bug in one line.
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
		# chebyshev proxy (`UtilityContext._move_economy`); the real route is
		# computed only for the cell that actually won, which is the difference
		# between one `astar` call and one per candidate.
		var pathfinder := Pathfinder.new(context.view.grid, context.unit.shell.can_climb())
		var path: Array[Vector2i] = pathfinder.astar(context.unit.cell, cell)
		if path.size() < 2:
			return false
		if not queue.enqueue(MoveAction.new(context.unit, path), state):
			return false
		moved = true
		context.settle_at(cell)

	if UtilityExecutors.needs_path(action):
		# The move WAS the action. A move action that won its own cell is a
		# contradiction the preconditions already forbid (`cell_is_elsewhere`), so
		# reaching here without having moved is a refusal, not a no-op.
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
