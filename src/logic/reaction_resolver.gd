class_name ReactionResolver
extends RefCounted

## taskblock-20 Pass H: the reaction window — tb18's existing interrupt
## STOP (a triggered Overwatch mid-move freeze) offering the DEFENDER a
## choice before the shot resolves, not a new resolver. "Options map to
## existing systems": IGNORE (take it as-is — a no-op, the SAME behavior
## every overwatch trigger already has today); DIVE_PRONE (a pose change,
## `Poses.prone()`); TURN_SHIELD (a facing change, the SAME `FaceAction`
## plumbing every other reface already uses). Neither reaction spends
## AP/MP — a reaction, not a queued action.

const IGNORE := &"ignore"
const DIVE_PRONE := &"dive_prone"
const TURN_SHIELD := &"turn_shield"
const ALL_REACTIONS: Array[StringName] = [IGNORE, DIVE_PRONE, TURN_SHIELD]


## taskblock-20 Pass H: "perk-gated — 'a unit with reactions'... reads the
## perk hook; default: no reactions available until perks exist." Same
## hook shape as `ResolutionSpeed.action_family_bonus` (taskblock-18 A3):
## returns `[]` today, since no perk system exists yet to name which units
## actually carry "a unit with reactions" — built when perks are.
static func available_reactions(_unit: Unit) -> Array[StringName]:
	return []


## Applies `reaction` to `defender` against `threat` — IGNORE and any
## unrecognized id are both no-ops (taking the shot as-is IS "doing
## nothing"). Logged unconditionally (even IGNORE): a reaction window
## being offered and resolved is itself real combat information, docs/09
## "if it changed the world, it's in the log," regardless of whether the
## chosen reaction itself changed anything.
static func apply_reaction(
	state: CombatState, defender: Unit, threat: Unit, reaction: StringName
) -> void:
	match reaction:
		DIVE_PRONE:
			defender.pose = Poses.prone()
		TURN_SHIELD:
			FaceAction.face_for_free(
				state,
				defender,
				FaceAction.orientation_toward(defender.cell, threat.cell),
				&"reaction_turn_shield"
			)
		_:
			pass

	if state.is_preview:
		return
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			defender.id,
			&"reaction_taken",
			{"threat": threat.id, "reaction": reaction},
			"unit %d reacts to unit %d with %s" % [defender.id, threat.id, reaction]
		)
	)
