class_name RunState
extends Resource

## Persistence across fights: the roster survives regardless of outcome
## (matrices can't die, only lose their chassis — Phase 8), stash accumulates
## salvage, seed drives the run's determinism (Appendix A).

const VICTORY_XP_REWARD: int = 10  # tunable — no formula specified in PLAN.md

@export var roster: Array[Matrix] = []
@export var chassis_stash: Array[Chassis] = []
@export var part_stash: Array[Part] = []
@export var salvage: int = 0
@export var credits: int = 0
@export var seed: int = 0


## Player's mechs got wrecked: strip every player matrix's chassis (parts are
## lost) but the matrices themselves always return to the roster.
func resolve_defeat(state: CombatState, player_squad_id: int) -> void:
	_apply_recovery_states(state)
	for unit: Unit in state.squads.get(player_squad_id, []):
		for slot_type: Variant in unit.chassis.slots.keys().duplicate():
			unit.chassis.remove(slot_type)
		_ensure_in_roster(unit.matrix)


## Player won: matrices gain XP, defeated enemies' parts and chassis are
## salvaged into the stash.
func resolve_victory(state: CombatState, player_squad_id: int) -> void:
	_apply_recovery_states(state)
	for unit: Unit in state.squads.get(player_squad_id, []):
		unit.matrix.xp += VICTORY_XP_REWARD
		_ensure_in_roster(unit.matrix)

	for squad_id: Variant in state.squads.keys():
		if squad_id == player_squad_id:
			continue
		for unit: Unit in state.squads[squad_id]:
			for part: Part in unit.chassis.slots.values():
				part_stash.append(part)
			unit.chassis.slots.clear()
			chassis_stash.append(unit.chassis)


func apply_perk(matrix: Matrix, perk: StringName) -> void:
	if not matrix.perks.has(perk):
		matrix.perks.append(perk)


func _ensure_in_roster(matrix: Matrix) -> void:
	if not roster.has(matrix):
		roster.append(matrix)


## RECOVERED: still piloting at end, picked up (held), or never ejected.
## LEFT_BEHIND: an ejected Matrix is still lying on the field.
func _apply_recovery_states(state: CombatState) -> void:
	var recovered: Dictionary = {}  # Matrix -> true
	var on_ground: Dictionary = {}  # Matrix -> true

	for unit: Unit in state.units:
		if unit.alive:
			recovered[unit.matrix] = true
		if unit.held_matrix != null:
			recovered[unit.held_matrix] = true

	for items: Array in state.grid.field_items.values():
		for item: Variant in items:
			if item is Matrix:
				on_ground[item] = true

	for matrix: Matrix in recovered.keys():
		matrix.recovery_state = Enums.RecoveryState.RECOVERED
		matrix.pending_return_penalty = false

	for matrix: Matrix in on_ground.keys():
		if recovered.has(matrix):
			continue
		matrix.recovery_state = Enums.RecoveryState.LEFT_BEHIND
		matrix.pending_return_penalty = true
