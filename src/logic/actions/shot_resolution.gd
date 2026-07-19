class_name ShotResolution
extends RefCounted

## taskblock-13 Pass C: the impact-resolve-and-log loop `AttackAction`
## originally owned alone (one `DamageResolver.resolve_shot` call, then a
## ~160-line cascade of part_destroyed/detonate/fragment/matrix_ejected/
## surrogate_ejected/surrogate_demoted/subtree_dropped event logging),
## factored out so `BurstAction` (N independent pulls, not one) can share
## it byte-for-byte instead of duplicating that cascade. `mission` is
## passed explicitly by each caller — salvage crediting only, no shared
## mutable state between them.


## Resolves one shot landing at `point` and logs every consequence to
## `state.combat_log` — side effects only, exactly what AttackAction's
## own per-point loop body used to do inline.
##
## `is_dud` (taskblock-19 Pass C2): true when this shot fired under a
## dud-capable weapon's own `min_range` — the damage cascade runs
## identically (see `RangeModel.is_dud`'s own doc comment: no separate
## payload system exists to suppress), only the log entry differs, so a
## future payload/AoE system has a real flag to check.
static func resolve_and_log_point(
	state: CombatState,
	attacker: Unit,
	origin: Vector2,
	direction: Vector2,
	point: Vector2,
	damage: float,
	crit_chance: float,
	bonus_pen: float,
	mission: MissionState,
	is_dud: bool = false
) -> void:
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
		attacker.shell.all_parts(),
		bonus_pen
	)
	for result: ImpactResult in results:
		_log_impact(state, attacker, result, mission, is_dud)


static func _log_impact(
	state: CombatState,
	attacker: Unit,
	result: ImpactResult,
	mission: MissionState,
	is_dud: bool = false
) -> void:
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
		"is_dud": is_dud,
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
				"%s" % result.region.part.id
			)
		)
		_credit_salvage(state, attacker, result.region.part, mission)
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
					"%s" % result.region.part.id
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
					"%s" % result.region.part.id
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
				"%s hit unit %d" % [result.region.part.id, detonated.id]
			)
		)
	# taskblock-09 A4: each fragment ray is its own full impact — same
	# logging path, recursively, so a fragment that itself penetrates/
	# deflects/ricochets is logged exactly like any other projectile.
	for fragment_result: ImpactResult in result.fragment_hits:
		_log_impact(state, attacker, fragment_result, mission)
	if result.meltdown_armed:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"meltdown_armed",
				{"part": result.region.part.id},
				"%s" % result.region.part.id
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
				"%s from %s" % [result.ejected_matrix.id, result.region.part.id]
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
				"%s from %s" % [result.ejected_surrogate.id, result.region.part.id]
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
			"unit %d %s -> %s (%s)"
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
		_credit_salvage(state, attacker, dropped, mission)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"subtree_dropped",
				{"part": dropped.id},
				"%s" % dropped.id
			)
		)


## docs/10 taskblock04 C3: "cut it apart or destroy it, get the resources...
## this is where docs/07's harvest loop finally touches the board." A
## no-op with no mission context (a standalone battle) or on a part with
## nothing to salvage (everything that isn't a field object) — the same
## MissionState.gather_resource() a real GatherAction call already uses,
## never a separate crediting path.
static func _credit_salvage(
	state: CombatState, attacker: Unit, destroyed: Part, mission: MissionState
) -> void:
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
				"%d %s from %s" % [amount, resource_id, destroyed.id]
			)
		)
