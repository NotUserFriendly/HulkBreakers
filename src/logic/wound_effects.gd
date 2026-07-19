class_name WoundEffects
extends RefCounted

## taskblock-20 Pass D: the mechanism side of `Part.wounds` — a non-terminal,
## per-part, repairable consequence (the state between "fine" and "failed"),
## distinct from `is_mangled`/`is_disabled` (whole-part, only ever at 0 hp)
## and from a future status effect (decays; a wound persists). Every caller
## that inflicts or reads a wound's own combat effect goes through here,
## never a second, independently-maintained copy of the disables/no-op
## question `WoundDef.disables` already answers.


## Direct infliction — "by a precise hit," the mechanism `DamageResolver`'s
## own C4 `lodged_bullet` trigger already calls, and the one any future
## caller (a called shot, melee, a script event) uses too. Idempotent: a
## part already carrying `wound_id` is left alone, never doubled up.
static func inflict(part: Part, wound_id: StringName) -> void:
	if wound_id in part.wounds:
		return
	part.wounds.append(wound_id)


## taskblock-20 Pass D: the status->wound threshold path — "wired but fires
## only once the status system exists." No status system exists yet, so no
## production caller can legitimately reach this today; it's a real, tested
## hook with nowhere to be called FROM, not a guess at which status maps to
## which wound at what magnitude — that vocabulary belongs to the status
## system's own block, not this one. Generic: `status_magnitude` and
## `threshold` are whatever the (future) caller's own status track says.
static func apply_if_status_crosses_threshold(
	part: Part, status_magnitude: float, threshold: float, wound_id: StringName
) -> void:
	if status_magnitude >= threshold:
		inflict(part, wound_id)


## True if any wound `part` carries is authored `disables = true`
## (`severed_controls`' "limb inert but pristine") — an unauthored/unknown
## wound id (a typo, a wound authored after this part's own save) never
## disables by default, the same "absence isn't a penalty" posture every
## other open-vocabulary lookup in this codebase takes.
static func is_disabled_by_wounds(part: Part) -> bool:
	for wound_id: StringName in part.wounds:
		var def: WoundDef = DataLibrary.get_wound_def(wound_id)
		if def != null and def.disables:
			return true
	return false
