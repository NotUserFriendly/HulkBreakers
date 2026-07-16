extends GutTest

## docs/10 taskblock03 H1: InventoryRows.build() is the panel's whole data
## source — a plain GUT test can prove "sockets and contents never get
## flattened together" without ever touching the Tree control itself.


func _make_unit(root: Part) -> Unit:
	return Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)


func test_the_root_part_is_row_zero_at_depth_zero() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var unit := _make_unit(torso)

	var rows: Array[InventoryRow] = InventoryRows.build(unit, MaterialTable.default_table())

	assert_eq(rows.size(), 1)
	assert_eq(rows[0].part, torso)
	assert_eq(rows[0].depth, 0)
	assert_eq(rows[0].kind, InventoryRow.Kind.SOCKET)


func test_a_socketed_child_shows_the_sockets_own_id() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER", Transform3D.IDENTITY, &"SHOULDER_L")
	shoulder.occupant = arm
	torso.sockets = [shoulder]
	var unit := _make_unit(torso)

	var rows: Array[InventoryRow] = InventoryRows.build(unit, MaterialTable.default_table())

	assert_eq(rows.size(), 2)
	assert_eq(rows[1].part, arm)
	assert_eq(rows[1].depth, 1)
	assert_eq(rows[1].kind, InventoryRow.Kind.SOCKET)
	assert_eq(rows[1].socket_label, &"SHOULDER_L")


func test_a_socket_with_no_authored_id_falls_back_to_its_socket_type() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 4
	arm.max_hp = 4

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER")  # id left at its "" default
	shoulder.occupant = arm
	torso.sockets = [shoulder]
	var unit := _make_unit(torso)

	var rows: Array[InventoryRow] = InventoryRows.build(unit, MaterialTable.default_table())

	assert_eq(rows[1].socket_label, &"SHOULDER")


## docs/10 taskblock03 H1: "sockets (structural) and contents (inventory)
## are different relationships" — a backpack is attached AND contains
## items, and both must show as what they are, never merged into one kind.
func test_a_backpack_is_both_socketed_and_shows_its_contents_distinctly() -> void:
	var ammo := Part.new()
	ammo.id = &"ammo"
	ammo.hp = 1
	ammo.max_hp = 1

	var backpack := Part.new()
	backpack.id = &"backpack"
	backpack.hp = 5
	backpack.max_hp = 5
	backpack.is_container = true
	backpack.max_bulk = 10.0
	backpack.contents = [ammo]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var back := Socket.new(&"BACK", Transform3D.IDENTITY, &"BACK")
	back.occupant = backpack
	torso.sockets = [back]
	var unit := _make_unit(torso)

	var rows: Array[InventoryRow] = InventoryRows.build(unit, MaterialTable.default_table())

	assert_eq(rows.size(), 3)
	assert_eq(rows[1].part, backpack)
	assert_eq(rows[1].kind, InventoryRow.Kind.SOCKET, "the backpack itself is attached")
	assert_eq(rows[1].socket_label, &"BACK")
	assert_eq(rows[2].part, ammo)
	assert_eq(rows[2].kind, InventoryRow.Kind.CONTENTS, "ammo is carried, not socketed")
	assert_eq(rows[2].depth, 2, "one level deeper than the backpack that carries it")


func test_a_destroyed_part_and_its_whole_subtree_are_omitted() -> void:
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 0  # destroyed
	arm.max_hp = 4
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	arm.sockets = [wrist]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets = [shoulder]
	var unit := _make_unit(torso)

	var rows: Array[InventoryRow] = InventoryRows.build(unit, MaterialTable.default_table())

	assert_eq(rows.size(), 1, "the destroyed arm and the hand beneath it must both be gone")
	assert_eq(rows[0].part, torso)


func test_dt_is_resolved_from_the_material_table() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.material = &"steel"
	var unit := _make_unit(torso)
	var table := MaterialTable.default_table()

	var rows: Array[InventoryRow] = InventoryRows.build(unit, table)

	assert_eq(rows[0].dt, table.get_entry(&"steel").dt)


## docs/04 taskblock02 D3: a part whose body_requires the docked surrogate's
## capabilities don't cover is flagged inert.
func test_a_part_requiring_an_unmet_capability_is_flagged_inert() -> void:
	var gadget := Part.new()
	gadget.id = &"gadget"
	gadget.hp = 1
	gadget.max_hp = 1
	gadget.body_requires = [&"NEVER_GRANTED"]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var socket := Socket.new(&"INTERNAL")
	socket.occupant = gadget
	torso.sockets = [socket]
	var unit := _make_unit(torso)

	var rows: Array[InventoryRow] = InventoryRows.build(unit, MaterialTable.default_table())

	assert_true(rows[1].inert)
	assert_false(rows[0].inert, "the torso itself has no body_requires to fail")
