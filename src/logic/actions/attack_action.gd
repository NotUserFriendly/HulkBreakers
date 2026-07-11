class_name AttackAction
extends CombatAction

## Resolves via Targeting.resolve_hit (exposure-weighted part selection + cover
## interception, Appendix C) and DamageResolver.apply. Requires the attacker to
## have at least one living WEAPON part — destroying an attacker's only weapon
## removes its ability to attack.

const AP_COST: int = 1
const DEFAULT_RANGE: int = 8
const DEFAULT_DAMAGE: int = 3

var attacker: Unit
var target: Unit


func _init(p_attacker: Unit, p_target: Unit) -> void:
	attacker = p_attacker
	target = p_target


func is_legal(state: CombatState) -> bool:
	if not attacker.alive or not target.alive:
		return false
	if state.current_unit() != attacker:
		return false
	if attacker == target or attacker.squad_id == target.squad_id:
		return false
	if attacker.ap < AP_COST:
		return false
	if not _has_living_weapon(attacker):
		return false
	if Grid.distance_chebyshev(attacker.cell, target.cell) > DEFAULT_RANGE:
		return false
	if not LoS.has_los(state.grid, attacker.cell, target.cell):
		return false
	return not target.chassis.living_parts().is_empty()


func apply(state: CombatState) -> void:
	attacker.ap -= AP_COST
	var hit: HitResult = Targeting.resolve_hit(attacker, target, state.grid, state.rng)
	DamageResolver.apply(hit, DEFAULT_DAMAGE, state, target)
	state.log_action("AttackAction: unit %d attacked unit %d" % [attacker.id, target.id])


func _has_living_weapon(unit: Unit) -> bool:
	for part: Part in unit.chassis.slots.values():
		if part.part_type == Enums.PartType.WEAPON and part.hp > 0:
			return true
	return false


func describe() -> String:
	return "AttackAction(attacker=%d, target=%d)" % [attacker.id, target.id]
