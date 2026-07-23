extends GutTest


func _make_part(id: StringName, attaches_to: Array[StringName] = []) -> Part:
	var p := Part.new()
	p.id = id
	p.attaches_to = attaches_to
	p.hp = 1
	p.max_hp = 1
	return p


func _add_socket(owner: Part, socket_type: StringName, socket_id: StringName = &"") -> Socket:
	var s := Socket.new(socket_type, Transform3D.IDENTITY, socket_id)
	owner.sockets.append(s)
	return s


func test_torso_with_12_shoulder_sockets_hosts_12_arms() -> void:
	var torso := _make_part(&"torso")
	for i in range(12):
		_add_socket(torso, &"SHOULDER")

	for i in range(12):
		var arm := _make_part(&"arm_%d" % i, [&"SHOULDER"])
		var socket: Socket = PartGraph.find_free_socket(torso, &"SHOULDER")
		assert_not_null(socket, "socket %d should still be free" % i)
		assert_true(PartGraph.attach(arm, torso, socket))

	assert_null(PartGraph.find_free_socket(torso, &"SHOULDER"), "all 12 sockets are full")
	assert_eq(PartGraph.walk(torso).size(), 13)  # torso + 12 arms


func test_part_mounts_on_any_shoulder_any_shell_no_parent_specific_code() -> void:
	# A mech torso and an entirely unrelated hauler shell both expose a
	# SHOULDER socket; the same Gravlance part attaches to either with zero
	# knowledge of what it's mounting on.
	var mech_torso := _make_part(&"mech_torso")
	_add_socket(mech_torso, &"SHOULDER")
	var hauler_frame := _make_part(&"hauler_frame")
	_add_socket(hauler_frame, &"SHOULDER")

	var gravlance_a := _make_part(&"gravlance_a", [&"SHOULDER"])
	var gravlance_b := _make_part(&"gravlance_b", [&"SHOULDER"])

	assert_true(PartGraph.attach(gravlance_a, mech_torso, mech_torso.sockets[0]))
	assert_true(PartGraph.attach(gravlance_b, hauler_frame, hauler_frame.sockets[0]))


func test_deep_tree_sibling_parts_do_not_block_each_other() -> void:
	# TORSO -[SHOULDER]-> shoulder_assembly, which also hosts a SHOULDER_MOUNT
	# rocket pod alongside its UPPER_ARM chain: shoulder -> upper_arm -> forearm
	# -> hand -> pistol, with a forearm sword and an upper-arm plate as further
	# siblings at each level. None of these block each other.
	var torso := _make_part(&"torso")
	_add_socket(torso, &"SHOULDER")

	var shoulder_assembly := _make_part(&"shoulder_assembly", [&"SHOULDER"])
	_add_socket(shoulder_assembly, &"SHOULDER_MOUNT")
	_add_socket(shoulder_assembly, &"UPPER_ARM")
	assert_true(PartGraph.attach(shoulder_assembly, torso, torso.sockets[0]))

	var rocket_pod := _make_part(&"rocket_pod", [&"SHOULDER_MOUNT"])
	assert_true(
		PartGraph.attach(
			rocket_pod,
			shoulder_assembly,
			PartGraph.find_free_socket(shoulder_assembly, &"SHOULDER_MOUNT")
		)
	)

	var upper_arm := _make_part(&"upper_arm", [&"UPPER_ARM"])
	_add_socket(upper_arm, &"ARMOR")
	_add_socket(upper_arm, &"FOREARM")
	assert_true(
		PartGraph.attach(
			upper_arm,
			shoulder_assembly,
			PartGraph.find_free_socket(shoulder_assembly, &"UPPER_ARM")
		)
	)

	var upper_arm_plate := _make_part(&"upper_arm_plate", [&"ARMOR"])
	assert_true(
		PartGraph.attach(
			upper_arm_plate, upper_arm, PartGraph.find_free_socket(upper_arm, &"ARMOR")
		)
	)

	var forearm := _make_part(&"forearm", [&"FOREARM"])
	_add_socket(forearm, &"FOREARM_TOOL")
	_add_socket(forearm, &"ARMOR")
	_add_socket(forearm, &"WRIST")
	assert_true(
		PartGraph.attach(forearm, upper_arm, PartGraph.find_free_socket(upper_arm, &"FOREARM"))
	)

	var folding_sword := _make_part(&"folding_sword", [&"FOREARM_TOOL"])
	assert_true(
		PartGraph.attach(
			folding_sword, forearm, PartGraph.find_free_socket(forearm, &"FOREARM_TOOL")
		)
	)

	var forearm_plate := _make_part(&"forearm_plate", [&"ARMOR"])
	assert_true(
		PartGraph.attach(forearm_plate, forearm, PartGraph.find_free_socket(forearm, &"ARMOR"))
	)

	var hand := _make_part(&"hand", [&"WRIST"])
	_add_socket(hand, &"GRIP")
	assert_true(PartGraph.attach(hand, forearm, PartGraph.find_free_socket(forearm, &"WRIST")))

	var pistol := _make_part(&"pistol", [&"GRIP"])
	assert_true(PartGraph.attach(pistol, hand, PartGraph.find_free_socket(hand, &"GRIP")))

	# The sword blocks nothing: the upper-arm plate, shoulder rocket pod, and
	# the hand's pistol are all simultaneously attached and present.
	var whole_tree: Array[Part] = PartGraph.walk(torso)
	assert_has(whole_tree, rocket_pod)
	assert_has(whole_tree, upper_arm_plate)
	assert_has(whole_tree, folding_sword)
	assert_has(whole_tree, forearm_plate)
	assert_has(whole_tree, pistol)
	# torso, shoulder_assembly, rocket_pod, upper_arm, upper_arm_plate,
	# forearm, folding_sword, forearm_plate, hand, pistol
	assert_eq(whole_tree.size(), 10)


func test_drill_on_wrist_exposes_no_grip_so_pistol_attach_fails() -> void:
	var hand_slot := _make_part(&"forearm")
	_add_socket(hand_slot, &"WRIST")

	var drill := _make_part(&"power_drill", [&"WRIST"])  # takes the hand's socket; no GRIP exposed
	assert_true(PartGraph.attach(drill, hand_slot, hand_slot.sockets[0]))

	# No rule was written to forbid this — it simply has nowhere to attach.
	var pistol := _make_part(&"pistol", [&"GRIP"])
	assert_null(PartGraph.find_free_socket(drill, &"GRIP"))
	assert_eq(drill.sockets.size(), 0)


func test_attach_rejects_type_mismatch() -> void:
	var torso := _make_part(&"torso")
	_add_socket(torso, &"SHOULDER")
	var leg := _make_part(&"leg", [&"HIP"])
	assert_false(PartGraph.attach(leg, torso, torso.sockets[0]))
	assert_null(torso.sockets[0].occupant)


func test_attach_rejects_occupied_socket() -> void:
	var torso := _make_part(&"torso")
	_add_socket(torso, &"SHOULDER")
	var arm_a := _make_part(&"arm_a", [&"SHOULDER"])
	var arm_b := _make_part(&"arm_b", [&"SHOULDER"])
	assert_true(PartGraph.attach(arm_a, torso, torso.sockets[0]))
	assert_false(PartGraph.attach(arm_b, torso, torso.sockets[0]))
	assert_eq(torso.sockets[0].occupant, arm_a)


func test_attach_rejects_cycle() -> void:
	var a := _make_part(&"a", [&"X"])
	_add_socket(a, &"Y")
	var b := _make_part(&"b", [&"Y"])
	_add_socket(b, &"X")

	assert_true(PartGraph.attach(b, a, a.sockets[0]))  # a -> b
	# b already contains a in its subtree via b->a; attaching a into b's socket would cycle.
	assert_false(PartGraph.attach(a, b, b.sockets[0]))


func test_attach_rejects_self_attachment() -> void:
	var a := _make_part(&"a", [&"X"])
	_add_socket(a, &"X")
	assert_false(PartGraph.attach(a, a, a.sockets[0]))


func test_attach_rejects_socket_not_owned_by_target() -> void:
	var owner_a := _make_part(&"owner_a")
	_add_socket(owner_a, &"X")
	var owner_b := _make_part(&"owner_b")
	var part := _make_part(&"part", [&"X"])
	# socket belongs to owner_a, not owner_b
	assert_false(PartGraph.attach(part, owner_b, owner_a.sockets[0]))


func test_destroying_a_part_drops_its_subtree_intact() -> void:
	var torso := _make_part(&"torso")
	_add_socket(torso, &"SHOULDER")
	var arm := _make_part(&"arm", [&"SHOULDER"])
	_add_socket(arm, &"GRIP")
	assert_true(PartGraph.attach(arm, torso, torso.sockets[0]))
	var pistol := _make_part(&"pistol", [&"GRIP"])
	assert_true(PartGraph.attach(pistol, arm, arm.sockets[0]))

	assert_true(PartGraph.drop(torso, arm))

	# The torso's shoulder socket is freed...
	assert_null(torso.sockets[0].occupant)
	assert_does_not_have(PartGraph.walk(torso), arm)
	# ...but the dropped arm is still a fully intact assembly: its own GRIP
	# socket is still populated with the pistol, not scattered as loose bits.
	assert_eq(arm.sockets[0].occupant, pistol)
	assert_eq(PartGraph.walk(arm).size(), 2)


func test_drop_returns_false_when_part_not_in_assembly() -> void:
	var torso := _make_part(&"torso")
	var stray := _make_part(&"stray")
	assert_false(PartGraph.drop(torso, stray))


func test_rifle_usable_by_hand_and_saw_together() -> void:
	var hand := _make_part(&"hand")
	hand.capabilities = [&"TRIGGER", &"SUPPORT", &"GRIP", &"POWER"]
	var saw := _make_part(&"saw_hand")
	saw.capabilities = [&"SUPPORT"]

	var rifle := _make_part(&"rifle")
	rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}

	assert_true(PartGraph.can_operate(rifle, [hand, saw]))


func test_pistol_not_usable_by_saw_alone() -> void:
	var saw := _make_part(&"saw_hand")
	saw.capabilities = [&"SUPPORT"]

	var pistol := _make_part(&"pistol")
	pistol.requires = {&"TRIGGER": 1}

	assert_false(PartGraph.can_operate(pistol, [saw]))


func test_saw_adds_no_power_to_melee_swing() -> void:
	var saw := _make_part(&"saw_hand")
	saw.capabilities = [&"SUPPORT"]

	var two_handed_sword := _make_part(&"sword")
	two_handed_sword.requires = {&"GRIP": 1, &"POWER": 1}

	assert_false(PartGraph.can_operate(two_handed_sword, [saw]))


func test_single_versatile_hand_cannot_alone_satisfy_a_two_slot_weapon() -> void:
	# A hand with every capability still can't fire a two-handed-support
	# weapon alone — physically it needs two limbs, one per role. Plain
	# per-capability summation would incorrectly say yes; proper bipartite
	# matching correctly says no.
	var hand := _make_part(&"hand")
	hand.capabilities = [&"TRIGGER", &"SUPPORT", &"GRIP", &"POWER"]

	var rifle := _make_part(&"rifle")
	rifle.requires = {&"TRIGGER": 1, &"SUPPORT": 1}

	assert_false(PartGraph.can_operate(rifle, [hand]))


func test_part_with_no_requirements_is_always_operable() -> void:
	var armor_plate := _make_part(&"plate")
	assert_true(PartGraph.can_operate(armor_plate, []))


func test_find_socket_returns_the_socket_with_that_id_regardless_of_declaration_order() -> void:
	var torso := _make_part(&"torso")
	_add_socket(torso, &"ARMOR", &"ARMOR_FRONT")
	_add_socket(torso, &"ARMOR", &"ARMOR_REAR")

	assert_eq(PartGraph.find_socket(torso, &"ARMOR_FRONT"), torso.sockets[0])
	assert_eq(PartGraph.find_socket(torso, &"ARMOR_REAR"), torso.sockets[1])

	# The landmine B0 exists to kill: swap the declaration order and the
	# same ids must still resolve to the same logical sockets — nothing may
	# depend on "whichever is first."
	torso.sockets.reverse()
	assert_eq(PartGraph.find_socket(torso, &"ARMOR_FRONT"), torso.sockets[1])
	assert_eq(PartGraph.find_socket(torso, &"ARMOR_REAR"), torso.sockets[0])


func test_find_socket_returns_null_for_an_unknown_id() -> void:
	var torso := _make_part(&"torso")
	_add_socket(torso, &"ARMOR", &"ARMOR_FRONT")
	assert_null(PartGraph.find_socket(torso, &"ARMOR_REAR"))


## BR36.01: `walk` never returns a socket's own `joint_handle()` — the
## synthetic identity `BodyProjector._project_joint` tags a joint Region
## with, never a real member of the socket tree. `walk_with_joints` is the
## one place that gap is closed, one joint per OCCUPIED socket, at every
## depth, on top of every real part `walk` already finds.
func test_walk_with_joints_adds_one_joint_per_occupied_socket_at_every_depth() -> void:
	var torso := _make_part(&"torso")
	var shoulder: Socket = _add_socket(torso, &"SHOULDER")
	_add_socket(torso, &"HIP")  # stays empty on purpose — no joint for it

	var arm := _make_part(&"arm", [&"SHOULDER"])
	var wrist: Socket = _add_socket(arm, &"WRIST")
	var hand := _make_part(&"hand", [&"WRIST"])

	shoulder.occupant = arm
	wrist.occupant = hand

	assert_eq(PartGraph.walk(torso).size(), 3, "torso + arm + hand, no joints")

	var with_joints: Array[Part] = PartGraph.walk_with_joints(torso)
	assert_eq(with_joints.size(), 5, "torso + arm + hand + one joint per occupied socket (2)")
	assert_true(with_joints.has(shoulder.joint_handle()))
	assert_true(with_joints.has(wrist.joint_handle()))


func test_walk_with_joints_matches_walk_with_nothing_attached() -> void:
	var torso := _make_part(&"torso")
	_add_socket(torso, &"SHOULDER")

	assert_eq(PartGraph.walk_with_joints(torso), PartGraph.walk(torso))
