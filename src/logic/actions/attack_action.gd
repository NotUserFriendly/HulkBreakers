class_name AttackAction
extends CombatAction

## Aim point -> dartboard -> shot plane -> impact (docs/02/03, Phase 6).
## `unit` and `weapon_id` are resolved fresh from whatever `state` is passed
## (docs/09): a preview's shell is an independent clone, so a bare Part
## reference captured at construction would never match it (see
## Shell.find_part). Aims at the target unit's own frontmost region by
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
## docs/10 taskblock04 C3: "this is where docs/07's harvest loop finally
## touches the board" — null for a standalone battle with no mission
## context (BattleScene, most tests); when set, a destroyed field object's
## own `salvage_yield` is credited to it the same way GatherAction credits
## a resource node. Optional and last, like GatherAction's own `mission`
## but not required here — attacking happens with or without a mission.
var mission: MissionState


func _init(
	p_unit: Unit,
	p_weapon_id: StringName,
	p_target_cell: Vector2i,
	p_aim_offset: Vector2 = Vector2.ZERO,
	p_extra_sources: Array[ModSource] = [],
	p_mission: MissionState = null
) -> void:
	unit = p_unit
	weapon_id = p_weapon_id
	target_cell = p_target_cell
	aim_offset = p_aim_offset
	extra_sources = p_extra_sources
	mission = p_mission


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false

	var weapon: Part = actual.shell.find_part(weapon_id)
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
	for part: Part in actual.shell.living_parts():
		if part != weapon:
			manipulators.append(part)
	return PartGraph.can_operate(weapon, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var weapon: Part = actual.shell.find_part(weapon_id)
	actual.ap -= weapon.ap_cost

	# docs/10 taskblock02 F3: firing faces the shooter toward the target
	# for free, inside apply() same as AP spend — never a separate charge,
	# and never skipped just because this is a preview (a queued shot's
	# preview should show the shooter's final rotation too).
	if actual.cell != target_cell:
		FaceAction.face_for_free(
			state, actual, FaceAction.orientation_toward(actual.cell, target_cell)
		)

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

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + aim_offset
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
		# The shooter's own body sits at the ray's own origin (depth <= 0)
		# and can otherwise satisfy `_find_next`'s point-containment check
		# just like the target can when the two happen to share a lateral
		# position — excluded on this first lookup only, the same mechanism
		# a ricochet uses to skip the body it just bounced off, so a shot
		# fired at a collinear target never reaches back into the shooter's
		# own chest.
		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			origin,
			direction,
			point,
			damage,
			crit_chance,
			state,
			state.material_table,
			state.rng,
			0,
			DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
			DamageResolver.DEFAULT_DAMAGE_FLOOR,
			DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
			actual.shell.all_parts()
		)
		for result: ImpactResult in results:
			_log_impact(state, actual, result)

	# Phase 6 placeholder: no living parts left disables the unit. Phase 7
	# (docs/04) replaces this with the real rule — destroying the specific
	# part hosting the Matrix ejects it — which fires strictly earlier than
	# "every part destroyed," so it supersedes rather than conflicts with
	# this conservative stand-in.
	if target.alive and target.shell.living_parts().is_empty():
		state.kill_unit(target)

	state.log_action(
		(
			"AttackAction: unit %d fired %s (burst %d) at %s"
			% [actual.id, weapon_id, weapon.burst, target_cell]
		)
	)


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
	# docs/09 "if it changed the world, it's in the log": which UNIT actually
	# took the hit (not just which part) — a ricochet can tag a third party,
	# so this is never assumed to be the shooter's own original target.
	# -1 for cover/terrain, which has no unit id.
	var target_unit_id: int = result.region.body.id if result.region.body is Unit else -1
	var data: Dictionary = {
		"outcome": result.outcome,
		"part": result.region.part.id,
		"target_unit_id": target_unit_id,
		"damage": result.part_damage,
		"bypassed_armor": result.bypassed_armor,
		"is_crit": result.is_crit,
		"is_double_crit": result.is_double_crit,
	}
	var event := LogEvent.new(
		state.round_number, Enums.Phase.RESOLUTION, attacker.id, &"impact", data, text
	)
	state.combat_log.emit(event)

	if result.destroyed_part:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"part_destroyed",
				{"part": result.region.part.id},
				"part_destroyed: %s" % result.region.part.id
			)
		)
		_credit_salvage(state, attacker, result.region.part)
		# taskblock-09 A1/A2: "if it changed the world, it's in the log" —
		# is_mangled/is_disabled are real, visible state changes (a
		# quartered DT, a dead weapon), not just bookkeeping alongside
		# part_destroyed.
		if result.region.part.is_mangled:
			state.combat_log.emit(
				LogEvent.new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker.id,
					&"part_mangled",
					{"part": result.region.part.id},
					"part_mangled: %s" % result.region.part.id
				)
			)
		if result.region.part.is_disabled:
			state.combat_log.emit(
				LogEvent.new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker.id,
					&"part_disabled",
					{"part": result.region.part.id},
					"part_disabled: %s" % result.region.part.id
				)
			)
	# taskblock-09 A3: renamed from "cook_off" — DETONATE, not cook-off.
	for detonated: Unit in result.detonated_units:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"detonate",
				{"source_part": result.region.part.id, "unit": detonated.id},
				"detonate: %s hit unit %d" % [result.region.part.id, detonated.id]
			)
		)
	# taskblock-09 A4: each fragment ray is its own full impact — same
	# logging path, recursively, so a fragment that itself penetrates/
	# deflects/ricochets is logged exactly like any other projectile.
	for fragment_result: ImpactResult in result.fragment_hits:
		_log_impact(state, attacker, fragment_result)
	if result.meltdown_armed:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"meltdown_armed",
				{"part": result.region.part.id},
				"meltdown_armed: %s" % result.region.part.id
			)
		)
	if result.ejected_matrix != null:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"matrix_ejected",
				{"host_part": result.region.part.id, "matrix": result.ejected_matrix.id},
				"matrix_ejected: %s from %s" % [result.ejected_matrix.id, result.region.part.id]
			)
		)
	# docs/04 taskblock02 Pass D1: the shell root destroyed while hosting an
	# ATTACHED surrogate (not a bare matrix) drops the whole surrogate,
	# matrix and all — distinct from matrix_ejected above, never both on
	# the same impact (DamageResolver.eject_surrogate_if_needed only fires
	# when eject_matrix_if_needed didn't).
	if result.ejected_surrogate != null:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"surrogate_ejected",
				{"host_part": result.region.part.id, "surrogate": result.ejected_surrogate.id},
				(
					"surrogate_ejected: %s from %s"
					% [result.ejected_surrogate.id, result.region.part.id]
				)
			)
		)
	if result.demoted_unit != null:
		var cause: String = (
			"matrix_ejected" if result.ejected_matrix != null else "surrogate_ejected"
		)
		var demotion_data: Dictionary = {
			"from": result.demoted_tier_before.id,
			"to": result.demoted_unit.surrogate_tier.id,
			"cause": cause,
		}
		var demotion_text: String = (
			"surrogate_demoted: unit %d %s -> %s (%s)"
			% [
				result.demoted_unit.id,
				result.demoted_tier_before.id,
				result.demoted_unit.surrogate_tier.id,
				cause,
			]
		)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				result.demoted_unit.id,
				&"surrogate_demoted",
				demotion_data,
				demotion_text
			)
		)
	# taskblock-09 C/D: a severed joint drops its whole intact subtree at
	# once — one event per part in it, never a summary, matching docs/09's
	# "if it changed the world, it's in the log." This is the ONLY producer
	# of `dropped_subtree` now (destroyed_part above is a wholly separate,
	# mutually exclusive path — MANGLE/DISABLE/DETONATE/FRAGMENT/MELTDOWN
	# never detach), so nothing here was credited/logged earlier the way a
	# destroyed part's own salvage already was above.
	for dropped: Part in result.dropped_subtree:
		_credit_salvage(state, attacker, dropped)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"subtree_dropped",
				{"part": dropped.id},
				"subtree_dropped: %s" % dropped.id
			)
		)


## docs/10 taskblock04 C3: "cut it apart or destroy it, get the resources...
## this is where docs/07's harvest loop finally touches the board." A
## no-op with no mission context (a standalone battle) or on a part with
## nothing to salvage (everything that isn't a field object) — the same
## MissionState.gather_resource() a real GatherAction call already uses,
## never a separate crediting path.
func _credit_salvage(state: CombatState, attacker: Unit, destroyed: Part) -> void:
	if mission == null or destroyed.salvage_yield.is_empty():
		return
	for resource_id: StringName in destroyed.salvage_yield:
		var amount: int = int(destroyed.salvage_yield[resource_id])
		mission.gather_resource(resource_id, amount)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"salvage_credited",
				{"part": destroyed.id, "resource": resource_id, "amount": amount},
				"salvage_credited: %d %s from %s" % [amount, resource_id, destroyed.id]
			)
		)


func describe() -> String:
	return "AttackAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]


## docs/09 taskblock06 Pass E: reads the WEAPON's own speed, not a fixed
## per-action-type constant — "a fast weapon can out-speed an overwatch
## trigger," which only works if the number lives on the weapon Part
## itself. Falls back to the action's own neutral 0.0 (never a name
## match/hardcoded ladder) if the actual unit or weapon can't be found —
## the same "never crash, never silently invent" posture is_legal() uses.
func speed(state: CombatState) -> float:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null:
		return super.speed(state)
	var weapon: Part = actual.shell.find_part(weapon_id)
	if weapon == null:
		return super.speed(state)
	return weapon.speed


func unit_id() -> int:
	return unit.id
