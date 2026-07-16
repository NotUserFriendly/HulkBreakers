extends GutTest

## docs/01 taskblock02 Pass B: BodyAssembler turns a ShellTemplate
## (structure) + Loadout (discretionary fill) + a named pool into a Unit.
## The reference humanoid's own structural correctness is covered
## end-to-end by test_reference_humanoid.gd — these tests exercise the
## assembler's own contract in isolation with small, purpose-built
## fixtures (CLAUDE.md: "if a test needs a concrete list, the test authors
## it as a fixture").


func _leaf_part(id: StringName, attaches_to: Array[StringName]) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = attaches_to
	p.hp = 1
	p.max_hp = 1
	return p


func _hosting_part(
	id: StringName, sockets: Array[Socket], attaches_to: Array[StringName] = []
) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = attaches_to
	p.sockets = sockets
	p.hp = 1
	p.max_hp = 1
	return p


func _matrix_socket() -> Socket:
	return Socket.new(&"MATRIX", Transform3D.IDENTITY, &"MATRIX")


func test_assemble_docks_the_matrix_and_carries_the_templates_budget() -> void:
	var root := _hosting_part(&"root", [_matrix_socket()])
	var pool := {&"root": root}
	var template := ShellTemplate.new(&"root", [], 10.0, 20.0)
	var matrix := Matrix.new()

	var unit: Unit = BodyAssembler.assemble(template, null, pool, matrix, Vector2i(0, 0))

	assert_not_null(unit)
	assert_eq(unit.shell.root.hosted_matrix, matrix)
	assert_eq(unit.shell.max_mass, 10.0)
	assert_eq(unit.shell.max_ram, 20.0)


func test_mount_attachment_is_order_independent() -> void:
	# Rear declared FIRST, front SECOND — the exact landmine B0 exists to
	# kill: a Mount targets a socket by id, never "whichever is free first".
	var torso := _hosting_part(
		&"torso",
		[
			Socket.new(&"ARMOR", Transform3D.IDENTITY, &"ARMOR_REAR"),
			Socket.new(&"ARMOR", Transform3D.IDENTITY, &"ARMOR_FRONT"),
			_matrix_socket(),
		]
	)
	var front_plate := _leaf_part(&"front_plate", [&"ARMOR"])
	var rear_plate := _leaf_part(&"rear_plate", [&"ARMOR"])
	var pool := {&"torso": torso, &"front_plate": front_plate, &"rear_plate": rear_plate}
	var template := ShellTemplate.new(
		&"torso",
		[Mount.new(&"ARMOR_FRONT", &"front_plate"), Mount.new(&"ARMOR_REAR", &"rear_plate")],
		10.0,
		10.0
	)

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	var front_socket: Socket = PartGraph.find_socket(unit.shell.root, &"ARMOR_FRONT")
	var rear_socket: Socket = PartGraph.find_socket(unit.shell.root, &"ARMOR_REAR")
	assert_eq(front_socket.occupant.id, &"front_plate")
	assert_eq(rear_socket.occupant.id, &"rear_plate")


func test_a_template_with_12_shoulder_mounts_assembles_12_arms_at_12_transforms() -> void:
	const SOCKET_COUNT := 12
	var sockets: Array[Socket] = [_matrix_socket()]
	var mounts: Array[Mount] = []
	for i in range(SOCKET_COUNT):
		var socket_id := StringName("SHOULDER_%d" % i)
		var x: float = float(i) * 0.5
		sockets.append(
			Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(x, 0.0, 0.0)), socket_id)
		)
		mounts.append(Mount.new(socket_id, &"arm"))
	var torso := _hosting_part(&"torso", sockets)
	var arm := _leaf_part(&"arm", [&"SHOULDER"])
	var pool := {&"torso": torso, &"arm": arm}
	var template := ShellTemplate.new(&"torso", mounts, 100.0, 100.0)

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	assert_eq(unit.shell.all_parts().size(), SOCKET_COUNT + 1)  # torso + 12 arms
	var transforms_seen: Array[Vector3] = []
	for i in range(SOCKET_COUNT):
		var socket: Socket = PartGraph.find_socket(unit.shell.root, StringName("SHOULDER_%d" % i))
		assert_not_null(socket.occupant, "socket %d must be filled" % i)
		assert_eq(socket.occupant.id, &"arm")
		assert_does_not_have(transforms_seen, socket.transform.origin)
		transforms_seen.append(socket.transform.origin)


func test_two_loadouts_on_one_template_produce_two_armaments_one_skeleton() -> void:
	var torso := _hosting_part(
		&"torso", [Socket.new(&"WRIST", Transform3D.IDENTITY, &"WRIST"), _matrix_socket()]
	)
	var hand := _hosting_part(
		&"hand", [Socket.new(&"GRIP", Transform3D.IDENTITY, &"GRIP")], [&"WRIST"]
	)
	var pistol := _leaf_part(&"pistol", [&"GRIP"])
	var rifle := _leaf_part(&"rifle", [&"GRIP"])
	var pool := {&"torso": torso, &"hand": hand, &"pistol": pistol, &"rifle": rifle}
	var template := ShellTemplate.new(&"torso", [Mount.new(&"WRIST", &"hand")], 10.0, 10.0)

	var pistol_unit: Unit = BodyAssembler.assemble(
		template, Loadout.new({&"GRIP": &"pistol"}), pool, Matrix.new(), Vector2i(0, 0)
	)
	var rifle_unit: Unit = BodyAssembler.assemble(
		template, Loadout.new({&"GRIP": &"rifle"}), pool, Matrix.new(), Vector2i(1, 0)
	)

	var pistol_hand: Part = pistol_unit.shell.find_part(&"hand")
	var rifle_hand: Part = rifle_unit.shell.find_part(&"hand")
	assert_not_null(pistol_hand, "same skeleton: both units grew a hand")
	assert_not_null(rifle_hand, "same skeleton: both units grew a hand")
	assert_eq(PartGraph.find_socket(pistol_hand, &"GRIP").occupant.id, &"pistol")
	assert_eq(PartGraph.find_socket(rifle_hand, &"GRIP").occupant.id, &"rifle")


func test_loadout_wins_over_a_mounts_own_default_part() -> void:
	var torso := _hosting_part(
		&"torso", [Socket.new(&"GRIP", Transform3D.IDENTITY, &"GRIP"), _matrix_socket()]
	)
	var pistol := _leaf_part(&"pistol", [&"GRIP"])
	var rifle := _leaf_part(&"rifle", [&"GRIP"])
	var pool := {&"torso": torso, &"pistol": pistol, &"rifle": rifle}
	var template := ShellTemplate.new(&"torso", [Mount.new(&"GRIP", &"pistol")], 10.0, 10.0)

	var unit: Unit = BodyAssembler.assemble(
		template, Loadout.new({&"GRIP": &"rifle"}), pool, Matrix.new(), Vector2i(0, 0)
	)

	assert_eq(PartGraph.find_socket(unit.shell.root, &"GRIP").occupant.id, &"rifle")


func test_unknown_root_pool_id_errors_by_name_and_fails_the_whole_assembly() -> void:
	var template := ShellTemplate.new(&"nonexistent_root", [], 10.0, 10.0)

	var unit: Unit = BodyAssembler.assemble(template, null, {}, Matrix.new(), Vector2i(0, 0))

	assert_null(unit)
	assert_push_error("nonexistent_root")


func test_unknown_mount_pool_id_errors_by_name_and_fails_the_whole_assembly() -> void:
	var torso := _hosting_part(
		&"torso", [Socket.new(&"ARMOR", Transform3D.IDENTITY, &"ARMOR"), _matrix_socket()]
	)
	var pool := {&"torso": torso}
	var template := ShellTemplate.new(
		&"torso", [Mount.new(&"ARMOR", &"nonexistent_plate")], 10.0, 10.0
	)

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	assert_null(unit)
	assert_push_error("nonexistent_plate")


func test_unknown_mount_socket_id_errors_by_name_and_fails_the_whole_assembly() -> void:
	var torso := _hosting_part(&"torso", [_matrix_socket()])
	var plate := _leaf_part(&"plate", [&"ARMOR"])
	var pool := {&"torso": torso, &"plate": plate}
	var template := ShellTemplate.new(&"torso", [Mount.new(&"ARMOR_FRONT", &"plate")], 10.0, 10.0)

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	assert_null(unit)
	assert_push_error("ARMOR_FRONT")


func test_illegal_attachment_errors_by_name_and_fails_the_whole_assembly() -> void:
	var torso := _hosting_part(
		&"torso", [Socket.new(&"HIP", Transform3D.IDENTITY, &"HIP"), _matrix_socket()]
	)
	# Wrong attaches_to on purpose: a SHOULDER-only part mounted at a HIP socket.
	var arm := _leaf_part(&"arm", [&"SHOULDER"])
	var pool := {&"torso": torso, &"arm": arm}
	var template := ShellTemplate.new(&"torso", [Mount.new(&"HIP", &"arm")], 10.0, 10.0)

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	assert_null(unit)
	assert_push_error("cannot attach")


func test_root_part_that_cannot_host_a_matrix_errors_and_fails_the_whole_assembly() -> void:
	var root := _hosting_part(&"root", [])  # no MATRIX socket
	var pool := {&"root": root}
	var template := ShellTemplate.new(&"root", [], 10.0, 10.0)

	var unit: Unit = BodyAssembler.assemble(template, null, pool, Matrix.new(), Vector2i(0, 0))

	assert_null(unit)
	assert_push_error("cannot host a matrix")
