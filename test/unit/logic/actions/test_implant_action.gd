extends GutTest


func _make_carrier(cell: Vector2i, held: MatrixCore = null) -> Unit:
	var chassis := Chassis.new()
	var core := Part.new()
	core.slot_type = Enums.SlotType.CORE
	core.hp = 5
	core.max_hp = 5
	chassis.install(core)
	var unit := Unit.new(Matrix.new(), chassis, cell, 0)
	unit.held_core = held
	return unit


func _spare_chassis() -> Chassis:
	var chassis := Chassis.new()
	var core := Part.new()
	core.slot_type = Enums.SlotType.CORE
	core.hp = 5
	core.max_hp = 5
	chassis.install(core)
	return chassis


func test_implant_spawns_new_unit_and_consumes_core() -> void:
	var grid := Grid.new(5, 5)
	var new_matrix := Matrix.new()
	new_matrix.id = &"rescued_matrix"
	var held := MatrixCore.new()
	held.matrix = new_matrix

	var carrier := _make_carrier(Vector2i(0, 0), held)
	var state := CombatState.new(grid, [carrier])
	var spare := _spare_chassis()

	var action := ImplantAction.new(carrier, spare, Vector2i(1, 0))
	assert_true(action.is_legal(state))
	assert_true(state.try_apply(action))

	assert_null(carrier.held_core)
	assert_eq(carrier.ap, carrier.max_ap - ImplantAction.AP_COST)
	assert_eq(state.units.size(), 2)

	var spawned: Unit = state.units[1]
	assert_eq(spawned.matrix, new_matrix)
	assert_eq(spawned.chassis, spare)
	assert_eq(spawned.cell, Vector2i(1, 0))
	assert_eq(spawned.squad_id, carrier.squad_id)
	assert_eq(grid.get_occupant_id(Vector2i(1, 0)), spawned.id)


func test_implant_rejects_without_held_core() -> void:
	var grid := Grid.new(5, 5)
	var carrier := _make_carrier(Vector2i(0, 0), null)
	var state := CombatState.new(grid, [carrier])
	var action := ImplantAction.new(carrier, _spare_chassis(), Vector2i(1, 0))
	assert_false(action.is_legal(state))


func test_implant_rejects_occupied_target_cell() -> void:
	var grid := Grid.new(5, 5)
	var held := MatrixCore.new()
	held.matrix = Matrix.new()
	var carrier := _make_carrier(Vector2i(0, 0), held)
	var blocker := _make_carrier(Vector2i(1, 0))
	blocker.squad_id = 1
	var state := CombatState.new(grid, [carrier, blocker])

	var action := ImplantAction.new(carrier, _spare_chassis(), Vector2i(1, 0))
	assert_false(action.is_legal(state))


func test_implant_rejects_too_far_target_cell() -> void:
	var grid := Grid.new(10, 10)
	var held := MatrixCore.new()
	held.matrix = Matrix.new()
	var carrier := _make_carrier(Vector2i(0, 0), held)
	var state := CombatState.new(grid, [carrier])

	var action := ImplantAction.new(carrier, _spare_chassis(), Vector2i(5, 5))
	assert_false(action.is_legal(state))
