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

## Who drives a squad's turns (docs/10 taskblock02 F1; tb31 Pass B) — a
## closed engine state, not open data. `UNASSIGNED` is NOT a third way to
## take a turn (that statement stays true) — it's "no decision made yet," a
## setup-time-only state. A bout must never actually RUN with an
## `UNASSIGNED` squad still on it: `BoutRunner._init()` treats that as a
## hard construction error (BR30.09's root cause was exactly this — a path
## that assigned nothing silently inherited a default instead of failing).
## `UNASSIGNED` is the zero-default so an unset squad reads that way rather
## than silently picking a side; every real entry point (`_seed_battle()`,
## `BoutSetup.build_bout()`) must assign explicitly before a bout can run —
## see `CombatState.assign_all_to_human()`/`assign_rest_to_ai()` for the
## authoring-layer shortcuts "mostly AI"/"Control All Squads" now go
## through, in the open, instead of as a hidden getter default.
enum SquadController {
	UNASSIGNED,
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

## taskblock-28 Pass B: how `KitEquipper.equip` resolves a unit's own kit
## into its hands — a closed engine state (a resolution STRATEGY, not
## content): INSTANT (the only implemented path) resolves before turn 1
## with no visible turns spent. VISIBLE is the seam laid for a future
## "watch them arm up" mode (units physically execute equip actions as
## real turns) — declared now, unimplemented, so `equip`'s own `match`
## already has somewhere for it to land without a later signature change.
enum EquipMode {
	INSTANT,
	VISIBLE,
}
