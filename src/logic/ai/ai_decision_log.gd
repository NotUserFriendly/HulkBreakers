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
