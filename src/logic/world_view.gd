class_name WorldView
extends RefCounted

## taskblock-44 Pass C: what a planner is allowed to know.
##
## The rebuild's intelligence tiers gate **information**, not just actions. A
## dumb unit runs the same scorer against a degraded world model and makes
## plausible-but-wrong decisions — firing at where someone *was*, walking into a
## flank it had no way to see — rather than random ones. Gating actions alone
## produces a unit with fewer options that still plays them optimally, which
## reads as *limited* rather than dumb. That only works if information access is
## a chokepoint, and retrofitting one onto a planner already reading global state
## touches everything. So the doorway goes in now, while the planner is still the
## old one and nothing depends on it.
##
## **Today this returns everything.** No filtering, no behaviour change, no
## tiers — a pass-through with a doorway in it.
##
## ## Where the boundary actually runs, which is the sentence part two needs
##
## **The line is not `CombatState` versus not-`CombatState`. It is
## knowledge-about-units versus everything else — and that line runs THROUGH
## `Grid` and THROUGH `BatchPlan` rather than around them.**
##
## - **Geometry is free.** A Mindless unit still knows where the walls are; what
##   it does not know is who is behind them. Terrain, surfaces, opacity and cover
##   are not gated by anything and never will be.
## - **Occupancy is not geometry.** `Grid` carries `occupant_id` and
##   `get_occupant_id()` right beside `blockers` and `surfaces`. Reading those is
##   reading the position of every unit on the board, including ones this view
##   just filtered out — the entire seam bypassed by a one-line accessor. So
##   occupancy reaches a planner **only** through `units_visible_to`, and
##   `test_world_view_seam.gd` enforces that by refusing occupancy reads anywhere
##   in the planner path. That is a deliberate choice of the cheaper of two
##   options; the other was a geometry-only `Grid` facade.
## - **The team blackboard is a tier capability, not infrastructure.** A Grunt
##   does not get one; Trained and above do. So batch plans sit on the
##   observer-parameterised side next to `units_visible_to`, never on the free
##   side next to `round_number`.
##
## ## What a restricted view may hide, and what it may never touch
##
## A restricted view may hide **units** and **facts about units** — that one
## exists, where it is, what it is carrying, what its squad is planning. It may
## report a stale position, because believing an enemy is where it last was seen
## is exactly the mistake a real soldier makes.
##
## It may **never** alter geometry, and it may never change what a shot does.
## **`ShotPlane` stays final regardless of what a unit believes** (`docs/02`,
## `docs/08`). A unit planning against a believed enemy position asks the
## resolver about geometry *to a cell*; the resolver answers objectively, and the
## unit's error lives in having chosen the wrong cell. That is why a gated view
## and a canonical resolver are compatible rather than in tension, and why
## `canonical_state_for_resolvers()` is not a loophole.

## taskblock-44 Pass C: tiers with team-blackboard access. Authored here as a
## fixture rather than derived, because the real tier table is part two's — this
## only needs to be somewhere part two can find, and to be non-empty enough that
## the gate is testable now.
const BLACKBOARD_TIERS: Array[StringName] = [&"TRAINED", &"ELITE"]

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
## **Staleness is DERIVED, never maintained.** The round a sighting was taken is
## stored and compared against `round_number` on read — taskblock-43's
## `BatchPlan` trick, for the same reason: no invalidation hook at a round
## boundary is no invalidation hook to miss. It also sidesteps the
## incremental-update bugs that eat perception systems.
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


## **The canonical resolver's door, and the one thing that must not become an
## accessor.** `ShotPlane`/`LineOfFire`/`Pathfinder` need the real, objective
## world; a unit's beliefs never change what a shot does.
##
## **It may appear only as a bare argument — never followed by a dot.**
## `LineOfFire.first_hit(..., view.canonical_state_for_resolvers())` is the
## intended use; `view.canonical_state_for_resolvers().units` is the entire seam
## defeated, and a guard watching direct field access would not see it. That rule
## is mechanical, greppable and enforced by `test_world_view_seam.gd`, in the
## same shape as taskblock-40's spawn-marker guard and taskblock-41's parse
## guard — because a prose rule with no enforcement is what BR40.02 was.
func canonical_state_for_resolvers() -> CombatState:
	return _state


## Every unit `observer` is entitled to know about. Unrestricted, this is the
## whole roster — identical to the `state.units` read it replaces, dead units
## included, since callers filter on `alive` themselves.
##
## Restricted, an enemy the observer cannot currently see is reported at its last
## remembered position if that sighting is still fresh, and omitted entirely
## otherwise. Allies are always known: they are on the radio.
func units_visible_to(observer: Unit) -> Array[Unit]:
	if not restricted or observer == null:
		return _state.units
	var seen: Array[Unit] = []
	for candidate: Unit in _state.units:
		if candidate == observer or candidate.squad_id == observer.squad_id:
			seen.append(candidate)
			continue
		if _has_direct_sight(observer, candidate):
			seen.append(candidate)
			continue
		var memory: Dictionary = remembered.get(candidate.id, {})
		if memory.is_empty():
			continue
		if round_number - int(memory["round_seen"]) > memory_rounds:
			continue
		seen.append(candidate)
	return seen


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
	if restricted and not observer.intelligence_tier in BLACKBOARD_TIERS:
		return {}
	return _state.batch_plans.plan_to_follow(observer, round_number)


## Records `observer` as this batch's leader for the current round. Writing to
## the blackboard is gated exactly as reading it is — a unit with no access to
## the shared plan cannot set one either.
func claim_batch_lead(observer: Unit, destination: Vector2i) -> void:
	if observer == null:
		return
	if restricted and not observer.intelligence_tier in BLACKBOARD_TIERS:
		return
	_state.batch_plans.claim(observer, round_number, destination)


## Deliberately `LoS`, not `LineOfFire`: this answers "can this unit SEE that
## one", which is a perception question, where line of FIRE is a shot question.
## Conflating them is what BR30.10 was about in the other direction.
func _has_direct_sight(observer: Unit, candidate: Unit) -> bool:
	return LoS.has_los(grid, observer.cell, candidate.cell)
