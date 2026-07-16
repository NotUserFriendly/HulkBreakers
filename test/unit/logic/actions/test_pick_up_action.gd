extends GutTest


func _make_unit(cell: Vector2i) -> Unit:
	var bag := Part.new()
	bag.id = &"bag"
	bag.hp = 5
	bag.max_hp = 5
	bag.is_container = true
	bag.max_bulk = 10.0

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var socket := Socket.new(&"BACK")
	socket.occupant = bag
	torso.sockets = [socket]

	var shell := Shell.new(torso)
	shell.max_mass = 1000.0
	return Unit.new(Matrix.new(), shell, cell, 0)


func test_pick_up_matrix_goes_to_held_matrix() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var matrix := Matrix.new()
	matrix.id = &"loose_matrix"
	grid.field_items[Vector2i(0, 0)] = [matrix]
	var state := CombatState.new(grid, [unit])

	var action := PickUpAction.new(unit, Vector2i(0, 0), &"loose_matrix")
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_eq(unit.held_matrix, matrix)
	assert_false(grid.field_items.has(Vector2i(0, 0)))


func test_pick_up_emits_a_pick_up_event() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var matrix := Matrix.new()
	matrix.id = &"loose_matrix"
	grid.field_items[Vector2i(0, 0)] = [matrix]
	var state := CombatState.new(grid, [unit])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	PickUpAction.new(unit, Vector2i(0, 0), &"loose_matrix").apply(state)

	var pick_ups: Array[LogEvent] = sink.events_of_kind(&"pick_up")
	assert_eq(pick_ups.size(), 1)
	assert_eq(pick_ups[0].unit_id, unit.id)
	assert_eq(pick_ups[0].data.get("item"), &"loose_matrix")
	assert_true(pick_ups[0].data.get("is_matrix"))


func test_pick_up_matrix_illegal_when_already_carrying_one() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	unit.held_matrix = Matrix.new()
	var grid := Grid.new(5, 5)
	var matrix := Matrix.new()
	matrix.id = &"loose_matrix"
	grid.field_items[Vector2i(0, 0)] = [matrix]
	var state := CombatState.new(grid, [unit])

	assert_false(PickUpAction.new(unit, Vector2i(0, 0), &"loose_matrix").is_legal(state))


func test_pick_up_part_attaches_into_the_named_container() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 5
	pistol.max_hp = 5
	pistol.bulk = 1.0
	grid.field_items[Vector2i(0, 0)] = [pistol]
	var state := CombatState.new(grid, [unit])

	var action := PickUpAction.new(unit, Vector2i(0, 0), &"pistol", &"bag")
	assert_true(action.is_legal(state))
	action.apply(state)

	var bag: Part = unit.shell.find_part(&"bag")
	assert_true(bag.contents.has(pistol))
	assert_false(grid.field_items.has(Vector2i(0, 0)))


func test_pick_up_part_illegal_without_room_in_the_container() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	unit.shell.find_part(&"bag").max_bulk = 0.5
	var grid := Grid.new(5, 5)
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 5
	pistol.max_hp = 5
	pistol.bulk = 1.0
	grid.field_items[Vector2i(0, 0)] = [pistol]
	var state := CombatState.new(grid, [unit])

	assert_false(PickUpAction.new(unit, Vector2i(0, 0), &"pistol", &"bag").is_legal(state))


## docs/05 taskblock04 D3: "PickUpAction with no container is illegal...
## no container, no looting." A unit with nothing worn to carry a Part in
## (never a Matrix — that path doesn't need one) simply can't pick one up.
func test_pick_up_part_illegal_with_no_container_worn_at_all() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shell := Shell.new(torso)
	shell.max_mass = 1000.0
	var unit := Unit.new(Matrix.new(), shell, Vector2i(0, 0), 0)

	var grid := Grid.new(5, 5)
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 5
	pistol.max_hp = 5
	pistol.bulk = 1.0
	grid.field_items[Vector2i(0, 0)] = [pistol]
	var state := CombatState.new(grid, [unit])

	assert_false(
		PickUpAction.new(unit, Vector2i(0, 0), &"pistol", &"bag").is_legal(state),
		"no container named 'bag' exists on this shell at all"
	)


func test_pick_up_illegal_off_the_units_own_cell() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var matrix := Matrix.new()
	matrix.id = &"loose_matrix"
	grid.field_items[Vector2i(1, 1)] = [matrix]
	var state := CombatState.new(grid, [unit])

	assert_false(PickUpAction.new(unit, Vector2i(1, 1), &"loose_matrix").is_legal(state))
