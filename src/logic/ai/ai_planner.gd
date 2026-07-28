class_name AiPlanner
extends RefCounted

## **The one seam every AI turn is planned through**, and where the playstyle
## vocabulary meets the profile table.
##
## For one block it dispatched between two planners so a head-to-head could flip
## the default on evidence; the loser is deleted and `SUPERSEDED.md` holds the
## comparison. What is left is the seam itself, the plan-cost diagnostics taken
## around it, and the playstyle bridge.
##
## **The view is restricted here, once, for everyone.** Callers hand in an
## unrestricted view and get the tier gating regardless, so "did this caller
## remember to set the flag" is not something anyone has to know.

## taskblock-45 Pass E: the playstyle vocabulary, moved here from the retired
## planner.
##
## **It outlives the planner that used to own it** — `Matrix.playstyle` authors it,
## `BoutRosterEntry` carries it and the bout maker's dropdown reads it, none of
## which the retirement touches. `PLAN.md` retires the vocabulary itself along with
## the profile table; until then it lives beside `profile_id_for`, which is the one
## thing that still interprets it.
const PLAYSTYLES: Array[StringName] = [
	&"AGGRESSIVE",
	&"COVER_SEEKER",
	&"SKIRMISHER",
	&"MARKSMAN",
	&"PSYCHOTIC",
	&"TURTLE",
]

## The utility planner is the default and, since the retirement, the only one.
##
## **No measurement is quoted here on purpose.** This comment carried the
## head-to-head table for one commit and the numbers in it were already wrong —
## they had been taken mid-change, before the fixes that followed. A measurement
## duplicated at a call site is a measurement nobody re-takes. `SUPERSEDED.md` holds
## the authoritative before/after and `BR45.03` holds the open regression.
static var use_utility_planner: bool = true

## What a plan actually cost, accumulated since the last reset. Diagnostics for the
## bench and for tests; **never read by planning**, so no decision can depend on
## them.
##
## **Measured at this seam rather than in the bench.** Timing a planner from
## outside means timing `BoutRunner.step`, which also resolves the turn — mixing
## planning cost with damage resolution. Taken around the dispatch, these are
## exactly per-unit plan cost and `ShotPlane` builds per plan, and they survive a
## planner being replaced because they measure the seam rather than the
## implementation.
static var plans: int = 0
static var plan_usec: int = 0
static var plan_shot_planes: int = 0


## Zeroes the diagnostics above. Called by the bench between planners and by tests
## in `before_each`, the standing posture for planner diagnostics in this codebase.
static func reset_diagnostics() -> void:
	plans = 0
	plan_usec = 0
	plan_shot_planes = 0


## `(unit, view, mission, playstyle, pacer) -> ActionQueue`.
##
## `playstyle` is still the caller's vocabulary; the mapping to a profile id lives
## in `profile_id_for` below, in one place, built to be deleted rather than
## untangled when `PLAN.md` retires the vocabulary.
static func plan_turn(
	unit: Unit,
	view: WorldView,
	mission: MissionState,
	playstyle: StringName = &"AGGRESSIVE",
	pacer: PlanPacer = null
) -> ActionQueue:
	var started_usec: int = Time.get_ticks_usec()
	var started_planes: int = ShotPlane.builds
	view.restricted = true
	var queue: ActionQueue = await UtilityPlanner.plan_turn(
		unit, view, mission, profile_id_for(playstyle), pacer
	)
	# A plan that SUSPENDED (a watching view supplied a pacer) spent wall-clock time
	# waiting for frames that is not this planner's cost. Recorded anyway rather
	# than corrected for, because the bench never supplies a pacer — and a
	# correction that only ever applies to a case the measurement does not cover
	# would be untested arithmetic sitting in the hot path.
	plans += 1
	plan_usec += Time.get_ticks_usec() - started_usec
	plan_shot_planes += ShotPlane.builds - started_planes
	return queue


## The temporary bridge from the playstyle vocabulary to the profile table.
##
## **Both sides are content, not code** — playstyles are `Matrix.playstyle` values a
## bout authors, profiles are `.tres` under `res://data/utility_profiles/`. Only the
## MAPPING is temporary, and it is one function so it can be deleted whole.
##
## The split is what the names already imply: the two that close and press an attack
## read as aggressive, everything that keeps its distance or weights cover reads as
## cautious. An unrecognised value falls to cautious — the standing posture for an
## unknown open-vocabulary value.
static func profile_id_for(playstyle: StringName) -> StringName:
	if playstyle in [&"AGGRESSIVE", &"PSYCHOTIC"]:
		return &"aggressive"
	return &"cautious"
