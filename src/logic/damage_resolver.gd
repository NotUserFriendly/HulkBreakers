class_name DamageResolver
extends RefCounted

## docs/03: armor is not more hitpoints. resolve_impact() decides penetrate /
## stop-dead / deflect from real geometry — never a roll. resolve_shot()
## orchestrates one projectile's whole life: penetration cascades through
## whatever's behind the plate, a deflection spawns a ricochet that travels
## the world and can hit anything, and the sim always terminates (ricochet
## depth cap + a damage floor).

const DEFAULT_MAX_RICOCHET_DEPTH := 2
const DEFAULT_DAMAGE_FLOOR := 1.0

## docs/03 specifies "bonus damage" on a crit but gives no multiplier. This
## is a flagged, tunable placeholder, not a design decision — ask before
## treating it as final.
const DEFAULT_CRIT_BONUS_MULTIPLIER := 1.5


## Pure geometry, decided once for a single region: no roll. `incoming_dir`
## is the projectile's direction of travel; `region.surface_normal` comes
## free from BodyProjector — the box face that was actually hit.
static func resolve_impact(
	incoming_dir: Vector2, damage: float, region: Region, table: MaterialTable
) -> ImpactResult:
	var material: MaterialEntry = table.get_entry(region.part.material)
	var dir: Vector2 = incoming_dir.normalized()
	var normal_2d := Vector2(region.surface_normal.x, region.surface_normal.z)

	var result := ImpactResult.new()
	result.region = region
	result.incoming_dir = dir

	if damage >= material.dt:
		result.outcome = Enums.Outcome.PENETRATE
		result.part_damage = damage
		return result

	var incidence_deg: float = rad_to_deg(acos(clampf((-dir).dot(normal_2d), -1.0, 1.0)))
	if incidence_deg <= material.deflect_threshold_deg:
		result.outcome = Enums.Outcome.STOP_DEAD
		result.part_damage = damage
		return result

	result.outcome = Enums.Outcome.DEFLECT
	var reflected: Vector2 = (dir - 2.0 * dir.dot(normal_2d) * normal_2d).normalized()
	result.reflected_dir = reflected
	var deflection_deg: float = rad_to_deg(acos(clampf(dir.dot(reflected), -1.0, 1.0)))
	var t: float = clampf(deflection_deg / table.max_bend_deg, 0.0, 1.0)
	result.retained_fraction = lerp(table.retain_at_zero_bend, table.retain_at_max_bend, t)
	return result


## Subtracts `amount` (rounded up, so any positive damage always registers)
## from `part.hp`. Returns true if this destroyed the part.
static func apply_damage_to_part(part: Part, amount: float) -> bool:
	part.hp = maxi(0, part.hp - int(ceil(amount)))
	return part.hp <= 0


## A destroyed VOLATILE part with cook_off_damage > 0 explodes: every living
## unit within cook_off_radius (Chebyshev) of its cell takes that damage to
## their frame's root part. Returns the units it hit.
static func cook_off(part: Part, state: CombatState) -> Array[Unit]:
	var affected: Array[Unit] = []
	if not (&"VOLATILE" in part.tags) or part.cook_off_damage <= 0.0:
		return affected
	var center: Vector2i = _locate_cell(part, state)
	if center.x < 0:
		return affected
	for unit: Unit in state.units:
		if unit.alive and Grid.distance_chebyshev(unit.cell, center) <= int(part.cook_off_radius):
			apply_damage_to_part(unit.frame.root, part.cook_off_damage)
			affected.append(unit)
	return affected


static func _locate_cell(part: Part, state: CombatState) -> Vector2i:
	for unit: Unit in state.units:
		if part in unit.frame.all_parts():
			return unit.cell
	for cell: Vector2i in state.grid.blockers:
		if state.grid.blockers[cell] == part:
			return cell
	return Vector2i(-1, -1)


## Destroying the part hosting a unit's Matrix ejects it as a loose field
## item (docs/01: "destroy that part -> eject") and demotes the unit's
## surrogate one rung (docs/04: "a torso chewed to SPINAL still functions"
## — the body degrades, the matrix does not). The unit itself goes
## unpiloted (alive false) — matrices are never lost, but an ejected one
## leaves its frame behind. Returns the ejected Matrix, or null if `part`
## wasn't hosting one belonging to a real unit.
static func eject_matrix_if_needed(part: Part, state: CombatState) -> Matrix:
	if part.hp > 0 or not part.hosts_matrix or part.hosted_matrix == null:
		return null
	var owner: Unit = _owning_unit(part, state)
	if owner == null:
		return null

	var ejected: Matrix = part.hosted_matrix
	part.hosted_matrix = null
	if not state.grid.field_items.has(owner.cell):
		state.grid.field_items[owner.cell] = []
	state.grid.field_items[owner.cell].append(ejected)

	owner.demote_surrogate(SurrogateLadder.default_ladder())
	owner.alive = false
	return ejected


static func _owning_unit(part: Part, state: CombatState) -> Unit:
	for unit: Unit in state.units:
		if part in unit.frame.all_parts():
			return unit
	return null


## Destroying any non-root part drops its whole subtree as one intact
## assembly (docs/01: "blow a shoulder off and the entire subtree below it
## drops as one item... not exploded into a pile of disparate bits"). The
## frame's own root is handled separately (eject_matrix_if_needed, if it
## hosts one) — there's no parent within the same frame to drop it from,
## since the root destroyed IS the unit. Returns the dropped part (the
## subtree's own root), or null if nothing was actually dropped.
static func drop_subtree_if_destroyed(part: Part, state: CombatState) -> Part:
	if part.hp > 0:
		return null
	var owner: Unit = _owning_unit(part, state)
	if owner == null or owner.frame.root == part:
		return null
	if not PartGraph.drop(owner.frame.root, part):
		return null

	if not state.grid.field_items.has(owner.cell):
		state.grid.field_items[owner.cell] = []
	state.grid.field_items[owner.cell].append(part)
	return part


## Every consequence of a part actually reaching 0 hp, gathered onto one
## ImpactResult: cook-off, matrix ejection (plus the demotion it always
## carries — docs/04), and the subtree drop. `demoted_tier_before` is
## captured ahead of eject_matrix_if_needed() since that call is what
## changes it.
static func _resolve_destruction_consequences(
	impact: ImpactResult, region: Region, state: CombatState
) -> void:
	impact.cooked_off_units = cook_off(region.part, state)
	var owner: Unit = _owning_unit(region.part, state)
	var tier_before: SurrogateTier = owner.surrogate_tier if owner != null else null
	impact.ejected_matrix = eject_matrix_if_needed(region.part, state)
	if impact.ejected_matrix != null:
		impact.demoted_unit = owner
		impact.demoted_tier_before = tier_before
	impact.dropped_subtree = drop_subtree_if_destroyed(region.part, state)


## Every part sharing a body with `part` (its whole unit, if any — otherwise
## just itself). A ricochet's new origin sits right where it just left, so
## excluding only the one part it bounced off still lets it immediately
## re-hit a sibling part of the same body at point-blank range; excluding
## the whole body for that first lookup is what "it bounced clear" means.
static func _body_of(part: Part, state: CombatState) -> Array[Part]:
	for unit: Unit in state.units:
		if part in unit.frame.all_parts():
			return unit.frame.all_parts()
	return [part]


static func _roll_crit(crit_chance: float, rng: RandomNumberGenerator) -> Dictionary:
	var is_crit: bool = rng.randf() < crit_chance
	var is_double_crit := false
	if is_crit:
		is_double_crit = rng.randf() < maxf(0.0, crit_chance - 1.0)
	return {"is_crit": is_crit, "is_double_crit": is_double_crit}


## docs/03: armored + crit -> bypass DT and resolve against whatever's
## behind; unarmored + crit -> bonus damage instead. A double crit always
## applies both — bypassing if armored, and bonus damage regardless.
static func _crit_effects(is_crit: bool, is_double_crit: bool, armored: bool) -> Dictionary:
	if is_double_crit:
		return {"bypass": armored, "bonus": true}
	if is_crit:
		return {"bypass": armored, "bonus": not armored}
	return {"bypass": false, "bonus": false}


## Resolves one projectile's entire path: builds the shot plane, walks it
## nearest-first from `point`, cascades through penetrations, and — on a
## deflect within budget — recurses into a fresh shot plane built from the
## ricochet's new origin and direction. Terminates via `max_ricochet_depth`
## and `damage_floor` (docs/03: "the sim must always terminate").
##
## `exclude_parts` skips those parts on this call's very first lookup only —
## set on a ricochet's recursive call to the whole body it just deflected
## off of (see _body_of), since a ricochet's new origin sits right where it
## bounced and would otherwise immediately re-resolve to a sibling part of
## that same body at point-blank range.
static func resolve_shot(
	origin: Vector2,
	direction: Vector2,
	point: Vector2,
	damage: float,
	crit_chance: float,
	state: CombatState,
	table: MaterialTable,
	rng: RandomNumberGenerator,
	ricochet_depth: int = 0,
	max_ricochet_depth: int = DEFAULT_MAX_RICOCHET_DEPTH,
	damage_floor: float = DEFAULT_DAMAGE_FLOOR,
	crit_bonus_multiplier: float = DEFAULT_CRIT_BONUS_MULTIPLIER,
	exclude_parts: Array[Part] = []
) -> Array[ImpactResult]:
	var results: Array[ImpactResult] = []
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var plane: Array[Region] = ShotPlane.build(origin, dir, state)

	# One crit roll per projectile flight: it stays in effect through
	# however many layers this same round penetrates or bypasses. A
	# ricochet is a new projectile (docs/03) and rolls its own on the
	# recursive call below.
	var crit: Dictionary = _roll_crit(crit_chance, rng)

	var start: int = 0
	var skip_parts: Array[Part] = exclude_parts
	# Every projectile in a burst shares the nominal `dir` used to build the
	# plane, but scatter puts each one at a different point — a different
	# muzzle-to-impact ray, not just a different landing spot. Derived once
	# per flight, from the first surface this round actually reaches, and
	# reused unchanged through whatever it goes on to penetrate (a round
	# doesn't bend just because it punched through).
	var shot_dir: Vector2 = dir
	var shot_dir_ready := false
	while start < plane.size():
		var found_index: int = _find_next(plane, start, point, skip_parts)
		skip_parts = []  # the exclusion applies only to this call's first hit
		if found_index == -1:
			break
		var region: Region = plane[found_index]
		start = found_index + 1

		if not shot_dir_ready:
			var muzzle_to_impact: Vector2 = dir * region.depth + perp * point.x
			shot_dir = muzzle_to_impact.normalized()
			shot_dir_ready = true

		var material: MaterialEntry = table.get_entry(region.part.material)
		var effects: Dictionary = _crit_effects(
			crit.is_crit, crit.is_double_crit, material.dt > 0.0
		)

		if effects.bypass:
			var bypass_result := ImpactResult.new()
			bypass_result.region = region
			bypass_result.incoming_dir = shot_dir
			bypass_result.is_crit = crit.is_crit
			bypass_result.is_double_crit = crit.is_double_crit
			bypass_result.bypassed_armor = true
			results.append(bypass_result)
			continue

		var applied_damage: float = damage * (crit_bonus_multiplier if effects.bonus else 1.0)
		var impact: ImpactResult = resolve_impact(shot_dir, applied_damage, region, table)
		impact.is_crit = crit.is_crit
		impact.is_double_crit = crit.is_double_crit
		results.append(impact)

		match impact.outcome:
			Enums.Outcome.PENETRATE:
				impact.destroyed_part = apply_damage_to_part(region.part, impact.part_damage)
				if impact.destroyed_part:
					_resolve_destruction_consequences(impact, region, state)
				continue
			Enums.Outcome.STOP_DEAD:
				impact.destroyed_part = apply_damage_to_part(region.part, impact.part_damage)
				if impact.destroyed_part:
					_resolve_destruction_consequences(impact, region, state)
				return results
			Enums.Outcome.DEFLECT:
				var next_damage: float = damage * impact.retained_fraction
				if ricochet_depth < max_ricochet_depth and next_damage >= damage_floor:
					var world_hit: Vector2 = origin + dir * region.depth + perp * point.x
					results.append_array(
						resolve_shot(
							world_hit,
							impact.reflected_dir,
							Vector2(0.0, point.y),
							next_damage,
							crit_chance,
							state,
							table,
							rng,
							ricochet_depth + 1,
							max_ricochet_depth,
							damage_floor,
							crit_bonus_multiplier,
							_body_of(region.part, state)
						)
					)
				return results
	return results


static func _find_next(
	plane: Array[Region], start: int, point: Vector2, exclude_parts: Array[Part] = []
) -> int:
	for i in range(start, plane.size()):
		if exclude_parts.has(plane[i].part):
			continue
		if plane[i].rect.has_point(point):
			return i
	return -1
