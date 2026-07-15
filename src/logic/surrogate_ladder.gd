class_name SurrogateLadder
extends RefCounted

## Ops on the ordered surrogate-tier ladder (docs/04): "degradation is a
## ladder, not a health bar." default_ladder() is the docs/04 reference
## ladder (FULL -> PERIPHERAL -> TORSIC -> SPINAL -> BRAIN_ONLY); demote()
## steps one rung toward BRAIN_ONLY and holds there — a bare matrix is the
## floor, never a further loss.


static func default_ladder() -> Array[SurrogateTier]:
	return [
		SurrogateTier.new(&"FULL", "Full body", 0),
		SurrogateTier.new(&"PERIPHERAL", "Arms + legs around a hollow core", 1),
		SurrogateTier.new(&"TORSIC", "Torso and head", 2),
		SurrogateTier.new(&"SPINAL", "Head and spine", 3),
		SurrogateTier.new(&"BRAIN_ONLY", "Just the matrix and its casing", 4),
	]


## The next-worse tier in `ladder`, or `current` unchanged if already at
## the bottom rung.
static func demote(current: SurrogateTier, ladder: Array[SurrogateTier]) -> SurrogateTier:
	var next_rank: int = current.rank + 1
	for tier: SurrogateTier in ladder:
		if tier.rank == next_rank:
			return tier
	return current
