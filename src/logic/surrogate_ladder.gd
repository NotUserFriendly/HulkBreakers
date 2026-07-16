class_name SurrogateLadder
extends RefCounted

## Ops on the ordered surrogate-tier ladder (docs/04): "degradation is a
## ladder, not a health bar." default_ladder() is the docs/04 reference
## ladder (FULL -> PERIPHERAL -> TORSIC -> SPINAL -> BRAIN_ONLY); demote()
## steps one rung toward BRAIN_ONLY and holds there — a bare matrix is the
## floor, never a further loss.


## `socket_type` and `capabilities` (docs/04 taskblock02 Pass D) are
## explicit columns, not derived — PERIPHERAL and TORSIC deliberately do
## NOT share a nested capability set (limbs vs. organs are different
## things, not "more" or "less" of one list). Only `LOCOMOTION` is
## authored so far (docs/04: "do not invent the capability vocabulary...
## ask" — one tag, for the one mechanic that needs it today).
static func default_ladder() -> Array[SurrogateTier]:
	return [
		SurrogateTier.new(&"FULL", "Full body", 0, &"SURROGATE_FULL", [&"LOCOMOTION"]),
		SurrogateTier.new(
			&"PERIPHERAL",
			"Arms + legs around a hollow core",
			1,
			&"SURROGATE_PERIPHERAL",
			[&"LOCOMOTION"]
		),
		SurrogateTier.new(&"TORSIC", "Torso and head", 2, &"SURROGATE_TORSIC", []),
		SurrogateTier.new(&"SPINAL", "Head and spine", 3, &"SURROGATE_SPINAL", []),
		SurrogateTier.new(
			&"BRAIN_ONLY", "Just the matrix and its casing", 4, &"SURROGATE_BRAIN", []
		),
	]


## The next-worse tier in `ladder`, or `current` unchanged if already at
## the bottom rung.
static func demote(current: SurrogateTier, ladder: Array[SurrogateTier]) -> SurrogateTier:
	var next_rank: int = current.rank + 1
	for tier: SurrogateTier in ladder:
		if tier.rank == next_rank:
			return tier
	return current


## docs/04 taskblock02 Pass D2: "any surrogate fits a larger box" — a
## surrogate's own rank is a MAXIMUM the socket it lands in must be at
## least as protective as, never an exact match. Lower rank = less
## degraded = bigger box, so a tier at rank R fits every socket type whose
## own tier ranks R or lower (its own box, and everything roomier than
## it). The author writes one field (`Part.surrogate_tier`); this list is
## generated — adding a new rung to `ladder` updates every surrogate with
## no hand-editing.
static func derive_attaches_to(
	tier: SurrogateTier, ladder: Array[SurrogateTier]
) -> Array[StringName]:
	var socket_types: Array[StringName] = []
	for candidate: SurrogateTier in ladder:
		if candidate.rank <= tier.rank:
			socket_types.append(candidate.socket_type)
	return socket_types


## Builds the actual, shootable Part for one rung of the ladder (docs/04
## taskblock02 Pass D1) — real organic tissue, not an abstract label: a
## material (`flesh`, dt 0), a placeholder box (FLAGGED — real per-tier
## geometry is a design question, not invented here), and its own MATRIX
## socket the matrix docks inside, same `dock_matrix()` every other
## MATRIX-hosting part already uses. `attaches_to` is always the derived
## list above, never hand-authored.
static func build_surrogate(tier: SurrogateTier, ladder: Array[SurrogateTier]) -> Part:
	var surrogate := Part.new()
	surrogate.id = StringName("surrogate_%s" % tier.id.to_lower())
	surrogate.display_name = tier.display_name
	surrogate.surrogate_tier = tier.id
	surrogate.attaches_to = derive_attaches_to(tier, ladder)
	surrogate.material = &"flesh"
	surrogate.tags = [&"ORGANIC"]
	# Placeholder box, sized only so a surrogate is never invisible to the
	# shot plane (docs/10: "hp > 0 with no volume" is a validation error) —
	# real per-tier silhouettes (a BRAIN_ONLY surrogate is a casing the size
	# of a fist, not a torso) are a design pass, not this one.
	surrogate.hp = 6
	surrogate.max_hp = 6
	surrogate.volume = [Box.new(Vector3.ZERO, Vector3(0.20, 0.20, 0.20))]
	surrogate.sockets = [Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX")]
	return surrogate
