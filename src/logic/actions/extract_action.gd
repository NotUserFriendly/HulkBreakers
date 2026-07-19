class_name ExtractAction
extends CombatAction

## Calls the mission (docs/07: "EXTRACT with loot") — legal only once a unit
## stands on one of `mission.extraction_cells` and every objective is
## complete. Banks the whole haul and returns every matrix
## (MissionState.extract()); free of AP cost — this ends the mission, it
## isn't a tactical maneuver units budget turns around.

var mission: MissionState
var unit: Unit


func _init(p_mission: MissionState, p_unit: Unit) -> void:
	mission = p_mission
	unit = p_unit


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	# taskblock-21 Pass D: team-coded cells win when this unit's own squad
	# has any authored (a real two-team bout always does, for both squads);
	# `extraction_cells` is the fallback, exactly as before this pass, for
	# every mission that never populates the team-coded set at all.
	var valid_cells: Array = mission.team_extraction_cells.get(
		actual.squad_id, mission.extraction_cells
	)
	if not valid_cells.has(actual.cell):
		return false
	for objective: StringName in mission.objectives:
		if objective not in mission.completed_objectives:
			return false
	return true


func apply(state: CombatState) -> void:
	if state.is_preview:
		# Extraction ends the mission outright — never something a
		# TACTICS-time preview may actually carry out.
		return

	mission.extract()
	var text: String = "ExtractAction: unit %d extracted the team" % unit.id
	state.log_action(text)
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			unit.id,
			&"extract",
			{},
			"extracted the team"
		)
	)


func describe() -> String:
	return "ExtractAction(unit=%d)" % unit.id
