extends GutTest

## taskblock-21 Pass A4: "strong sort, still tree'd: Weapons -> Inventories/
## containers -> body parts." Reuses InventoryRows.build() for every
## per-item number — this only tests the group partition on top.


func _make_unit(root: Part) -> Unit:
	return Unit.new(Matrix.new(), Shell.new(root), Vector2i(0, 0), 0)


func test_weapons_come_before_containers_before_body_parts() -> void:
	var weapon := Part.new()
	weapon.id = &"weapon"
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.damage = 5.0

	var backpack := Part.new()
	backpack.id = &"backpack"
	backpack.hp = 5
	backpack.max_hp = 5
	backpack.is_container = true
	backpack.max_bulk = 10.0

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	var back := Socket.new(&"BACK")
	back.occupant = backpack
	torso.sockets = [grip, back]
	var unit := _make_unit(torso)

	var rows: Array[InspectRow] = InspectRows.build(unit, DataLibrary.material_table())

	assert_eq(rows.size(), 3)
	assert_eq(rows[0].group, InspectRow.Group.WEAPONS)
	assert_eq(rows[0].row.part, weapon)
	assert_eq(rows[1].group, InspectRow.Group.CONTAINERS)
	assert_eq(rows[1].row.part, backpack)
	assert_eq(rows[2].group, InspectRow.Group.BODY)
	assert_eq(rows[2].row.part, torso)


## A weapon carried INSIDE a container (a spare pistol in a backpack) still
## groups under Weapons, by its own part — never buried under Containers
## just because of where it's stashed.
func test_a_weapon_carried_inside_a_container_still_groups_as_a_weapon() -> void:
	var spare_pistol := Part.new()
	spare_pistol.id = &"spare_pistol"
	spare_pistol.hp = 2
	spare_pistol.max_hp = 2
	spare_pistol.damage = 4.0

	var backpack := Part.new()
	backpack.id = &"backpack"
	backpack.hp = 5
	backpack.max_hp = 5
	backpack.is_container = true
	backpack.max_bulk = 10.0
	backpack.contents = [spare_pistol]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var back := Socket.new(&"BACK")
	back.occupant = backpack
	torso.sockets = [back]
	var unit := _make_unit(torso)

	var rows: Array[InspectRow] = InspectRows.build(unit, DataLibrary.material_table())

	var weapon_group_parts: Array[Part] = []
	for row: InspectRow in rows:
		if row.group == InspectRow.Group.WEAPONS:
			weapon_group_parts.append(row.row.part)
	assert_eq(weapon_group_parts, [spare_pistol])


## Within each group, relative order is exactly InventoryRows' own
## depth-first order — a stable partition, never a re-sort.
func test_order_within_a_group_matches_inventory_rows_own_depth_first_order() -> void:
	var hand_l := Part.new()
	hand_l.id = &"hand_l"
	hand_l.hp = 4
	hand_l.max_hp = 4
	hand_l.damage = 1.0  # unarmed strike still counts as a "weapon" here

	var hand_r := Part.new()
	hand_r.id = &"hand_r"
	hand_r.hp = 4
	hand_r.max_hp = 4
	hand_r.damage = 1.0

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var socket_l := Socket.new(&"HAND_L")
	socket_l.occupant = hand_l
	var socket_r := Socket.new(&"HAND_R")
	socket_r.occupant = hand_r
	torso.sockets = [socket_l, socket_r]
	var unit := _make_unit(torso)

	var rows: Array[InspectRow] = InspectRows.build(unit, DataLibrary.material_table())

	var weapon_parts: Array[Part] = []
	for row: InspectRow in rows:
		if row.group == InspectRow.Group.WEAPONS:
			weapon_parts.append(row.row.part)
	assert_eq(weapon_parts, [hand_l, hand_r], "socket declaration order preserved within the group")
