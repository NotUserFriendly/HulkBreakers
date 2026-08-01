class_name Detonation
extends RefCounted

## taskblock-51 `BR51.22`/`BR51.23`: **an explosion, and everything it reaches.**
##
## Split out of `DamageResolver` when chain reactions pushed that file past its line cap. The
## split is real rather than cosmetic: a detonation resolves in **waves** and logs its own
## events, which is a different shape from the single-impact resolution around it.
##
## ## The supervisor's specification for chaining
##
## > *"Chain reactions chain react simultaneously, then in order, they should never re-explode
## > something that's already exploded."*
##
## Everything in one wave goes off together and its damage lands before the next wave is
## decided. Termination comes from the **exploded set**, not from a depth cap — a bound that
## says "this cannot go on forever" is not the same as one that says "nothing goes off twice",
## and only the second is what was asked for.

## A detonation names no attacker: `ImpactResult` does not carry one, and a debug-forced failure
## genuinely has none. Recorded as a constant so the log's `-1` is a stated decision rather than
## a magic number.
const UNATTRIBUTED := -1


## taskblock-09 A3 (docs/03): renamed from "cook-off," same mechanic. A
## failed DETONATE part with detonate_damage > 0 explodes: every living
## unit within detonate_radius (Chebyshev) of its cell takes that damage
## to their shell's root part. Returns the units it hit. No longer gated
## by the VOLATILE tag — that's a descriptor now, open vocabulary; the
## trigger is failure_mode == DETONATE, enforced by this file's own single
## caller, `resolve_part_failure`.
static func resolve(part: Part, state: CombatState, locate: Callable) -> Array[Unit]:
	var affected: Array[Unit] = []
	var exploded: Array[Part] = []
	var wave: Array[Part] = [part]
	# **Waves, because the supervisor specified the shape:** *"Chain reactions chain react
	# simultaneously, then in order, they should never re-explode something that's already
	# exploded."* Everything in one wave goes off together and its damage lands before the next
	# wave is decided; `exploded` is what makes the chain terminate rather than a depth cap.
	while not wave.is_empty():
		var next_wave: Array[Part] = []
		for blast: Part in wave:
			if blast in exploded:
				continue
			exploded.append(blast)
			if blast.detonate_damage <= 0.0:
				continue
			var centre: Vector2i = locate.call(blast, state)
			if centre.x < 0:
				continue
			var reach: int = int(blast.detonate_radius)
			var caught: Array[Unit] = []
			for unit: Unit in state.units:
				if unit.alive and Grid.distance_chebyshev(unit.cell, centre) <= reach:
					DamageResolver.apply_damage_to_part(unit.shell.root, blast.detonate_damage)
					caught.append(unit)
					if unit not in affected:
						affected.append(unit)
			# `BR51.22`: **cover takes the blast too.** This iterated `state.units` and nothing
			# else, so a barrel beside a barrel could not chain and an explosion beside a wall
			# left it untouched — the same units-only assumption that hid the drawing gate.
			for cell: Vector2i in state.grid.blockers:
				var blocker: Part = state.grid.blockers[cell]
				if blocker == blast or blocker in exploded:
					continue
				if Grid.distance_chebyshev(cell, centre) > reach:
					continue
				DamageResolver.apply_damage_to_part(blocker, blast.detonate_damage)
				if blocker.hp <= 0 and blocker.failure_mode == &"DETONATE":
					next_wave.append(blocker)
			_log(state, blast, caught)
		wave = next_wave
	return affected


## **`BR51.23`: where the exploding thing actually is**, in cell units, or `null` if it cannot be
## placed.
##
## The supervisor's catch: *"For a barrel, cell center works, but an ammo rack on a unit's back may
## be higher up or offset."* Centring on `_locate_cell` returns the *unit's* cell, so a mounted
## part detonated at its wearer's feet. `UnitGeometry.assembly_placements` already composes each
## part's real world transform — it is what renders the box and what `PartPicker` hits — so this
## asks it rather than deriving a second answer.
##
## A blocker falls back to its own cell centre, which for a blocker genuinely is its position —
## the case that hid this.
static func _origin(part: Part, state: CombatState) -> Variant:
	for unit: Unit in state.units:
		if not (part in unit.shell.all_parts()):
			continue
		for placement: BoxPlacement in UnitGeometry.assembly_placements(
			unit.shell.root, unit.cell, unit.orientation, unit.pose, unit.height
		):
			if placement.part == part:
				return placement.transform.origin / UnitGeometry.CELL_SIZE
		return Vector3(unit.cell.x, unit.height, unit.cell.y)
	for cell: Vector2i in state.grid.blockers:
		if state.grid.blockers[cell] == part:
			return Vector3(
				float(cell.x), UnitGeometry.true_height_for_cell(cell, state.grid), float(cell.y)
			)
	return null


## `BR35.08`/`BR51.20`: the detonation event, carrying **where it went off and how far it
## reached**, so the drawn sphere is a readout of the real mechanical extent. Centred on the
## exploding object's own real position (`_origin`) rather than its owner's cell — `BR51.23`.
static func _log(state: CombatState, part: Part, caught: Array[Unit]) -> void:
	var placed: Variant = _origin(part, state)
	if placed == null:
		return
	var at: Vector3 = placed
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					UNATTRIBUTED,
					&"detonation",
					{
						"source_part": part.id,
						"center_x": at.x,
						"center_y": at.z,
						"center_height": at.y,
						"radius": part.detonate_radius,
						"units": caught.size(),
					},
					(
						"%s detonated at (%.2f, %.2f, %.2f), radius %.1f, %d caught"
						% [part.id, at.x, at.y, at.z, part.detonate_radius, caught.size()]
					)
				)
			)
		)
	)
