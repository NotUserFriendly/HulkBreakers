class_name AttackAction
extends CombatAction

## Placeholder resolution: damages the target's first living part with no
## exposure weighting or cover interception. Phase 8 (Targeting.resolve_hit +
## DamageResolver) replaces this body; Phase 7 only needs AP-gated legality
## and turn-log behavior to be correct.

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
	if Grid.distance_chebyshev(attacker.cell, target.cell) > DEFAULT_RANGE:
		return false
	if not LoS.has_los(state.grid, attacker.cell, target.cell):
		return false
	return not target.chassis.living_parts().is_empty()


func apply(state: CombatState) -> void:
	attacker.ap -= AP_COST
	var living: Array[Part] = target.chassis.living_parts()
	if not living.is_empty():
		var part: Part = living[0]
		part.hp = maxi(part.hp - DEFAULT_DAMAGE, 0)

	if target.chassis.living_parts().is_empty():
		target.alive = false
		state.grid.set_occupant_id(target.cell, -1)

	state.log_action("AttackAction: unit %d attacked unit %d" % [attacker.id, target.id])


func describe() -> String:
	return "AttackAction(attacker=%d, target=%d)" % [attacker.id, target.id]
