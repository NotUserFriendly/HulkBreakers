extends GutTest

## taskblock-22 Pass E: batteries, the Arc Welder, repair-with-scrap.


## A welder (with a docked, charged Tool Battery) held by a real hand, plus
## one damaged leg to repair — the minimum real assembly RepairResolver's
## own checks need to walk (PartGraph.can_operate requires a real
## manipulator, not just a bare weapon-shaped Part).
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
	return {"unit": unit, "welder": welder, "battery": battery, "target": target, "hand": hand}


func test_find_operable_welder_returns_the_welder_with_a_real_manipulator() -> void:
	var built: Dictionary = _make_welder_unit()

	assert_eq(RepairResolver.find_operable_welder(built.unit), built.welder)


func test_find_operable_welder_null_without_a_manipulator() -> void:
	var built: Dictionary = _make_welder_unit()
	built.hand.capabilities = [] as Array[StringName]  # no TRIGGER left to operate it

	assert_null(RepairResolver.find_operable_welder(built.unit))


func test_find_operable_welder_null_with_no_welder_at_all() -> void:
	var root := Part.new()
	root.id = &"torso"
	root.hp = 10
	root.max_hp = 10
	var unit := Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)

	assert_null(RepairResolver.find_operable_welder(unit))


func test_welder_battery_returns_the_docked_tool_battery() -> void:
	var built: Dictionary = _make_welder_unit()

	assert_eq(RepairResolver.welder_battery(built.welder), built.battery)


func test_welder_battery_null_with_an_empty_socket() -> void:
	var built: Dictionary = _make_welder_unit()
	built.welder.sockets[0].occupant = null

	assert_null(RepairResolver.welder_battery(built.welder))


func test_can_repair_with_true_when_welder_and_charge_both_present() -> void:
	var built: Dictionary = _make_welder_unit()

	assert_true(RepairResolver.can_repair_with(built.unit))


func test_can_repair_with_false_once_the_battery_is_drained() -> void:
	var built: Dictionary = _make_welder_unit(5, 10, 0.0)

	assert_false(RepairResolver.can_repair_with(built.unit))


func test_can_repair_with_false_once_the_battery_is_destroyed() -> void:
	var built: Dictionary = _make_welder_unit()
	built.battery.hp = 0

	assert_false(RepairResolver.can_repair_with(built.unit))


func test_heal_amount_capped_at_three() -> void:
	var target := Part.new()
	target.hp = 1
	target.max_hp = 20

	assert_eq(RepairResolver.heal_amount_for(target), 3)


func test_heal_amount_never_exceeds_whats_actually_missing() -> void:
	var target := Part.new()
	target.hp = 8
	target.max_hp = 9

	assert_eq(RepairResolver.heal_amount_for(target), 1)


func test_scrap_cost_matches_heal_amount_one_to_one() -> void:
	var target := Part.new()
	target.hp = 5
	target.max_hp = 10

	assert_eq(RepairResolver.scrap_cost_for(target), RepairResolver.heal_amount_for(target))


func test_scrap_resource_id_is_the_targets_own_material() -> void:
	var target := Part.new()
	target.material = &"ceramic"

	assert_eq(RepairResolver.scrap_resource_id_for(target), &"ceramic")


func test_repairable_parts_lists_only_damaged_living_parts() -> void:
	var built: Dictionary = _make_welder_unit(5, 10)

	var damaged: Array[Part] = RepairResolver.repairable_parts(built.unit)

	assert_has(damaged, built.target)
	assert_does_not_have(damaged, built.welder, "the welder itself is undamaged")


func test_repairable_parts_excludes_a_fully_destroyed_part() -> void:
	var built: Dictionary = _make_welder_unit(0, 10)

	var damaged: Array[Part] = RepairResolver.repairable_parts(built.unit)

	assert_does_not_have(
		damaged, built.target, "a 0-hp part is destroyed, not a field-repair candidate"
	)


func test_repairable_parts_excludes_a_fully_healed_part() -> void:
	var built: Dictionary = _make_welder_unit(10, 10)

	assert_does_not_have(RepairResolver.repairable_parts(built.unit), built.target)
