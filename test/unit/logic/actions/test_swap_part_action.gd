extends GutTest


func _make_unit(cell: Vector2i, arm: Part) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets = [shoulder]
	var shell := Shell.new(torso)
	shell.max_mass = 1000.0
	return Unit.new(Matrix.new(), shell, cell, 0)


func _make_arm(id: StringName) -> Part:
	var arm := Part.new()
	arm.id = id
	arm.hp = 5
	arm.max_hp = 5
	arm.attaches_to = [&"SHOULDER"]
	return arm


func test_swap_part_detaches_old_and_attaches_replacement() -> void:
	var old_arm := _make_arm(&"stump")
	var unit := _make_unit(Vector2i(0, 0), old_arm)
	var grid := Grid.new(5, 5)
	var replacement := _make_arm(&"gun_arm")
	grid.field_items[Vector2i(0, 0)] = [replacement]
	var state := CombatState.new(grid, [unit])

	var action := SwapPartAction.new(unit, &"torso", &"SHOULDER", &"gun_arm", 2)
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_eq(unit.shell.find_part(&"gun_arm"), replacement)
	assert_false(unit.shell.all_parts().has(old_arm), "the old arm must be off the assembly")
	assert_true(
		grid.field_items[Vector2i(0, 0)].has(old_arm),
		"the detached arm must drop as its own field item, not vanish"
	)
	assert_eq(unit.ap, unit.max_ap - 2)


func test_swap_part_emits_a_swap_part_event() -> void:
	var old_arm := _make_arm(&"stump")
	var unit := _make_unit(Vector2i(0, 0), old_arm)
	var grid := Grid.new(5, 5)
	var replacement := _make_arm(&"gun_arm")
	grid.field_items[Vector2i(0, 0)] = [replacement]
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	SwapPartAction.new(unit, &"torso", &"SHOULDER", &"gun_arm", 2).apply(state)

	var swaps: Array[LogEvent] = sink.events_of_kind(&"swap_part")
	assert_eq(swaps.size(), 1)
	assert_eq(swaps[0].unit_id, unit.id)
	assert_eq(swaps[0].data.get("replacement"), &"gun_arm")
	assert_eq(swaps[0].data.get("removed"), &"stump")


func test_swap_part_illegal_when_replacement_does_not_fit_the_socket_type() -> void:
	var old_arm := _make_arm(&"stump")
	var unit := _make_unit(Vector2i(0, 0), old_arm)
	var grid := Grid.new(5, 5)
	var wrong_fit := Part.new()
	wrong_fit.id = &"boot"
	wrong_fit.hp = 5
	wrong_fit.max_hp = 5
	wrong_fit.attaches_to = [&"FOOT"]
	grid.field_items[Vector2i(0, 0)] = [wrong_fit]
	var state := CombatState.new(grid, [unit])

	assert_false(SwapPartAction.new(unit, &"torso", &"SHOULDER", &"boot", 2).is_legal(state))


func test_swap_part_illegal_without_enough_ap() -> void:
	var old_arm := _make_arm(&"stump")
	var unit := _make_unit(Vector2i(0, 0), old_arm)
	var grid := Grid.new(5, 5)
	var replacement := _make_arm(&"gun_arm")
	grid.field_items[Vector2i(0, 0)] = [replacement]
	var state := CombatState.new(grid, [unit])
	unit.ap = 1

	assert_false(SwapPartAction.new(unit, &"torso", &"SHOULDER", &"gun_arm", 2).is_legal(state))
