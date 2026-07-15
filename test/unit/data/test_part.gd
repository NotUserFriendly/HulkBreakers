extends GutTest


func test_new_part_has_sane_defaults() -> void:
	var part := Part.new()
	assert_eq(part.attaches_to, [] as Array[StringName])
	assert_eq(part.sockets, [] as Array[Socket])
	assert_eq(part.capabilities, [] as Array[StringName])
	assert_eq(part.requires, {})
	assert_eq(part.hp, 1)
	assert_eq(part.max_hp, 1)
	assert_false(part.is_container)
	assert_true(part.is_destructible)
	assert_null(part.hosted_matrix)


func test_save_load_round_trips_a_full_socket_tree() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.material = &"steel"
	torso.volume = [Box.new(Vector3.ZERO, Vector3(1, 2, 1))]
	torso.tags = [&"ORGANIC"]
	var shoulder_socket := Socket.new(&"SHOULDER")
	torso.sockets = [shoulder_socket]

	var arm := Part.new()
	arm.id = &"arm"
	arm.attaches_to = [&"SHOULDER"]
	arm.hp = 6
	arm.max_hp = 6
	shoulder_socket.occupant = arm

	var grip_socket := Socket.new(&"GRIP")
	arm.sockets = [grip_socket]
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.attaches_to = [&"GRIP"]
	pistol.capabilities = []
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 8.0
	pistol.burst = 1
	pistol.recoil = 2.0
	pistol.weapon_max_range = 12.0
	pistol.ap_cost = 1
	pistol.crit_chance = 0.1
	pistol.scatter = [Ring.new(0.1, 1.0), Ring.new(0.5, 2.0)]
	grip_socket.occupant = pistol

	var path := "user://tmp_test_part_tree.tres"
	assert_eq(ResourceSaver.save(torso, path), OK)
	var loaded: Part = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	assert_eq(loaded.id, &"torso")
	assert_eq(loaded.material, &"steel")
	assert_eq(loaded.volume.size(), 1)
	assert_eq(loaded.volume[0].size, Vector3(1, 2, 1))
	assert_eq(loaded.tags, [&"ORGANIC"])

	assert_eq(loaded.sockets.size(), 1)
	var loaded_arm: Part = loaded.sockets[0].occupant
	assert_eq(loaded_arm.id, &"arm")
	assert_eq(loaded_arm.attaches_to, [&"SHOULDER"])

	var loaded_pistol: Part = loaded_arm.sockets[0].occupant
	assert_eq(loaded_pistol.id, &"pistol")
	assert_eq(loaded_pistol.requires, {&"TRIGGER": 1})
	assert_eq(loaded_pistol.damage, 8.0)
	assert_eq(loaded_pistol.burst, 1)
	assert_eq(loaded_pistol.recoil, 2.0)
	assert_eq(loaded_pistol.weapon_max_range, 12.0)
	assert_eq(loaded_pistol.ap_cost, 1)
	assert_eq(loaded_pistol.crit_chance, 0.1)
	assert_eq(loaded_pistol.scatter.size(), 2)
	assert_eq(loaded_pistol.scatter[0].radius, 0.1)
	assert_eq(loaded_pistol.scatter[1].weight, 2.0)


## docs/01: a matrix docks only into a part that declares a MATRIX socket —
## never a free-standing flag any part can claim.
func test_hosts_matrix_is_false_without_a_matrix_socket() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.sockets = [Socket.new(&"WRIST")]
	assert_false(arm.hosts_matrix())


func test_hosts_matrix_is_true_with_a_matrix_socket() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.sockets = [Socket.new(&"MATRIX")]
	assert_true(torso.hosts_matrix())


func test_dock_matrix_fails_on_a_part_with_no_matrix_socket() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.sockets = [Socket.new(&"WRIST")]
	var matrix := Matrix.new()
	assert_false(arm.dock_matrix(matrix), "an arm can never host a matrix")
	assert_null(arm.hosted_matrix)


func test_dock_matrix_succeeds_on_a_part_with_a_free_matrix_socket() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.sockets = [Socket.new(&"MATRIX")]
	var matrix := Matrix.new()
	assert_true(torso.dock_matrix(matrix))
	assert_eq(torso.hosted_matrix, matrix)


func test_dock_matrix_fails_when_already_hosting() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.sockets = [Socket.new(&"MATRIX")]
	assert_true(torso.dock_matrix(Matrix.new()))
	assert_false(torso.dock_matrix(Matrix.new()), "a MATRIX socket can only ever hold one matrix")
