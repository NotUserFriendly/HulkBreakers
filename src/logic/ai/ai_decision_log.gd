class_name AiDecisionLog
extends RefCounted

## tb35 Pass A1: "which branch plan_turn took and why, if it held" — a
## diagnostic side-channel only, never read back by any planner, so
## emitting it does not compromise `UnitAI.plan_turn`'s own purity/
## determinism contract (`test_plan_turn_is_pure_and_deterministic` asserts
## on the returned queue, not on log side effects).


static func emit(
	state: CombatState,
	unit: Unit,
	branch: StringName,
	fired: bool,
	held: bool,
	hold_reason: StringName
) -> void:
	var suffix: String = ""
	if fired:
		suffix = " (fired)"
	elif held:
		suffix = " (held: %s)" % hold_reason
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.TACTICS,
			unit.id,
			&"ai_decision",
			{"branch": branch, "fired": fired, "held": held, "hold_reason": hold_reason},
			"AI unit %d: %s%s" % [unit.id, branch, suffix]
		)
	)


## taskblock-45 Pass A3: **the utility planner's decision, recorded well enough
## to reconstruct.**
##
## A behaviour tree fails legibly — it took a branch and you can see which. **A
## scorer produces a number, and you either reconstruct why afterwards or you
## cannot.** BR26.02 sat in exactly that hole through three passes of
## reasoned-but-unmeasured fixes, which is why this is designed in rather than
## added the first time behaviour looks wrong.
##
## Four things go in, and each answers a question that is otherwise unanswerable:
##
## - **Every candidate and its final score**, not just the winner. "Why not the
##   other one" is the question actually asked, and the winner alone cannot
##   answer it.
## - **Per consideration, the raw input AND the curve output** — the trace
##   `UtilityScorer.score` fills. A veto is invisible in a product, so "which
##   consideration returned zero" needs the individual factors; the product tells
##   you only that something did.
## - **Tier, profile, and what the unit could see.** A decision that looks wrong
##   is often correct given a degraded world model, and without the visible set
##   there is no way to tell that apart from a scoring bug. This is the half that
##   taskblock-44's `WorldView` exists to make knowable.
## - **The margin over second place.** A landslide and a near-tie want reading
##   very differently, and the winning score alone cannot distinguish them.
##
## `candidates` entries are `{label, action_id, score, offered, trace}` —
## `offered` false meaning a precondition refused it, which is a different answer
## from "offered and scored zero".
static func emit_utility_decision(
	state: CombatState,
	unit: Unit,
	candidates: Array,
	winner_index: int,
	tier: StringName,
	profile_id: StringName,
	visible_unit_ids: Array
) -> void:
	var scores: Array[float] = []
	for candidate: Dictionary in candidates:
		scores.append(float(candidate.get("score", 0.0)))
	var winner: Dictionary = (
		candidates[winner_index] if winner_index >= 0 and winner_index < candidates.size() else {}
	)
	var chosen: String = str(winner.get("label", "nothing"))
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.TACTICS,
					unit.id,
					&"ai_utility_decision",
					{
						"candidates": candidates,
						"winner_index": winner_index,
						"winner": chosen,
						"margin": UtilityScorer.margin(scores),
						"tier": tier,
						"profile": profile_id,
						"visible_unit_ids": visible_unit_ids,
					},
					(
						"AI unit %d [%s/%s]: %s over %d candidates (margin %.3f)"
						% [
							unit.id,
							tier,
							profile_id,
							chosen,
							candidates.size(),
							UtilityScorer.margin(scores)
						]
					)
				)
			)
		)
	)
