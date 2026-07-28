class_name BatchObjective
extends RefCounted

## The leader's coarse call, scored by the same `UtilityScorer` over the same
## profile as everything else — an objective is not a special kind of decision,
## just the same one asked about a coarser question. `docs/11` has why batches
## amortize and why the objective is injected as a consideration input rather than
## a destination to copy.
##
## Two things worth stating here rather than there:
##
## - **The inputs are read at the leader's own cell**, not per candidate. This is a
##   judgement about the squad's situation, not about anywhere it might move, so it
##   costs four scores per batch per round rather than four per cell.
## - **A follower consumes it for free.** The objective is one more entry in a
##   dictionary the follower was already building — which is what "dramatically
##   cheaper than the leader" actually looks like, and what the destination-copying
##   model it replaced never managed.

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
