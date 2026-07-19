class_name Enums
extends RefCounted

## Values for Grid.terrain. Cover (Grid.blockers — real field-object
## geometry, taskblock-16 Pass B) is a separate overlay — terrain only
## governs walkability and vision blocking.
enum TerrainType {
	OPEN,
	WALL,
	SPAWN_A,
	SPAWN_B,
}

## A matrix's fate at battle end (docs/04). PILOTING is the default — still
## in a body, nothing went wrong. Matrices are never lost on any path; this
## only ever flags how they came home, not whether they did.
enum RecoveryState {
	PILOTING,  # still in a body at extraction
	CARRIED,  # picked up by an ally, extracted
	LEFT_BEHIND,  # still on the hulk floor at mission end; returns anyway
	LINK_KILLED,  # link matrix destroyed; returns, death-feedback applies
}

## Turn structure (docs/09). TACTICS queues intents against a speculative
## state copy and mutates nothing; RESOLUTION executes the queue and owns
## every mutation. A closed engine state — not open data.
enum Phase {
	TACTICS,
	RESOLUTION,
}

## How a ModSource combines with what came before it in StatResolver
## (docs/08). A closed, small set of arithmetic operations — not open data.
enum ModOp {
	ADD,
	MULTIPLY,
	OVERRIDE,
}

## Where a stat modifier came from (docs/08) — a closed structural
## classification, distinct from the open `tags`/`capabilities` vocabularies.
enum ModSourceKind {
	PART,
	PERK,
	SKILL,
	AMMO,
	STATUS,
	STANCE,
}

## What resolve_impact decides for one region (docs/03) — real geometry,
## never a roll. A closed engine state, not open data.
enum Outcome {
	PENETRATE,
	STOP_DEAD,
	DEFLECT,
}

## How a mission actually ended (docs/00/07 taskblock02 Pass E) — never
## "one squad is down"; that's not an ending at all. A closed, small set.
## UNDECIDED is the default: still in progress.
enum MissionOutcome {
	UNDECIDED,
	EXTRACTED,  # reached extraction, kept the haul
	TERMINATED,  # the player's own choice: cut losses, matrices blink back, loot lost
	STRANDED,  # involuntary — no player matrix can act. NOT a loss; matrices persist regardless
}

## Who drives a squad's turns (docs/10 taskblock02 F1) — a closed engine
## state, not open data (there is no third way to take a turn). HUMAN is
## every squad's default (the "Control All Squads" build default): nothing
## in TacticsController itself gates whose unit a click can select by
## squad, so a HUMAN-controlled squad is already exactly what today's
## input does. No AI decision-maker consults this yet — the heuristics
## that exist today live only in test_full_mission.gd's own test harness,
## never rehomed into production code. Flagged, not silently pretended
## otherwise.
enum SquadController {
	HUMAN,
	AI,
}

## What a board ray actually hit (docs/10 taskblock05 A1) — a closed engine
## state: a click either lands on a unit's own body or bare ground, never a
## third thing.
enum HitKind {
	UNIT,
	CELL,
}

## docs/09 taskblock06 D1: RESOLUTION is a loop with re-entry now (TACTICS
## -> RESOLUTION -> (interrupt) -> TACTICS -> ...), not one atomic pass —
## a closed engine state: a queue's resolution either ran to completion or
## stopped partway, never a third thing.
enum ResolveOutcome {
	COMPLETED,
	STOPPED,
}
