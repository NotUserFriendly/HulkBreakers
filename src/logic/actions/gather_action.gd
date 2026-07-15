class_name GatherAction
extends CombatAction

## Gathers a resource node lying on the map (docs/07: "gather resources or
## hit objective") — the mission loop's own verb; before this, nothing in
## simulation ever called MissionState.gather_resource() except a test
## standing in for the player. `mission` is held directly rather than
## resolved through `state`: resource nodes and objectives are mission-
## scoped, outside CombatState entirely, so a TACTICS-time preview (docs/09)
## must never touch them — `apply()` spends AP either way (so a later
## queued action still previews correctly) but skips the real gather.

const DEFAULT_AP_COST := 2

var mission: MissionState
var unit: Unit
var cell: Vector2i
var ap_cost: int


func _init(
	p_mission: MissionState, p_unit: Unit, p_cell: Vector2i, p_ap_cost: int = DEFAULT_AP_COST
) -> void:
	mission = p_mission
	unit = p_unit
	cell = p_cell
	ap_cost = p_ap_cost


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.ap < ap_cost or actual.cell != cell:
		return false
	return mission.resource_nodes.has(cell)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	actual.ap -= ap_cost

	if state.is_preview:
		return

	var node: Dictionary = mission.resource_nodes[cell]
	var resource_id: StringName = node.resource
	var amount: int = node.amount
	mission.gather_resource(resource_id, amount)
	mission.resource_nodes.erase(cell)
	var objective: StringName = node.get("objective", &"")
	if objective != &"":
		mission.complete_objective(objective)

	var text: String = (
		"GatherAction: unit %d gathered %d %s at %s" % [actual.id, amount, resource_id, cell]
	)
	state.log_action(text)
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			actual.id,
			&"gather",
			{"resource": resource_id, "amount": amount, "cell": cell},
			text
		)
	)


func describe() -> String:
	return "GatherAction(unit=%d, cell=%s)" % [unit.id, cell]
