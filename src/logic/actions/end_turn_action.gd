class_name EndTurnAction
extends CombatAction

## taskblock-22 Pass A2: `mission`, optional, threaded the same way
## AttackAction/GatherAction/ExtractAction already take one — every turn a
## unit ends is exactly the once-per-round cadence "held the tile" needs
## to be checked at (each unit gets one turn per round), so this is where
## the player squad's own passive extraction hold lives, rather than a
## second, CombatState-side hook (CombatState never depends on
## MissionState — docs/00's own one-way layering). `null` (every existing
## caller/test) simply skips the hold check entirely, unchanged.
var unit: Unit
var mission: MissionState


func _init(p_unit: Unit, p_mission: MissionState = null) -> void:
	unit = p_unit
	mission = p_mission


## Resolved through state.find_unit(), not the stored reference directly
## (docs/09): a preview's units are independent clones sharing `unit.id`.
## Deliberately does NOT require `actual.alive`: a unit can die mid-turn from
## its own queued action (e.g. cook-off, or a shot that reaches its own
## body), and turn order only ever advances via this action's apply() — if
## ending a dead unit's own turn were illegal, the engine would never call
## advance_turn() again and every subsequent turn would stall on a corpse.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	return actual != null and state.current_unit() == actual


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var text: String = "EndTurnAction: unit %d ended turn" % unit.id
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number, Enums.Phase.RESOLUTION, actual.id, &"turn_end", {}, "ended turn"
			)
		)
		if mission != null and actual.alive:
			_update_extraction_hold(state, actual)
	state.advance_turn()


## taskblock-22 Pass A2: "enter the tile, and if still there at the end of
## the next round, extracted. Leaving early cancels it." A flagged, simple
## approximation, not a true round-boundary event: since each unit gets
## exactly one turn per round, checking here — on THIS unit's own next
## turn — after having first been seen on the tile a turn ago is "roughly
## one round held," close enough to "~1.something rounds" per the
## taskblock's own explicitly tunable framing, without CombatState needing
## to depend on MissionState just to watch for true round boundaries.
## Player squad only — a non-player squad uses `ExtractAction`'s own fast,
## AP-costed path instead, never this passive one. Requires every mission
## objective complete first, same gate `ExtractAction` itself used to
## apply before this pass split the two mechanics apart.
func _update_extraction_hold(state: CombatState, actual: Unit) -> void:
	if actual.squad_id != mission.player_squad_id:
		return
	var tiles: Array = mission.team_extraction_cells.get(actual.squad_id, mission.extraction_cells)
	if not tiles.has(actual.cell):
		actual.extraction_hold_start_round = -1
		return
	var incomplete: bool = mission.objectives.any(
		func(o: StringName) -> bool: return o not in mission.completed_objectives
	)
	if incomplete:
		return
	if actual.extraction_hold_start_round == -1:
		actual.extraction_hold_start_round = state.round_number
		return
	if state.round_number > actual.extraction_hold_start_round:
		mission.extract_unit(actual)


func describe() -> String:
	return "EndTurnAction(unit=%d)" % unit.id
