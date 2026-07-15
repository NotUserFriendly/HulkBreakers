class_name AttackAction
extends CombatAction

## Aim point -> dartboard -> shot plane -> impact (docs/02/03, Phase 6).
## `unit` and `weapon_id` are resolved fresh from whatever `state` is passed
## (docs/09): a preview's frame is an independent clone, so a bare Part
## reference captured at construction would never match it (see
## Frame.find_part). Aims at the target unit's own frontmost region by
## default — center mass — offset by `aim_offset` if given; never picks a
## body part directly (docs/02: the dartboard picks a point, not a part).

var unit: Unit
var weapon_id: StringName
var target_cell: Vector2i
var aim_offset: Vector2
## Perk/ammo/stance modifiers on top of the weapon's own part-level mods
## (docs/08) — empty until those systems exist, but resolved through the same
## WeaponResolver call a tooltip would use, never a separate code path.
var extra_sources: Array[ModSource]


func _init(
	p_unit: Unit,
	p_weapon_id: StringName,
	p_target_cell: Vector2i,
	p_aim_offset: Vector2 = Vector2.ZERO,
	p_extra_sources: Array[ModSource] = []
) -> void:
	unit = p_unit
	weapon_id = p_weapon_id
	target_cell = p_target_cell
	aim_offset = p_aim_offset
	extra_sources = p_extra_sources


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false

	var weapon: Part = actual.frame.find_part(weapon_id)
	if weapon == null or weapon.hp <= 0:
		return false
	if actual.ap < weapon.ap_cost:
		return false

	if not state.grid.in_bounds(target_cell):
		return false
	var target: Unit = _unit_at(state, target_cell)
	if target == null:
		return false

	var range_cells: int = Grid.distance_chebyshev(actual.cell, target_cell)
	if weapon.weapon_max_range > 0.0 and range_cells > int(weapon.weapon_max_range):
		return false
	if not LoS.has_los(state.grid, actual.cell, target_cell):
		return false

	var manipulators: Array[Part] = []
	for part: Part in actual.frame.living_parts():
		if part != weapon:
			manipulators.append(part)
	return PartGraph.can_operate(weapon, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var weapon: Part = actual.frame.find_part(weapon_id)
	actual.ap -= weapon.ap_cost

	if state.is_preview:
		# The one thing a preview must never resolve (docs/09): whether this
		# round actually hits and kills is exactly what RESOLUTION alone
		# gets to decide. AP is spent so a later queued move/attack still
		# previews correctly; the target is left exactly as it was.
		return

	var target: Unit = _unit_at(state, target_cell)
	var origin := Vector2(actual.cell.x, actual.cell.y)
	var direction := Vector2(target_cell - actual.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)

	var aim_point: Vector2 = _center_mass(plane, target) + aim_offset
	var resolved_scatter: Array[Ring] = Dartboard.resolve_scatter(weapon, extra_sources)
	var points: Array[Vector2] = Dartboard.sample(
		aim_point, resolved_scatter, state.rng, weapon.burst
	)

	# docs/08: the damage/crit numbers used here must be the exact same
	# ones a tooltip built from WeaponResolver would show — never a raw
	# Part field read directly.
	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, extra_sources).current

	for point: Vector2 in points:
		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			origin, direction, point, damage, crit_chance, state, state.material_table, state.rng
		)
		for result: ImpactResult in results:
			_log_impact(state, actual, result)

	# Phase 6 placeholder: no living parts left disables the unit. Phase 7
	# (docs/04) replaces this with the real rule — destroying the specific
	# part hosting the Matrix ejects it — which fires strictly earlier than
	# "every part destroyed," so it supersedes rather than conflicts with
	# this conservative stand-in.
	if target.alive and target.frame.living_parts().is_empty():
		target.alive = false

	state.log_action(
		(
			"AttackAction: unit %d fired %s (burst %d) at %s"
			% [actual.id, weapon_id, weapon.burst, target_cell]
		)
	)


## The target's frontmost region's rect center — a point, never a chosen
## body part. Regions are matched back to `target` by object identity,
## which is safe here: both the plane and `target` were built from the same
## `state`, never compared across two different states.
func _center_mass(plane: Array[Region], target: Unit) -> Vector2:
	var target_parts: Array[Part] = target.frame.all_parts()
	var best: Region = null
	for region: Region in plane:
		if not target_parts.has(region.part):
			continue
		if best == null or region.depth < best.depth:
			best = region
	if best == null:
		return Vector2(target.cell.x, target.cell.y)
	return best.rect.get_center()


func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for candidate: Unit in state.units:
		if candidate.alive and candidate.cell == cell:
			return candidate
	return null


func _log_impact(state: CombatState, attacker: Unit, result: ImpactResult) -> void:
	var outcome_name: String = (
		"BYPASS" if result.bypassed_armor else Enums.Outcome.keys()[result.outcome]
	)
	var text: String = "%s on %s" % [outcome_name, result.region.part.id]
	var data: Dictionary = {
		"outcome": result.outcome,
		"part": result.region.part.id,
		"damage": result.part_damage,
		"bypassed_armor": result.bypassed_armor,
		"is_crit": result.is_crit,
		"is_double_crit": result.is_double_crit,
	}
	var event := LogEvent.new(
		state.turn_index, Enums.Phase.RESOLUTION, attacker.id, &"impact", data, text
	)
	state.combat_log.emit(event)


func describe() -> String:
	return "AttackAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]
