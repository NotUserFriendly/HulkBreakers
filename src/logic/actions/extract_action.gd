class_name ExtractAction
extends CombatAction

## taskblock-22 Pass A2: the FAST, asymmetric half of extraction (docs/07:
## "EXIT with loot") — "an Extract ACTION: reach a team extraction tile,
## spend 1 AP, gone immediately." Deliberately restricted to a non-player
## squad: the player's own squad never gets this cheap button at all, it
## has to hold the tile instead (`EndTurnAction`'s own hold-check) —
## that's the whole asymmetry the taskblock calls for, not an oversight.
## No longer ends the mission by itself (taskblock-21's own single-call
## `mission.extract()` wiring was the taskblock-22 A1 bug: "ends the whole
## bout on the first escapee") — `MissionState.extract_unit()` now owns
## deciding whether this ALSO happens to be the squad's last unit out.

const AP_COST := 1

var mission: MissionState
var unit: Unit


func _init(p_mission: MissionState, p_unit: Unit) -> void:
	mission = p_mission
	unit = p_unit


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.squad_id == mission.player_squad_id:
		return false
	if actual.ap < AP_COST:
		return false
	# taskblock-21 Pass D: team-coded cells win when this unit's own squad
	# has any authored (a real two-team bout always does, for both squads);
	# `extraction_cells` is the fallback, exactly as before this pass, for
	# every mission that never populates the team-coded set at all.
	var valid_cells: Array = mission.team_extraction_cells.get(
		actual.squad_id, mission.extraction_cells
	)
	return valid_cells.has(actual.cell)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	actual.ap -= AP_COST
	if state.is_preview:
		# Leaving the board for real is never something a TACTICS-time
		# preview may actually carry out — AP still spends (matching every
		# other action's own preview contract) so a later queued action in
		# the same preview still costs correctly.
		return
	state.log_action("ExtractAction: unit %d extracted" % actual.id)
	mission.extract_unit(actual)


func describe() -> String:
	return "ExtractAction(unit=%d)" % unit.id
