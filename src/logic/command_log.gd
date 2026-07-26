class_name CommandLog
extends RefCounted

## taskblock-41 Pass C: pairs **what was sent** with **what happened**, so a
## refused or dropped command is visible instead of a silent `return false`.
## This counters the specific class of bug this project keeps producing — a
## verb that quietly does nothing looks identical, from the outside, to a verb
## that ran and had no effect.
##
## One emitter for every command path (`BoutInjector`'s debug verbs,
## `CombatState.try_apply`), never a per-caller copy — CLAUDE.md's own "if two
## code paths decide the same thing, that's the bug to fix", applied to how a
## refusal reads.
##
## **Two events per command, always:** `command` before the attempt, then
## `command_outcome` after it. Both always fire, including on success, so
## "issued but never resolved" is itself a readable state in the log (a verb
## that crashed mid-way leaves a `command` with no `command_outcome`) rather
## than something you can only infer from absence.
##
## Pass A is what makes this affordable: render cost no longer scales with
## event count, so doubling command traffic costs one frame's draw either way.

const COMMAND_KIND: StringName = &"command"
const OUTCOME_KIND: StringName = &"command_outcome"

## docs/09's two-phase turn model, surfaced in the text rather than left for
## the reader to reconstruct from `phase`: "a command queued in TACTICS and a
## command refused at RESOLUTION are different events and should read
## differently." A refusal during TACTICS means the queue would not take it; a
## refusal during RESOLUTION means the world moved out from under something
## already approved. Same `reason`, very different diagnosis.
const TACTICS_ISSUE_VERB := "queued"
const RESOLUTION_ISSUE_VERB := "applying"
const TACTICS_REFUSAL := "refused while queueing"
const RESOLUTION_REFUSAL := "refused at resolution"


## "What was sent." `data` is the command's own arguments, verbatim — the
## point is to be able to reconstruct the call, not to summarise it.
static func issued(state: CombatState, verb: StringName, data: Dictionary = {}) -> void:
	var full: Dictionary = data.duplicate()
	full["verb"] = verb
	var issue_verb: String = RESOLUTION_ISSUE_VERB if state.is_resolving else TACTICS_ISSUE_VERB
	var text: String = "%s: %s%s" % [issue_verb, verb, _argument_text(data)]
	state.combat_log.emit(
		LogEvent.new(state.round_number, _phase(state), _unit_id(data), COMMAND_KIND, full, text)
	)


## "What happened" — the accepted half. Emitted after the mutation, so the
## pair brackets the real work.
static func accepted(state: CombatState, verb: StringName, data: Dictionary = {}) -> void:
	_outcome(state, verb, true, &"", data)


## "What happened" — the refused half. **Returns false**, so a caller reads
## `return CommandLog.refused(...)` and cannot accidentally refuse without
## logging, or log without refusing.
##
## `reason` is an open `StringName` vocabulary (CLAUDE.md — a new refusal
## reason must never need a code edit anywhere but its own call site), and it
## is never optional: "remove-unit rejected" alone is exactly the uninformative
## outcome this pass exists to delete. The specifics (which cell, which part)
## ride in `data`.
static func refused(
	state: CombatState, verb: StringName, reason: StringName, data: Dictionary = {}
) -> bool:
	_outcome(state, verb, false, reason, data)
	return false


static func _outcome(
	state: CombatState, verb: StringName, was_accepted: bool, reason: StringName, data: Dictionary
) -> void:
	var full: Dictionary = data.duplicate()
	full["verb"] = verb
	full["accepted"] = was_accepted
	full["reason"] = reason
	var text: String
	if was_accepted:
		text = "accepted: %s" % verb
	else:
		var refusal: String = RESOLUTION_REFUSAL if state.is_resolving else TACTICS_REFUSAL
		text = "%s — %s: %s" % [refusal, verb, reason]
	state.combat_log.emit(
		LogEvent.new(state.round_number, _phase(state), _unit_id(data), OUTCOME_KIND, full, text)
	)


## An injection is not attributed to any unit's own turn, so `unit_id` comes
## from the command's own arguments when it names one (`{"unit": <id>}`) and
## falls back to -1 — the same "no specific unit caused this" convention
## `ShotResolution` already uses for cover/terrain impacts.
static func _unit_id(data: Dictionary) -> int:
	var unit: Variant = data.get("unit")
	return unit if unit is int else -1


static func _phase(state: CombatState) -> Enums.Phase:
	return Enums.Phase.RESOLUTION if state.is_resolving else Enums.Phase.TACTICS


## Renders the arguments inline so the command line alone is readable without
## cross-referencing `data` — sorted, so the same call always reads the same
## way regardless of Dictionary insertion order.
static func _argument_text(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var keys: Array = data.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key: Variant in keys:
		parts.append("%s=%s" % [key, data[key]])
	return "(%s)" % ", ".join(parts)
