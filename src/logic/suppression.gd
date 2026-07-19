class_name Suppression
extends RefCounted

## taskblock-19 Pass E: "real tactics games gate face-to-face crowding
## with suppression." Melee itself isn't built — the AI PRETENDS it is:
## adjacency to a living enemy disarms a two-handed weapon (real, enforced
## legality, stops the crowding outright), and leaving an adjacent tile
## draws a free "attack of opportunity" whose resolution is a flagged
## stub (no real melee weapon/geometry exists to resolve it properly).
## Both halves share `adjacent_living_enemies` as their one predicate, the
## same "never two independently-drifting notions of adjacency" principle
## `Overwatch._qualifying_weapon` already established for its own trigger.

## Flagged placeholder — no balance number was specified for the stub
## hit, only that it must be a REAL, felt cost (not a no-op) so avoiding
## it is worth an AI's own decision weight. Ask before tuning.
const STUB_OPPORTUNITY_DAMAGE := 3.0


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


## taskblock-19 Pass E: "the free melee attack resolves as a stub (a
## flagged placeholder hit) until melee exists." A flat, un-armored,
## un-resolved hit straight to the mover's root part — deliberately NOT
## routed through DamageResolver's real penetration/armor cascade (there
## is no melee weapon/ray geometry to resolve against), so the log entry
## is unmistakably a placeholder, never mistaken for a real shot.
static func resolve_opportunity_attacks(
	state: CombatState, mover: Unit, attackers: Array[Unit]
) -> void:
	for attacker: Unit in attackers:
		var root: Part = mover.shell.root
		if root == null or root.hp <= 0:
			continue
		root.hp = maxi(0, root.hp - int(STUB_OPPORTUNITY_DAMAGE))
		state.log_action(
			"Suppression: unit %d opportunity-attacks unit %d (stub)" % [attacker.id, mover.id]
		)
		if not state.is_preview:
			state.combat_log.emit(
				LogEvent.new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker.id,
					&"opportunity_attack",
					{
						"target_unit_id": mover.id,
						"damage": STUB_OPPORTUNITY_DAMAGE,
						"is_stub": true
					},
					"unit %d attacks unit %d as it leaves (stub)" % [attacker.id, mover.id]
				)
			)
		if mover.alive and mover.shell.living_parts().is_empty():
			state.kill_unit(mover)
