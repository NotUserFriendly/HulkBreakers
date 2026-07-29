class_name WorldView
extends RefCounted

## What a planner is allowed to know. `docs/11` has the model: why the world model
## is a chokepoint rather than a convention, why the boundary runs THROUGH `Grid`
## and `BatchPlan` rather than around them, and why the resolver door is a door.
##
## This file is that boundary. Three things about it are local and worth stating
## where they are enforced rather than where they are explained:
##
## - **`canonical_state_for_resolvers()` may appear only as a bare argument, never
##   followed by a dot.** `LineOfFire.first_hit(..., view.canonical_state_for_
##   resolvers())` is the intended use; `.units` on the end is the entire seam
##   defeated, and a guard watching field access would not see it. The rule is
##   mechanical and greppable precisely so `test_world_view_seam.gd` can hold it —
##   a prose rule with no enforcement is what BR40.02 was.
## - **Reading and writing are gated together.** A tier that could record a batch
##   plan it cannot read back is worse than one planning alone, so `has_blackboard`
##   is asked by `batch_plan_for` and `claim_batch_lead` alike.
## - **Staleness is derived, never maintained.** A sighting stores the round it was
##   taken and is compared on read. No invalidation hook at a round boundary is no
##   invalidation hook to miss, and it sidesteps the incremental-update bugs that
##   eat perception systems.

## taskblock-44 Pass C: tiers with team-blackboard access. Authored here as a
## fixture rather than derived, because the real tier table is part two's — this
## only needs to be somewhere part two can find, and to be non-empty enough that
## the gate is testable now.
const BLACKBOARD_TIERS: Array[StringName] = [&"TRAINED", &"ELITE"]

## Tiers that may read `remembered` at all — `docs/11`'s tier table, where Mindless
## is current-sight-only and Grunt is the first tier to add last-known positions.
##
## **A `MINDLESS` unit therefore stops knowing an enemy exists the moment line of
## sight breaks**, planning against an empty board rather than a stale belief. That
## was a supervisor decision, and it is worth recording that it went the other way
## first: the spec asked for a `MINDLESS` unit acting on a remembered position that
## is now wrong, which is not writable for a tier with no memory. Chasing a ghost is
## Grunt's behaviour and needs only this list gaining an entry.
##
## Two separate lists rather than one ordered ladder because `intelligence_tier` is
## an open `StringName` with no defined rank — "at least Grunt" is not expressible;
## membership is.
const MEMORY_TIERS: Array[StringName] = [&"GRUNT", &"TRAINED", &"ELITE"]

## taskblock-46 Pass E: tiers that may SET a batch objective, as opposed to merely
## reading one (`BLACKBOARD_TIERS`).
##
## **`docs/11`'s tier table gives "set batch objective" to Elite alone**, and
## splitting the write from the read is what makes Elite behaviourally distinct
## without inventing an executor for it. A Trained unit follows a plan; an Elite
## unit is the one that makes one. A batch whose fastest member is merely Trained
## therefore coordinates on nothing and every member plans for itself — correct for
## that table row rather than a gap.
const OBJECTIVE_SETTING_TIERS: Array[StringName] = [&"ELITE"]

## Free side — geometry, gated by nothing, the same for every observer.
var grid: Grid
var round_number: int = 0

## taskblock-44 Pass C: the disabled-by-default restriction. **Off is
## byte-identical to having no view at all**, which is the whole point of landing
## the seam before the thing it governs. On, it applies `_remembered` below.
var restricted: bool = false

## `unit_id -> {"cell": Vector2i, "round_seen": int}` — the team's pooled
## knowledge, NOT a flat per-unit memory.
##
## **Pooled from the start, deliberately.** Sharing is already the tier table's
## "team blackboard" column, so pooling is the same axis rather than a later
## bolt-on; building per-unit-only now would force a restructure the moment
## Trained tier arrives.
##
## Staleness is derived on read, not maintained — see the top of this file.
var remembered: Dictionary = {}
## How many rounds a remembered sighting stays usable. Flagged, not tuned — part
## two owns the real number, and nothing reads this while `restricted` is false.
var memory_rounds: int = 2

var _state: CombatState


## The unrestricted view — everything, exactly as the planner saw the world
## before this class existed. Every production caller builds this one today.
static func full(state: CombatState) -> WorldView:
	var view := WorldView.new()
	view._state = state
	view.grid = state.grid
	view.round_number = state.round_number
	return view


## The real, objective world, for `ShotPlane`/`LineOfFire`/`Pathfinder`. **Bare
## argument only, never followed by a dot** — see the rule at the top of this file.
func canonical_state_for_resolvers() -> CombatState:
	return _state


## Every unit `observer` is entitled to know about. Unrestricted, this is the
## whole roster — identical to the `state.units` read it replaces, dead units
## included, since callers filter on `alive` themselves.
##
## Restricted, an enemy the observer cannot currently see is reported at its last
## remembered position if that sighting is still fresh, and omitted entirely
## otherwise. Allies are always known: they are on the radio.
##
## **Memory is itself a tier capability** (`MEMORY_TIERS`), so a `MINDLESS`
## observer skips the remembered branch and sees only what its own eyes reach.
func units_visible_to(observer: Unit) -> Array[Unit]:
	if not restricted or observer == null:
		return _state.units
	var may_remember: bool = observer.intelligence_tier in MEMORY_TIERS
	var seen: Array[Unit] = []
	for candidate: Unit in _state.units:
		if candidate == observer or candidate.squad_id == observer.squad_id:
			seen.append(candidate)
			continue
		if _has_direct_sight(observer, candidate):
			seen.append(candidate)
			continue
		if not may_remember:
			continue
		var memory: Dictionary = remembered.get(candidate.id, {})
		if memory.is_empty():
			continue
		if round_number - int(memory["round_seen"]) > memory_rounds:
			continue
		seen.append(candidate)
	return seen


## taskblock-45 Pass B: records everything `observer` can currently SEE, so a later
## turn can act on it once direct sight is gone.
##
## **Nothing calls this for a `MINDLESS` observer** — a tier that cannot read the
## memory has no business writing it, exactly as `claim_batch_lead` refuses a write
## from a tier that cannot read the blackboard. The asymmetry that would otherwise
## creep in is a Mindless unit feeding sightings to the Trained units around it,
## which is the team blackboard arriving through a side door.
##
## Sightings are stamped with the round they were taken and never expired here;
## `units_visible_to` compares on read. **No invalidation hook is a hook that
## cannot be missed** — taskblock-43's `BatchPlan` trick, for the same reason.
func record_sightings(observer: Unit) -> void:
	if observer == null or not observer.intelligence_tier in MEMORY_TIERS:
		return
	for candidate: Unit in _state.units:
		if candidate == observer or candidate.squad_id == observer.squad_id:
			continue
		if not candidate.alive:
			continue
		if _has_direct_sight(observer, candidate):
			remembered[candidate.id] = {"cell": candidate.cell, "round_seen": round_number}


## This batch's shared plan for the current round, or empty when `observer` is
## not entitled to one.
##
## **Gated on tier, because the blackboard is a tier capability.** A Grunt has no
## team blackboard, so it gets nothing here and plans for itself — which is the
## correct behaviour for it, not a degradation. Unrestricted, every tier is
## treated as having access, so nothing changes today.
func batch_plan_for(observer: Unit) -> Dictionary:
	if observer == null:
		return {}
	if not has_blackboard(observer):
		return {}
	return _state.batch_plans.plan_to_follow(observer, round_number)


## Records `observer` as this batch's leader for the current round. Writing to
## the blackboard is gated exactly as reading it is — a unit with no access to
## the shared plan cannot set one either.
##
## taskblock-45 Pass C: `objective` is the coarse call the leader made for the
## batch. A tier with no blackboard cannot set one for the same reason it cannot
## read one — a `MINDLESS` unit acting first in a batch simply leaves the batch
## without an objective, and every member plans for itself. That is correct rather
## than a gap: a squad led by something that cannot coordinate is not coordinated.
func claim_batch_lead(
	observer: Unit, destination: Vector2i, objective: StringName = BatchPlan.NO_OBJECTIVE
) -> void:
	if not has_blackboard(observer):
		return
	if not may_set_objective(observer):
		return
	_state.batch_plans.claim(observer, round_number, destination, objective)


## taskblock-45 Pass C: whether `observer` may use the team blackboard at all.
##
## The same gate `batch_plan_for` and `claim_batch_lead` apply, exposed so a caller
## can skip work it is not entitled to do rather than doing it and having the
## result discarded — a `MINDLESS` unit should not pay to choose a batch objective
## it can neither record nor read. **One gate, asked three ways**, never a second
## copy of the tier list.
func has_blackboard(observer: Unit) -> bool:
	if observer == null:
		return false
	return not restricted or observer.intelligence_tier in BLACKBOARD_TIERS


## Whether `observer` may set the batch's objective, not merely read it — Elite
## only. Asked separately from `has_blackboard` because reading and writing are
## different capabilities in the tier table, and collapsing them would make Elite
## indistinguishable from Trained.
func may_set_objective(observer: Unit) -> bool:
	if observer == null:
		return false
	return not restricted or observer.intelligence_tier in OBJECTIVE_SETTING_TIERS


## Deliberately `LoS`, not `LineOfFire`: this answers "can this unit SEE that
## one", which is a perception question, where line of FIRE is a shot question.
## Conflating them is what BR30.10 was about in the other direction.
func _has_direct_sight(observer: Unit, candidate: Unit) -> bool:
	return LoS.has_los(grid, observer.cell, candidate.cell)
