class_name BatchObjective
extends RefCounted

## taskblock-45 Pass C: **squad coordination without a squad planner.**
##
## A batch's leader runs one coarse utility pass — over four authored objectives
## rather than over cells — and the answer is injected into every follower's
## scoring as a consideration input. Followers keep individual agency: an objective
## biases what each of them wants, and none of them is told where to stand.
##
## ## Why this replaces taskblock-43 Pass D rather than extending it
##
## That pass had the leader publish a **destination** and each follower scan the
## handful of cells around it. Its own acceptance went unmet — the follower was not
## dramatically cheaper — and widening or narrowing the local scan does not fix
## that, because the cost was never the scan's size. An objective is a single
## `StringName` that costs a follower **nothing** to consume: it is one more entry
## in a dictionary the follower was already building. That is what "dramatically
## cheaper" actually looks like.
##
## It also fixes a behavioural problem the destination had: every follower
## converging on one cell is not a squad manoeuvre, it is a queue.
##
## ## Standing rule 5 is untouched
##
## The leader acts, then follower one, then follower two, each on their own turn in
## initiative order. The objective is computed **once per batch per round** and
## reused — an amortisation device, never a licence to resolve several units
## together (`docs/PLAN.md` standing rule 5).
##
## ## Dormant until a batch exists
##
## Every unit is `batch_id == 0` until something assigns otherwise, and automatic
## assignment is explicitly not this block's job. So in ordinary play nothing here
## runs at all, and `UtilityContext` publishes a fully neutral objective vector —
## which is what makes "the dormancy is the claim, so assert it" testable rather
## than aspirational.

## Prefix for the per-objective inputs `UtilityContext` publishes. An objective
## `&"advance"` becomes the input `&"objective_advance"`, so the vocabulary follows
## the authored `.tres` set with no code knowing the names.
const INPUT_PREFIX := "objective_"


## The input id an action reads to ask "is this the batch's current objective".
static func input_id_for(objective_id: StringName) -> StringName:
	return StringName(INPUT_PREFIX + String(objective_id))


## The leader's coarse call, or `BatchPlan.NO_OBJECTIVE` when nothing clears the
## veto floor.
##
## Scored by the **same `UtilityScorer`** over the **same profile** as everything
## else — an objective is not a special kind of decision, it is the same decision
## made about a coarser question, which is why it needs no machinery of its own.
## The inputs are the leader's own, read at the cell it is standing on: this is a
## judgement about the squad's situation, not about anywhere it might move to, so
## it costs four scores rather than four per candidate cell.
static func choose(context: UtilityContext, profile: UtilityProfile) -> StringName:
	var pool: Array[UtilityActionDef] = DataLibrary.batch_objectives_pool()
	if pool.is_empty():
		return BatchPlan.NO_OBJECTIVE
	var inputs: Dictionary = context.inputs_for(context.origin())
	var predicates: Dictionary = context.predicates_for(context.origin())
	var scores: Array[float] = []
	for objective: UtilityActionDef in pool:
		var offered: bool = UtilityScorer.preconditions_hold(objective, predicates)
		scores.append(UtilityScorer.score(objective, inputs, profile) if offered else 0.0)
	var winner: int = UtilityScorer.best_index(scores)
	return pool[winner].id if winner >= 0 else BatchPlan.NO_OBJECTIVE
