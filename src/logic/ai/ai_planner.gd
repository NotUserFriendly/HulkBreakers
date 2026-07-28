class_name AiPlanner
extends RefCounted

## taskblock-45 Pass B: **the one seam every AI turn is planned through**, and the
## place the playstyle vocabulary meets the profile table.
##
## For one block it dispatched between two planners — the engagement-score planner
## and the utility planner — so Pass D could run the same seeds through both and
## flip the default on evidence. **Pass E deleted the loser.** What is left is the
## seam itself: one entry point, the plan-cost diagnostics taken around it, and the
## playstyle bridge.
##
## ## The view is restricted here, once, for everyone
##
## The utility planner is built to plan against a degraded world model — the tier
## gap is the entire reason it exists — so restriction is switched on at this seam
## rather than left for each caller to remember. `BoutRunner` hands in an
## unrestricted view and gets the gating regardless, which is what stops "did this
## caller set the flag" from being a thing anyone has to know.

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

## taskblock-45 Pass D: **the utility planner is now the default**, and after Pass E
## it is the only one. Kept as a `true` constant-in-practice rather than deleted so
## the head-to-head that justified the switch stays attached to the switch.
##
## Flipped on the head-to-head, which is what the pass exists to produce:
##
## | | old | new |
## |---|---|---|
## | completion rate | 75% | 58% |
## | turns to complete | 23.9 | 13.1 |
## | per-unit plan cost (ms), mission bout | 139.90 | 51.04 |
## | per-unit plan cost (ms), 3v3 combat bout | 485.16 | 112.53 |
## | `ShotPlane` builds per turn | 29.1 | **0.0** |
##
## **The completion drop is real, was flagged to the supervisor, and the decision to
## proceed was theirs.** `MIN_COMPLETION_RATE` (0.5) holds at 0.58, which is the
## codified criterion, and no seed on either side ended `STRANDED` — the five that
## fail under the new planner all end `TERMINATED`, meaning the turn cap ran out.
## **Nothing is losing fights; something is failing to finish.** That is a
## characterized regression carried forward, not an unknown.
static var use_utility_planner: bool = true

## taskblock-45 Pass D: what a plan actually cost, accumulated across every turn
## since the last reset. Diagnostics for the bench and for tests; **never read by
## planning**, so no decision can depend on them.
##
## **Measured here rather than in the bench**, because this is the one seam both
## planners pass through with identical instrumentation. A bench timing each
## planner from the outside would have to reach into `BoutRunner.step`, which also
## resolves the turn — mixing planning cost with damage resolution and making the
## head-to-head measure the wrong thing. Taken around the dispatch, these are
## exactly "per-unit plan cost" and "`ShotPlane` builds per plan", which are two of
## the four rows Pass D's comparison table asks for.
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
## `playstyle` is still the caller's vocabulary. Retiring it is explicitly NOT this
## block's job — it migrates with the profile table (`PLAN.md`) — so the mapping to
## a profile id lives in `profile_id_for` below, in one place, ready to be deleted
## rather than untangled.
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


## The temporary bridge from the playstyle enum to the profile table.
##
## **Both sides of this mapping are real content and neither is code.** The
## playstyles are `Matrix.playstyle` values a bout already authors; the profiles are
## `.tres` files under `res://data/utility_profiles/`. What is temporary is the
## MAPPING — `PLAN.md` retires the playstyle vocabulary entirely, at which point a
## matrix names its profile directly and this function goes away rather than
## growing arms.
##
## The split is the one the playstyle names already imply: the two that close and
## press an attack read as aggressive, and everything that keeps its distance,
## weights cover or would rather withdraw reads as cautious. An unrecognised value
## falls to cautious, matching the codebase's standing "unknown open-vocabulary
## value falls back rather than errors" posture.
static func profile_id_for(playstyle: StringName) -> StringName:
	if playstyle in [&"AGGRESSIVE", &"PSYCHOTIC"]:
		return &"aggressive"
	return &"cautious"
