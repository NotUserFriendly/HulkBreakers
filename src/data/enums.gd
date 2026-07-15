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
