class_name Suppression
extends RefCounted

## taskblock-19 Pass E / taskblock-25 Pass E: "real tactics games gate
## face-to-face crowding with suppression." Adjacency to a living enemy
## disarms a two-handed weapon (real, enforced legality, stops the
## crowding outright), and leaving an adjacent tile draws a free "attack
## of opportunity" — now (docs/PLAN.md "Phase M — Melee") a real melee
## strike with the enemy's own default melee weapon, resolved through the
## same shot plane a queued stab uses, not the taskblock-19 stub. Both
## halves share `adjacent_living_enemies` as their one predicate, the same
## "never two independently-drifting notions of adjacency" principle
## `Overwatch._qualifying_weapon` already established for its own trigger.


## Every living unit of a different squad standing orthogonally or
## diagonally adjacent to `cell` — the one shared adjacency predicate.
static func adjacent_living_enemies(state: CombatState, unit: Unit, cell: Vector2i) -> Array[Unit]:
	var result: Array[Unit] = []
	for candidate: Unit in state.units:
		if candidate == unit or not candidate.alive or candidate.squad_id == unit.squad_id:
			continue
		if Grid.distance_chebyshev(cell, candidate.cell) == 1:
			result.append(candidate)
	return result


static func is_suppressed(state: CombatState, unit: Unit) -> bool:
	return not adjacent_living_enemies(state, unit, unit.cell).is_empty()


static func is_long_gun(weapon: Part) -> bool:
	return weapon != null and weapon.weapon_def != null and weapon.weapon_def.two_handed


## taskblock-19 Pass E: "adjacent to an enemy is suppressed — can't use a
## long gun." The actual legality gate `AttackAction`/`BurstAction` both
## read, never a second, independently-maintained adjacency check.
static func blocks_weapon(state: CombatState, unit: Unit, weapon: Part) -> bool:
	return is_long_gun(weapon) and is_suppressed(state, unit)


## taskblock-19 Pass E: "moving OUT of a tile adjacent to an enemy lets
## that enemy make a free melee attack as you leave." Every living enemy
## adjacent to `from_cell` that is NOT also adjacent to `to_cell` — a
## sidestep that stays adjacent to the SAME enemy draws no attack, only a
## genuine departure does. Speculative and non-mutating (mirrors
## `Overwatch.would_trigger_at`'s own "ask without firing" shape) so the
## AI's own decision weighting and the real mid-move trigger share one
## predicate.
static func would_trigger_opportunity_attack(
	state: CombatState, unit: Unit, from_cell: Vector2i, to_cell: Vector2i
) -> Array[Unit]:
	if from_cell == to_cell:
		return []
	var leaving: Array[Unit] = []
	for enemy: Unit in adjacent_living_enemies(state, unit, from_cell):
		if Grid.distance_chebyshev(to_cell, enemy.cell) != 1:
			leaving.append(enemy)
	return leaving


## taskblock-25 Pass E: "an opportunity attack — moving out of a tile
## adjacent to an enemy — resolves as a real melee strike (the enemy's
## default melee, a stab/punch) instead of the stubbed penalty." Each
## `attacker`'s own melee weapon (`ActionCatalog.provider_for(attacker,
## &"stab")` — the SAME provider lookup a queued StabAction's own action
## bar reads, never a second notion of "what's this unit's melee") fires
## through `ShotResolution.resolve_and_log_point`, the identical
## resolve-and-log primitive `StabAction.apply()` itself calls — real
## armor DT/deflection/penetration, `DEFLECT_MODE_SLIDE` and the weapon's
## own `stab_width` spherecast, same as a queued stab. An attacker with no
## melee weapon at all (before taskblock-25 Pass F's baseline punch
## exists) simply has nothing to swing — a no-op, not a fallback stub.
##
## `AttackAction`'s own posture, not the old stub's: a real strike rolls
## dartboard scatter and a crit chance, so — unlike the old deterministic
## stub, safe to preview — RESOLUTION alone decides whether it actually
## lands (docs/09).
static func resolve_opportunity_attacks(
	state: CombatState, mover: Unit, attackers: Array[Unit]
) -> void:
	for attacker: Unit in attackers:
		var weapon: Part = ActionCatalog.provider_for(attacker, &"stab")
		if weapon == null:
			continue
		var direction := Vector2(mover.cell - attacker.cell)
		if direction.is_zero_approx():
			continue
		state.log_action(
			"Suppression: unit %d opportunity-attacks unit %d" % [attacker.id, mover.id]
		)
		if state.is_preview:
			continue
		var origin := Vector2(attacker.cell.x, attacker.cell.y)
		# taskblock-37 Pass A: a real muzzle height (this weapon is a real
		# Part on the attacker), matching AttackAction's own precision.
		var muzzle: Vector3 = UnitGeometry.shouldered_muzzle_point(attacker, weapon)
		var elevation: Dictionary = ShotPlane.elevation_for(
			origin, muzzle.y, attacker.cell, mover.cell, state.grid
		)
		var plane: Array[Region] = ShotPlane.build(elevation.origin, elevation.direction, state)
		var aim_point: Vector2 = ShotPlane.center_of(plane, mover)
		# taskblock-37 Pass A: the aim point's own real depth — see
		# AttackAction's own doc comment for why `_find_next` needs this
		# anchor, not just the vertical_slope itself.
		var aim_depth: float = ShotPlane.depth_of(plane, mover)
		var damage: float = WeaponResolver.resolve_damage(weapon, []).current
		var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, []).current
		var bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, []).current
		var stab_width: float = weapon.weapon_def.stab_width if weapon.weapon_def != null else 0.0
		ShotResolution.resolve_and_log_point(
			state,
			attacker,
			origin,
			direction,
			aim_point,
			damage,
			crit_chance,
			bonus_pen,
			null,
			false,
			RangeModel.max_range(weapon),
			muzzle.y,
			DamageResolver.DEFLECT_MODE_SLIDE,
			stab_width,
			elevation.vertical_slope,
			aim_depth
		)
		if mover.alive and mover.shell.living_parts().is_empty():
			state.kill_unit(mover)
