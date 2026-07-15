class_name Enums
extends RefCounted

## Values for Grid.terrain. Cover (Grid.cover_value) is a separate overlay —
## terrain only governs walkability and vision blocking.
enum TerrainType {
	OPEN,
	WALL,
	SPAWN_A,
	SPAWN_B,
}

## A matrix's fate at battle end (Phase 10). RECOVERED is the default for a
## matrix that never ejected.
enum RecoveryState {
	RECOVERED,
	LEFT_BEHIND,
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
