extends GutTest

## taskblock-22 Pass E: RepairAction — "a welder with a charged battery
## can repair up to 3 HP for 4 AP and a portion of its battery's power,"
## consuming scrap of the target part's own material.


func _make_welder_unit(
	target_hp: int = 5, target_max_hp: int = 10, battery_charge: float = 6.0
) -> Dictionary:
	var target := Part.new()
	target.id = &"leg"
	target.material = &"steel"
	target.hp = target_hp
	target.max_hp = target_max_hp

	var battery := Part.new()
	battery.id = &"tool_battery"
	battery.hp = 3
	battery.max_hp = 3
	battery.battery_capacity = 6.0
	battery.battery_power_out = 3.0
	battery.battery_charge = battery_charge
	battery.tags = [&"POWER_SOURCE", &"BATTERY", &"TOOL_BATTERY"]

	var welder := Part.new()
	welder.id = &"welder"
	welder.hp = 4
	welder.max_hp = 4
	welder.attaches_to = [&"GRIP"]
	welder.requires = {&"TRIGGER": 1}
	welder.tags = [&"WELDER"]
	var battery_socket := Socket.new(&"TOOL_BATTERY")
	battery_socket.occupant = battery
	welder.sockets = [battery_socket]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = welder
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	var leg_socket := Socket.new(&"LEG")
	leg_socket.occupant = target
	torso.sockets = [hand_socket, leg_socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)
	var state := CombatState.new(Grid.new(5, 5), [unit])
	return {"unit": unit, "welder": welder, "battery": battery, "target": target, "state": state}


func _mission_with_scrap(state: CombatState, resource_id: StringName, amount: int) -> MissionState:
	var mission := MissionState.new(RunState.new(), state)
	mission.gather_resource(resource_id, amount)
	return mission


func test_is_legal_true_with_a_charged_welder_and_enough_scrap() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)

	var action := RepairAction.new(built.unit, &"welder", &"leg", mission)

	assert_true(action.is_legal(built.state))


func test_is_legal_false_without_enough_ap() -> void:
	var built: Dictionary = _make_welder_unit()
	built.unit.ap = 1
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)

	assert_false(RepairAction.new(built.unit, &"welder", &"leg", mission).is_legal(built.state))


func test_is_legal_false_with_no_welder() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)

	assert_false(
		RepairAction.new(built.unit, &"nonexistent", &"leg", mission).is_legal(built.state)
	)


func test_is_legal_false_with_a_drained_battery() -> void:
	var built: Dictionary = _make_welder_unit(5, 10, 0.0)
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)

	assert_false(RepairAction.new(built.unit, &"welder", &"leg", mission).is_legal(built.state))


func test_is_legal_false_on_a_fully_healed_target() -> void:
	var built: Dictionary = _make_welder_unit(10, 10)
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)

	assert_false(RepairAction.new(built.unit, &"welder", &"leg", mission).is_legal(built.state))


func test_is_legal_false_without_enough_matching_scrap() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 1)  # needs 3

	assert_false(RepairAction.new(built.unit, &"welder", &"leg", mission).is_legal(built.state))


## "A steel part needs steel scrap" — the wrong-material resource never
## substitutes, no matter how much of it is on hand.
func test_is_legal_false_with_the_wrong_material_scrap() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"ceramic", 99)

	assert_false(RepairAction.new(built.unit, &"welder", &"leg", mission).is_legal(built.state))


func test_apply_heals_the_target_spends_ap_scrap_and_battery_charge() -> void:
	var built: Dictionary = _make_welder_unit(5, 10)
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)
	var starting_ap: int = built.unit.ap

	RepairAction.new(built.unit, &"welder", &"leg", mission).apply(built.state)

	assert_eq(built.target.hp, 8, "5 hp + 3 (capped heal)")
	assert_eq(built.unit.ap, starting_ap - RepairResolver.REPAIR_AP_COST)
	assert_eq(mission.gathered_resources.get(&"steel", 0), 2, "5 scrap - 3 spent")
	assert_eq(built.battery.battery_charge, 3.0, "6.0 - battery_power_out (3.0)")


func test_apply_never_heals_past_max_hp() -> void:
	var built: Dictionary = _make_welder_unit(8, 9)  # only 1 hp missing
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)

	RepairAction.new(built.unit, &"welder", &"leg", mission).apply(built.state)

	assert_eq(built.target.hp, 9)
	assert_eq(mission.gathered_resources.get(&"steel", 0), 4, "only 1 scrap actually spent")


func test_apply_erases_the_resource_entry_once_fully_spent() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 3)  # exactly enough

	RepairAction.new(built.unit, &"welder", &"leg", mission).apply(built.state)

	assert_false(mission.gathered_resources.has(&"steel"), "spent to exactly 0 — must be erased")


func test_apply_emits_a_repaired_event() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)
	var sink := MemorySink.new()
	built.state.combat_log.add_sink(sink)

	RepairAction.new(built.unit, &"welder", &"leg", mission).apply(built.state)

	var events: Array[LogEvent] = sink.events_of_kind(&"repaired")
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("part"), &"leg")
	assert_eq(events[0].data.get("heal"), 3)


func test_apply_on_a_preview_spends_ap_but_never_touches_the_real_unit() -> void:
	var built: Dictionary = _make_welder_unit()
	var mission: MissionState = _mission_with_scrap(built.state, &"steel", 5)
	var starting_hp: int = built.target.hp
	var starting_scrap: int = mission.gathered_resources.get(&"steel", 0)
	var starting_ap: int = built.unit.ap

	var preview: CombatState = built.state.dup()
	var previewed_unit: Unit = preview.find_unit(built.unit.id)
	RepairAction.new(previewed_unit, &"welder", &"leg", mission).apply(preview)

	assert_eq(
		previewed_unit.ap,
		starting_ap - RepairResolver.REPAIR_AP_COST,
		"AP still spends on the preview's own clone, same as every other action"
	)
	assert_eq(built.target.hp, starting_hp, "the real part must be untouched by a preview")
	assert_eq(built.unit.ap, starting_ap, "the real unit's own AP must be untouched too")
	assert_eq(mission.gathered_resources.get(&"steel", 0), starting_scrap)
