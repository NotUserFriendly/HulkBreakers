extends GutTest


func _make_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"root"
	root.hp = 5
	root.max_hp = 5
	var shell := Shell.new(root)
	shell.max_mass = 1000.0
	return Unit.new(Matrix.new(), shell, cell, 0)


## A severed arm (dropped intact, docs/01) still holding a pistol in its hand.
func _make_dropped_arm() -> Part:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 6
	arm.max_hp = 6
	var grip := Socket.new(&"GRIP")
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 5
	pistol.max_hp = 5
	pistol.attaches_to = [&"GRIP"]
	grip.occupant = pistol
	arm.sockets = [grip]
	return arm


func test_modify_assembly_strips_a_sub_part_off_a_dropped_assembly() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var arm := _make_dropped_arm()
	grid.field_items[Vector2i(0, 0)] = [arm]
	var state := CombatState.new(grid, [unit])

	var action := ModifyAssemblyAction.new(unit, Vector2i(0, 0), &"arm", &"pistol", 2)
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_eq(PartGraph.walk(arm).size(), 1, "the pistol must be gone from the arm's assembly")
	var items: Array = grid.field_items[Vector2i(0, 0)]
	var stripped_pistol_found := false
	for item: Variant in items:
		if item is Part and item.id == &"pistol":
			stripped_pistol_found = true
	assert_true(stripped_pistol_found, "the stripped pistol must land as its own field item")
	assert_eq(unit.ap, unit.max_ap - 2)


func test_modify_assembly_emits_a_strip_part_event() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var arm := _make_dropped_arm()
	grid.field_items[Vector2i(0, 0)] = [arm]
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	ModifyAssemblyAction.new(unit, Vector2i(0, 0), &"arm", &"pistol", 2).apply(state)

	var strips: Array[LogEvent] = sink.events_of_kind(&"strip_part")
	assert_eq(strips.size(), 1)
	assert_eq(strips[0].unit_id, unit.id)
	assert_eq(strips[0].data.get("assembly"), &"arm")
	assert_eq(strips[0].data.get("stripped"), &"pistol")


func test_modify_assembly_illegal_for_a_part_not_in_the_assembly() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var arm := _make_dropped_arm()
	grid.field_items[Vector2i(0, 0)] = [arm]
	var state := CombatState.new(grid, [unit])

	assert_false(
		ModifyAssemblyAction.new(unit, Vector2i(0, 0), &"arm", &"nonexistent", 2).is_legal(state)
	)


func test_modify_assembly_illegal_targeting_the_assembly_root_itself() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var arm := _make_dropped_arm()
	grid.field_items[Vector2i(0, 0)] = [arm]
	var state := CombatState.new(grid, [unit])

	assert_false(ModifyAssemblyAction.new(unit, Vector2i(0, 0), &"arm", &"arm", 2).is_legal(state))
