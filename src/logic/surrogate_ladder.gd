class_name SurrogateLadder
extends RefCounted

## Ops on the surrogate-tier DAG (docs/04): "degradation is a ladder, not a
## health bar" — except taskblock03 Pass A corrects taskblock02's mistake
## of modeling it as a straight LINE. It's a DAG:
##
##   BRAIN_ONLY -> SPINAL -+-> PERIPHERAL -+-> FULL
##                          +-> TORSIC ----+
##
## PERIPHERAL and TORSIC are mutually exclusive branches of the same
## stage, not neighbouring rungs — a PERIPHERAL surrogate must never fit a
## SURROGATE_TORSIC socket or vice versa.


## `socket_type` and `capabilities` (docs/04 taskblock02 Pass D) are
## explicit columns, not derived — PERIPHERAL and TORSIC deliberately do
## NOT share a nested capability set (limbs vs. organs are different
## things, not "more" or "less" of one list). Only `LOCOMOTION` is
## authored so far (docs/04: "do not invent the capability vocabulary...
## ask" — one tag, for the one mechanic that needs it today).
static func default_ladder() -> Array[SurrogateTier]:
	return [
		SurrogateTier.new(&"FULL", "Full body", [], &"SURROGATE_FULL", [&"LOCOMOTION"]),
		SurrogateTier.new(
			&"PERIPHERAL",
			"Arms + legs around a hollow core",
			[&"FULL"],
			&"SURROGATE_PERIPHERAL",
			[&"LOCOMOTION"]
		),
		SurrogateTier.new(&"TORSIC", "Torso and head", [&"FULL"], &"SURROGATE_TORSIC", []),
		SurrogateTier.new(
			&"SPINAL", "Head and spine", [&"PERIPHERAL", &"TORSIC"], &"SURROGATE_SPINAL", []
		),
		SurrogateTier.new(
			&"BRAIN_ONLY", "Just the matrix and its casing", [&"SPINAL"], &"SURROGATE_BRAIN", []
		),
	]


## docs/04 taskblock03 Pass A2: demotion on a DAG is genuinely ambiguous
## wherever more than one tier promotes into `current` — today, only FULL
## (both PERIPHERAL and TORSIC promote there). "It presumably depends on
## what was destroyed" (taskblock03), and that rule is deliberately NOT
## invented here. For that ambiguous case this picks the first branch in
## `ladder`'s own declaration order as a flagged, deterministic
## placeholder — `push_warning`'d every time it fires — never final
## design. Every tier with exactly one upstream branch demotes to it
## unambiguously; a tier with none (BRAIN_ONLY, the floor) holds.
static func demote(current: SurrogateTier, ladder: Array[SurrogateTier]) -> SurrogateTier:
	var candidates: Array[SurrogateTier] = []
	for candidate: SurrogateTier in ladder:
		if current.id in candidate.promotes_to:
			candidates.append(candidate)

	if candidates.is_empty():
		return current
	if candidates.size() > 1:
		push_warning(
			(
				(
					"SurrogateLadder.demote: ambiguous demotion from %s (%d branches lead here) — "
					+ "picking the first in ladder order as an unresolved, flagged placeholder "
					+ "(taskblock03 Pass A2, not a design decision)"
				)
				% [current.id, candidates.size()]
			)
		)
	return candidates[0]


## docs/04 taskblock03 Pass A1: "any surrogate fits a larger box" survives
## the DAG correction — "larger" now means *downstream in the promotion
## graph* rather than *higher in a line*. A tier's `attaches_to` is every
## socket type reachable from itself via `promotes_to` (itself included),
## computed by transitive reachability, never a rank comparison — a
## PERIPHERAL surrogate reaches FULL but never TORSIC, and vice versa. The
## author writes one field (`Part.surrogate_tier`); this list is
## generated — adding a branch to `ladder` updates every surrogate with no
## hand-editing.
static func derive_attaches_to(
	tier: SurrogateTier, ladder: Array[SurrogateTier]
) -> Array[StringName]:
	var by_id: Dictionary = {}
	for candidate: SurrogateTier in ladder:
		by_id[candidate.id] = candidate

	var reached: Array[StringName] = [tier.id]
	var frontier: Array[StringName] = [tier.id]
	while not frontier.is_empty():
		var current_id: StringName = frontier.pop_back()
		var current_tier: SurrogateTier = by_id.get(current_id)
		if current_tier == null:
			continue
		for next_id: StringName in current_tier.promotes_to:
			if not next_id in reached:
				reached.append(next_id)
				frontier.append(next_id)

	var socket_types: Array[StringName] = []
	for reached_id: StringName in reached:
		var reached_tier: SurrogateTier = by_id.get(reached_id)
		if reached_tier != null:
			socket_types.append(reached_tier.socket_type)
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
