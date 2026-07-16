extends GutTest

## runNotes.md: "a list of weapons the unit has attached. Gray out
## 'inactive' weapons, with a 'why' attached." WeaponRows.build() is the
## whole data source — active/why must be provable headlessly, same split
## as InventoryRows/InventoryRow.


func _make_unit(root: Part) -> Unit:
	return Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)


func _pistol() -> Part:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 4.0
	return pistol


func _hand_with_pistol() -> Part:
	var pistol: Part = _pistol()
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]
	return hand


func test_a_shell_with_no_weapons_builds_no_rows() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var unit := _make_unit(torso)

	assert_eq(WeaponRows.build(unit).size(), 0)


func test_an_operable_weapon_is_active_with_no_reason() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = _hand_with_pistol()
	torso.sockets = [hand_socket]
	var unit := _make_unit(torso)

	var rows: Array[WeaponRow] = WeaponRows.build(unit)

	assert_eq(rows.size(), 1)
	assert_eq(rows[0].part.id, &"pistol")
	assert_true(rows[0].active)
	assert_eq(rows[0].why, "")


func test_a_weapon_with_no_capable_manipulator_is_inactive_with_a_reason() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var grip := Socket.new(&"GRIP")
	grip.occupant = _pistol()  # no TRIGGER-capable hand anywhere in the shell
	torso.sockets = [grip]
	var unit := _make_unit(torso)

	var rows: Array[WeaponRow] = WeaponRows.build(unit)

	assert_eq(rows.size(), 1)
	assert_false(rows[0].active)
	assert_true(rows[0].why.contains("TRIGGER"))


func test_a_destroyed_weapon_is_inactive_and_says_destroyed() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand: Part = _hand_with_pistol()
	var pistol: Part = (hand.sockets[0] as Socket).occupant
	pistol.hp = 0
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	var unit := _make_unit(torso)

	var rows: Array[WeaponRow] = WeaponRows.build(unit)

	assert_eq(rows.size(), 1, "a destroyed weapon still belongs on the list, not silently gone")
	assert_false(rows[0].active)
	assert_eq(rows[0].why, "destroyed")


## docs/01: a two-handed weapon needs two DISTINCT manipulators, one per
## required capability slot — a single hand with both capabilities still
## can't operate it alone (PartGraph.can_operate's own bipartite matching).
func test_a_two_handed_weapon_with_only_one_manipulator_is_inactive() -> void:
	var rifle := Part.new()
	rifle.id = &"rifle"
	rifle.hp = 3
	rifle.max_hp = 3
	rifle.attaches_to = [&"GRIP"]
	rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}
	rifle.damage = 8.0

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER", &"SUPPORT"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = rifle
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	var unit := _make_unit(torso)

	var rows: Array[WeaponRow] = WeaponRows.build(unit)

	assert_eq(rows.size(), 1)
	assert_false(rows[0].active, "one hand can't fill two distinct capability slots alone")


func test_dual_wielded_operable_pistols_are_both_active() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var left := Socket.new(&"HAND_L")
	left.occupant = _hand_with_pistol()
	var right := Socket.new(&"HAND_R")
	right.occupant = _hand_with_pistol()
	torso.sockets = [left, right]
	var unit := _make_unit(torso)

	var rows: Array[WeaponRow] = WeaponRows.build(unit)

	assert_eq(rows.size(), 2)
	assert_true(rows[0].active)
	assert_true(rows[1].active)


func test_a_carried_but_unattached_weapon_is_not_listed() -> void:
	var backpack := Part.new()
	backpack.id = &"backpack"
	backpack.hp = 5
	backpack.max_hp = 5
	backpack.is_container = true
	backpack.contents = [_pistol()]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var back_socket := Socket.new(&"BACK")
	back_socket.occupant = backpack
	torso.sockets = [back_socket]
	var unit := _make_unit(torso)

	assert_eq(WeaponRows.build(unit).size(), 0, "only attached weapons belong on this list")
