extends GutTest


func _make_carrier(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var back := Socket.new(&"BACK")
	torso.sockets = [back]
	var shell := Shell.new(torso)
	shell.max_mass = 1000.0
	return Unit.new(Matrix.new(), shell, cell, 0)


func _make_body() -> Part:
	var body := Part.new()
	body.id = &"downed_ally"
	body.hp = 3
	body.max_hp = 10
	body.attaches_to = [&"BACK"]  # cargo shaped for a BACK socket, same as a backpack
	body.mass = 40.0
	# Slung across the back: local z negative, same rearward convention as
	# the ammo racks elsewhere (docs/02) — behind the torso from the front,
	# frontmost from behind.
	body.volume = [Box.new(Vector3(0.0, 0.5, -0.3), Vector3(1.8, 1.0, 0.4))]
	return body


func test_carry_body_attaches_to_back_and_tags_inert() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var body := _make_body()
	grid.field_items[Vector2i(0, 0)] = [body]
	var state := CombatState.new(grid, [carrier])

	var action := CarryBodyAction.new(carrier, Vector2i(0, 0), &"downed_ally")
	assert_true(action.is_legal(state))
	action.apply(state)

	assert_true(
		carrier.shell.all_parts().has(body), "the body must now be part of the carrier's assembly"
	)
	assert_true(&"INERT" in body.tags)
	assert_false(grid.field_items.has(Vector2i(0, 0)))


func test_carry_body_emits_a_carry_body_event() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var body := _make_body()
	grid.field_items[Vector2i(0, 0)] = [body]
	var state := CombatState.new(grid, [carrier])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	CarryBodyAction.new(carrier, Vector2i(0, 0), &"downed_ally").apply(state)

	var carries: Array[LogEvent] = sink.events_of_kind(&"carry_body")
	assert_eq(carries.size(), 1)
	assert_eq(carries[0].unit_id, carrier.id)
	assert_eq(carries[0].data.get("body"), &"downed_ally")


func test_carry_body_occupies_back_so_a_second_body_has_nowhere_to_go() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var body_a := _make_body()
	body_a.id = &"body_a"
	grid.field_items[Vector2i(0, 0)] = [body_a]
	var state := CombatState.new(grid, [carrier])
	CarryBodyAction.new(carrier, Vector2i(0, 0), &"body_a").apply(state)

	var body_b := _make_body()
	body_b.id = &"body_b"
	state.grid.field_items[Vector2i(0, 0)] = [body_b]
	assert_false(CarryBodyAction.new(carrier, Vector2i(0, 0), &"body_b").is_legal(state))


## docs/05 taskblock04 D3: "BACK holds a barrel or a crewmate, never both...
## loot capacity and rescue are mutually exclusive. This is intended." No
## new mechanic — the same free-socket check that already stops a second
## body (test above) stops a body once a container already occupies BACK.
func test_a_worn_trash_barrel_leaves_no_room_to_carry_a_body() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var barrel: Part = Containers.trash_barrel()
	assert_true(PartGraph.attach(barrel, carrier.shell.root, carrier.shell.root.sockets[0]))

	var grid := Grid.new(5, 5)
	var body := _make_body()
	grid.field_items[Vector2i(0, 0)] = [body]
	var state := CombatState.new(grid, [carrier])

	assert_false(
		CarryBodyAction.new(carrier, Vector2i(0, 0), &"downed_ally").is_legal(state),
		"a worn barrel already occupies the only BACK socket"
	)


func test_carry_body_illegal_for_something_not_shaped_for_a_back_socket() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 5
	crate.max_hp = 5
	crate.attaches_to = [&"CARGO"]  # not BACK-shaped
	grid.field_items[Vector2i(0, 0)] = [crate]
	var state := CombatState.new(grid, [carrier])

	assert_false(
		CarryBodyAction.new(carrier, Vector2i(0, 0), &"crate").is_legal(state),
		"an item not shaped for BACK must be rejected, not silently dropped from the ground"
	)


func test_carry_body_illegal_without_a_body_present() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid, [carrier])
	assert_false(CarryBodyAction.new(carrier, Vector2i(0, 0), &"nothing_here").is_legal(state))


func test_carried_body_contributes_volume_to_the_carriers_projection() -> void:
	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(5, 5)
	var body := _make_body()
	grid.field_items[Vector2i(0, 0)] = [body]
	var state := CombatState.new(grid, [carrier])
	CarryBodyAction.new(carrier, Vector2i(0, 0), &"downed_ally").apply(state)

	var regions: Array[Region] = BodyProjector.project(carrier, Vector3(0, 0.0, -1))
	var body_region_found := false
	for region: Region in regions:
		if region.part == body:
			body_region_found = true
	assert_true(body_region_found, "no new mechanism needed — the socket graph already projects it")


func _make_shooter(cell: Vector2i, weapon: Part) -> Unit:
	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 5
	hand.max_hp = 5
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


## docs/05's core claim: a body carried on the BACK eats rounds aimed at the
## carrier's back, purely because the socket graph now includes its volume
## in the projection — no dedicated "bullet catcher" mechanic.
func test_a_shot_from_behind_hits_the_carried_body_instead_of_the_carrier() -> void:
	var weapon := Part.new()
	weapon.id = &"pistol"
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 20.0
	weapon.ap_cost = 1
	weapon.burst = 1
	weapon.scatter = [Ring.new(0.05, 1.0)]

	var carrier := _make_carrier(Vector2i(0, 0))
	var grid := Grid.new(20, 20)
	var body := _make_body()
	grid.field_items[Vector2i(0, 0)] = [body]
	var state := CombatState.new(grid, [carrier])
	CarryBodyAction.new(carrier, Vector2i(0, 0), &"downed_ally").apply(state)

	# Shooter at smaller Y firing +Y hits the carrier's back (same
	# front-faces-+Y convention used throughout docs/02/03).
	var shooter := _make_shooter(Vector2i(0, -5), weapon)
	state.add_unit(shooter)

	AttackAction.new(shooter, &"pistol", Vector2i(0, 0)).apply(state)

	assert_lt(body.hp, 3, "the carried body must take the hit aimed at the carrier's back")
