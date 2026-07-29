class_name AiPlanner
extends RefCounted

## **The one seam every AI turn is planned through**, and where the AI profile
## vocabulary meets the profile table.
##
## For one block it dispatched between two planners so a head-to-head could flip
## the default on evidence; the loser is deleted and `SUPERSEDED.md` holds the
## comparison. What is left is the seam itself, the plan-cost diagnostics taken
## around it.
##
## **The view is restricted here, once, for everyone.** Callers hand in an
## unrestricted view and get the tier gating regardless, so "did this caller
## remember to set the flag" is not something anyone has to know.

## taskblock-46 Pass E: **the playstyle vocabulary is gone.** A bout now names a
## `UtilityProfile` id directly.
##
## `AGGRESSIVE`/`SKIRMISHER`/`MARKSMAN`/`COVER_SEEKER`/`PSYCHOTIC`/`TURTLE` mixed
## three unrelated axes into one word — a temperament, a role, and a preferred range
## — so it could not answer "cautious but close-quarters" without a seventh name, and
## the seventh would have mixed them again. All three are weights over shared
## considerations now: standoff and cover-seeking are inputs, not identities.
##
## Nothing replaces the list here **on purpose**: the profiles ARE the list, and
## `DataLibrary.utility_profiles_pool()` is where anything that needs to enumerate
## them reads it. A hardcoded copy is what let the old vocabulary drift from the
## table it was supposed to select from — six playstyles selecting between two
## profiles, five of them landing on the same one.

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
	# The lookahead's own counter resets with the rest, so a caller cannot end up
	# comparing plan counts from this run against field counts from the last one.
	UtilityLookahead.reset_diagnostics()


## `(unit, view, mission, profile_id, pacer) -> ActionQueue`.
##
## `profile_id` names a `UtilityProfile` under `res://data/utility_profiles/`
## directly — no translation step. An unknown id is not an error here; the scorer
## falls back to unweighted scoring, the standing posture for an unrecognised
## open-vocabulary value.
static func plan_turn(
	unit: Unit,
	view: WorldView,
	mission: MissionState,
	profile_id: StringName = &"aggressive",
	pacer: PlanPacer = null
) -> ActionQueue:
	var started_usec: int = Time.get_ticks_usec()
	var started_planes: int = ShotPlane.builds
	view.restricted = true
	var queue: ActionQueue = await UtilityPlanner.plan_turn(unit, view, mission, profile_id, pacer)
	# A plan that SUSPENDED (a watching view supplied a pacer) spent wall-clock time
	# waiting for frames that is not this planner's cost. Recorded anyway rather
	# than corrected for, because the bench never supplies a pacer — and a
	# correction that only ever applies to a case the measurement does not cover
	# would be untested arithmetic sitting in the hot path.
	plans += 1
	plan_usec += Time.get_ticks_usec() - started_usec
	plan_shot_planes += ShotPlane.builds - started_planes
	return queue
