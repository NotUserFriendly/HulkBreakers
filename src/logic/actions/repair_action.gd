class_name RepairAction
extends CombatAction

## taskblock-22 Pass E: "a welder with a charged battery can repair up to
## 3 HP for 4 AP and a portion of its battery's power," consuming scrap of
## the target part's own material (RepairResolver.scrap_resource_id_for) —
## 1:1 with the HP actually restored. `mission` is required, not optional
## (like GatherAction/ExtractAction): repair is inherently mission-scoped,
## it has nothing to consume without a real scrap pool to draw from.

var unit: Unit
var welder_id: StringName
var target_part_id: StringName
var mission: MissionState


func _init(
	p_unit: Unit, p_welder_id: StringName, p_target_part_id: StringName, p_mission: MissionState
) -> void:
	unit = p_unit
	welder_id = p_welder_id
	target_part_id = p_target_part_id
	mission = p_mission


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	var welder: Part = actual.shell.find_part(welder_id)
	if welder == null or welder.hp <= 0 or WoundEffects.is_disabled_by_wounds(welder):
		return false
	if not welder.tags.has(RepairResolver.WELDER_TAG):
		return false
	if actual.ap < RepairResolver.REPAIR_AP_COST:
		return false
	var battery: Part = RepairResolver.welder_battery(welder)
	if battery == null or battery.hp <= 0 or battery.battery_charge <= 0.0:
		return false
	var target: Part = actual.shell.find_part(target_part_id)
	if target == null or target.hp <= 0 or target.hp >= target.max_hp:
		return false
	var heal: int = RepairResolver.heal_amount_for(target)
	if heal <= 0:
		return false
	var scrap_id: StringName = RepairResolver.scrap_resource_id_for(target)
	var available: int = int(mission.gathered_resources.get(scrap_id, 0))
	if available < RepairResolver.scrap_cost_for(target):
		return false

	var manipulators: Array[Part] = []
	for part: Part in actual.shell.operable_parts():
		if part != welder:
			manipulators.append(part)
	return PartGraph.can_operate(welder, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	actual.ap -= RepairResolver.REPAIR_AP_COST
	if state.is_preview:
		# Real HP/scrap/battery changes are never something a TACTICS-time
		# preview may actually carry out — AP still spends (every other
		# action's own preview contract) so a later queued action in the
		# same preview still costs correctly.
		return

	var welder: Part = actual.shell.find_part(welder_id)
	var battery: Part = RepairResolver.welder_battery(welder)
	var target: Part = actual.shell.find_part(target_part_id)
	var heal: int = RepairResolver.heal_amount_for(target)
	var scrap_id: StringName = RepairResolver.scrap_resource_id_for(target)
	var scrap_cost: int = RepairResolver.scrap_cost_for(target)

	mission.gathered_resources[scrap_id] = (
		int(mission.gathered_resources.get(scrap_id, 0)) - scrap_cost
	)
	if mission.gathered_resources[scrap_id] <= 0:
		mission.gathered_resources.erase(scrap_id)

	# "A portion of its battery's power" — flagged, not a tuned design
	# number: one turn's worth of the battery's own max discharge rate,
	# the same amount `PowerResolver.discharge_batteries` already treats
	# as "what a battery gives up in a turn," never more than it actually
	# holds.
	battery.battery_charge -= minf(battery.battery_charge, battery.battery_power_out)

	target.hp = mini(target.max_hp, target.hp + heal)

	var text: String = "RepairAction: unit %d repairs %s for %d HP" % [actual.id, target.id, heal]
	state.log_action(text)
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			actual.id,
			&"repaired",
			{
				"part": target.id,
				"heal": heal,
				"scrap_resource": scrap_id,
				"scrap_spent": scrap_cost
			},
			text
		)
	)


func describe() -> String:
	return "RepairAction(unit=%d, target=%s)" % [unit.id, target_part_id]
