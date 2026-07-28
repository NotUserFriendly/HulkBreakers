class_name AiDecisionLog
extends RefCounted

## tb35 Pass A1: "which branch plan_turn took and why, if it held" — a
## diagnostic side-channel only, never read back by any planner, so
## emitting it does not compromise the planner's own purity/
## determinism contract (the planner's own determinism tests assert
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


## The utility planner's decision, recorded well enough to reconstruct by hand.
## `docs/11` has why the log is the instrument rather than a diagnostic afterthought.
##
## `candidates` entries are `{label, action_id, cell, score, offered, trace}`.
## **`offered: false` means a precondition refused it**, which is a different answer
## from "offered and scored zero" — and telling those apart is most of the value
## when someone asks why a unit did not do something.
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
