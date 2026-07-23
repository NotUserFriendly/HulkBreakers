extends GutTest

## taskblock-09 C: two independent HP pools per limb — part HP (shoot the
## forearm, it fails per its own failure_mode, docs/03 Pass A) and joint HP
## (shoot the elbow, the intact forearm drops). `Socket.joint_hp` is
## copied from the CHILD's own `Part.joint_hp` at attach time
## (`PartGraph.attach`, docs/01's "the arm carries the info" inversion),
## never authored on the socket/parent itself.


## torso -[SHOULDER]- arm -[WRIST]- hand -[GRIP]- pistol, attached via
## PartGraph.attach (not a bare `socket.occupant = x`) so joint_hp actually
## gets copied.
func _make_armed_unit(cell: Vector2i, arm_joint_hp: int = 4) -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.attaches_to = [&"GRIP"]

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.attaches_to = [&"WRIST"]
	hand.sockets = [Socket.new(&"GRIP")]
	PartGraph.attach(pistol, hand, hand.sockets[0])

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 3
	arm.max_hp = 3
	arm.attaches_to = [&"SHOULDER"]
	arm.joint_hp = arm_joint_hp
	arm.sockets = [Socket.new(&"WRIST")]
	PartGraph.attach(hand, arm, arm.sockets[0])

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.sockets = [Socket.new(&"SHOULDER")]
	PartGraph.attach(arm, torso, torso.sockets[0])

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell)
	return {
		"unit": unit,
		"torso": torso,
		"arm": arm,
		"hand": hand,
		"pistol": pistol,
		"shoulder": torso.sockets[0],
	}


func test_attach_copies_joint_hp_from_the_child_not_the_parent() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(0, 0), 7)
	var shoulder: Socket = built.shoulder

	assert_eq(shoulder.joint_hp, 7, "the socket's runtime joint_hp comes from the occupant")
	assert_eq(shoulder.joint_hp_max, 7)


func test_the_same_heavy_arm_severs_just_as_hard_on_any_frame() -> void:
	var light_torso := Part.new()
	light_torso.id = &"light_torso"
	light_torso.hp = 3
	light_torso.max_hp = 3
	light_torso.sockets = [Socket.new(&"SHOULDER")]

	var heavy_torso := Part.new()
	heavy_torso.id = &"heavy_torso"
	heavy_torso.hp = 50
	heavy_torso.max_hp = 50
	heavy_torso.sockets = [Socket.new(&"SHOULDER")]

	var battle_arm_template := Part.new()
	battle_arm_template.id = &"battle_arm"
	battle_arm_template.attaches_to = [&"SHOULDER"]
	battle_arm_template.joint_hp = 9

	PartGraph.attach(battle_arm_template.duplicate(true), light_torso, light_torso.sockets[0])
	PartGraph.attach(battle_arm_template.duplicate(true), heavy_torso, heavy_torso.sockets[0])

	assert_eq(light_torso.sockets[0].joint_hp, 9, "a tough joint on a light frame")
	assert_eq(
		heavy_torso.sockets[0].joint_hp,
		light_torso.sockets[0].joint_hp,
		"the exact same arm severs just as hard regardless of what frame it's on"
	)


func test_depleting_joint_hp_severs_and_drops_the_intact_subtree_sockets_still_populated() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var hand: Part = built.hand
	var pistol: Part = built.pistol
	var shoulder: Socket = built.shoulder
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_true(DamageResolver.apply_damage_to_joint(shoulder, 10.0))
	var dropped: Part = DamageResolver.sever_joint(shoulder, unit.cell, state)

	assert_eq(dropped, arm)
	assert_null(shoulder.occupant, "the socket itself is empty once severed")
	assert_false(
		unit.shell.all_parts().has(arm), "the severed arm is no longer part of the unit's assembly"
	)
	assert_true(
		PartGraph.walk(arm).has(hand) and PartGraph.walk(arm).has(pistol),
		"the arm's own subtree (hand, pistol) drops with it, fully assembled — one intact assembly"
	)
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(arm),
		"the dropped arm must land as a recoverable field item"
	)
	assert_eq(state.grid.blockers[Vector2i(2, 2)], arm)


func test_depleting_part_hp_runs_failure_mode_and_never_touches_the_joint() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var shoulder: Socket = built.shoulder
	var state := CombatState.new(Grid.new(5, 5), [unit])
	var joint_hp_before: int = shoulder.joint_hp

	assert_true(DamageResolver.apply_damage_to_part(arm, 10.0))
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(arm, state, impact)

	assert_true(arm.is_mangled, "MANGLE is the default failure_mode")
	assert_eq(shoulder.occupant, arm, "part failure alone never detaches — only a severed joint")
	assert_eq(shoulder.joint_hp, joint_hp_before, "part damage must never touch the joint's own hp")


func test_apply_damage_to_joint_floors_at_zero_and_severs_exactly_there() -> void:
	var socket := Socket.new(&"SHOULDER")
	socket.joint_hp = 4
	socket.joint_hp_max = 4

	assert_false(DamageResolver.apply_damage_to_joint(socket, 3.0), "3 of 4: not severed yet")
	assert_eq(socket.joint_hp, 1)
	assert_true(
		DamageResolver.apply_damage_to_joint(socket, 1.0), "the last hp: severed exactly now"
	)
	assert_eq(socket.joint_hp, 0)
	assert_true(
		DamageResolver.apply_damage_to_joint(socket, 5.0), "still severed once already at 0"
	)
	assert_eq(socket.joint_hp, 0, "floors at 0, never goes negative")


func test_sever_joint_is_a_no_op_for_an_empty_socket() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	var socket := Socket.new(&"SHOULDER")
	torso.sockets = [socket]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(1, 1))
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_null(DamageResolver.sever_joint(socket, unit.cell, state))
	assert_true(state.grid.field_items.is_empty())


## taskblock-09 D: a torso with one shoulder, offset far enough laterally
## (x=1.3) to sit clear of the torso's own box (half-width 1.0), and an
## arm whose own volume is offset OUTWARD from the shoulder's attach point
## (not centered on it, the way a real limb extends from its joint) —
## torso, joint, and arm all land in disjoint screen-space lateral ranges,
## so each is independently, unambiguously aimable.
func _make_joint_reachable_fixture(cell: Vector2i) -> Dictionary:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 5
	arm.max_hp = 5
	arm.joint_hp = 4
	arm.attaches_to = [&"SHOULDER"]
	arm.volume = [Box.new(Vector3(0.4, 0.5, 0.0), Vector3(0.6, 0.3, 0.3))]

	var shoulder := Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(1.3, 0.5, 0.0)))
	torso.sockets = [shoulder]
	PartGraph.attach(arm, torso, shoulder)

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell)
	return {"unit": unit, "torso": torso, "arm": arm, "shoulder": shoulder}


func _joint_region(plane: Array[Region], socket: Socket) -> Region:
	for region: Region in plane:
		if region.socket == socket:
			return region
	fail_test("no joint region for socket")
	return null


func test_resolve_shot_on_a_joint_hit_depletes_joint_hp_never_part_hp() -> void:
	var built: Dictionary = _make_joint_reachable_fixture(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var shoulder: Socket = built.shoulder
	var state := CombatState.new(Grid.new(10, 10), [unit])
	var table := DataLibrary.material_table()

	var origin := Vector2(2, 8)
	var direction := Vector2(0, -1)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	var aim_point: Vector2 = _joint_region(plane, shoulder).rect.get_center()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 2.0, 0.0, state, table, rng
	)

	assert_eq(results.size(), 1)
	assert_eq(results[0].region.socket, shoulder)
	assert_eq(shoulder.joint_hp, 2, "4 joint hp - ceil(2.0 damage)")
	assert_eq(arm.hp, 5, "a joint hit must never touch the part's own hp")


func test_resolve_shot_severs_the_joint_and_drops_the_subtree_when_depleted() -> void:
	var built: Dictionary = _make_joint_reachable_fixture(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var shoulder: Socket = built.shoulder
	var state := CombatState.new(Grid.new(10, 10), [unit])
	var table := DataLibrary.material_table()

	var origin := Vector2(2, 8)
	var direction := Vector2(0, -1)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	var aim_point: Vector2 = _joint_region(plane, shoulder).rect.get_center()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 10.0, 0.0, state, table, rng
	)

	assert_eq(results.size(), 1)
	assert_eq(results[0].dropped_subtree, [arm])
	assert_null(shoulder.occupant, "the joint's own occupant is gone once severed")
	assert_true(state.grid.field_items[Vector2i(2, 2)].has(arm))


## taskblock-26 Pass D: joints default to 3 HP (a weaken-then-sever
## gradient) instead of tb09's original 1 (an instant sever on any hit
## reaching a joint at all). Per-part overrides (`arm.joint_hp = N`, tested
## above and in `test_attach_copies_joint_hp_from_the_child_not_the_parent`)
## still win — this only covers the un-authored CLASS default.
func test_a_fresh_joint_defaults_to_3_hp() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.attaches_to = [&"SHOULDER"]

	var torso := Part.new()
	torso.id = &"torso"
	var shoulder := Socket.new(&"SHOULDER")
	torso.sockets = [shoulder]
	PartGraph.attach(arm, torso, shoulder)

	assert_eq(arm.joint_hp, 3, "Part.joint_hp's own class default")
	assert_eq(shoulder.joint_hp, 3)
	assert_eq(shoulder.joint_hp_max, 3)


func test_a_default_joint_takes_3_points_across_hits_before_severing() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(0, 0), 3)  # the new default, spelled out
	var shoulder: Socket = built.shoulder

	assert_false(DamageResolver.apply_damage_to_joint(shoulder, 1.0), "1 of 3: still attached")
	assert_eq(shoulder.joint_hp, 2)
	assert_false(DamageResolver.apply_damage_to_joint(shoulder, 1.0), "2 of 3: still attached")
	assert_eq(shoulder.joint_hp, 1)
	assert_true(DamageResolver.apply_damage_to_joint(shoulder, 1.0), "the 3rd point severs it")
	assert_eq(shoulder.joint_hp, 0)


## taskblock-26 Pass D: a torso whose shoulder joint is additionally
## protected by a small cladding Part (`Socket.joint_cladding`) sitting at
## the joint's own attach point — the "the new piece is cladding that
## attaches to/covers a socket's joint" half of Pass D. Reuses
## `_make_joint_reachable_fixture`'s geometry verbatim; only the cladding
## is new.
func _make_cladded_joint_fixture(cell: Vector2i) -> Dictionary:
	var built: Dictionary = _make_joint_reachable_fixture(cell)
	var shoulder: Socket = built.shoulder

	var cladding := Part.new()
	cladding.id = &"shoulder_cladding"
	cladding.material = &"steel"  # dt 6 (test_damage_resolver.gd's own reference)
	cladding.hp = 4
	cladding.max_hp = 4
	cladding.volume = [Box.new(Vector3.ZERO, Vector3(0.2, 0.2, 0.2))]
	shoulder.joint_cladding = cladding

	built.cladding = cladding
	return built


func test_joint_cladding_absorbs_a_hit_before_the_joint_takes_any_damage() -> void:
	var built: Dictionary = _make_cladded_joint_fixture(Vector2i(2, 2))
	var unit: Unit = built.unit
	var shoulder: Socket = built.shoulder
	var cladding: Part = built.cladding
	var joint_hp_before: int = shoulder.joint_hp
	var state := CombatState.new(Grid.new(10, 10), [unit])
	var table := DataLibrary.material_table()

	var origin := Vector2(2, 8)
	var direction := Vector2(0, -1)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	var aim_point: Vector2 = _joint_region(plane, shoulder).rect.get_center()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 2.0, 0.0, state, table, rng
	)

	assert_eq(results.size(), 1)
	assert_eq(results[0].region.part, cladding, "aiming at the joint hits its cladding first")
	assert_null(results[0].region.socket, "the cladding's own region is an ordinary part region")
	assert_lt(cladding.hp, 4, "the cladding itself absorbs the hit")
	assert_eq(shoulder.joint_hp, joint_hp_before, "the joint underneath never took damage")


func test_an_uncladded_joint_behaves_as_before_just_with_the_new_hp_default() -> void:
	var built: Dictionary = _make_joint_reachable_fixture(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var shoulder: Socket = built.shoulder
	assert_null(shoulder.joint_cladding, "this fixture's joint is deliberately bare")
	var state := CombatState.new(Grid.new(10, 10), [unit])
	var table := DataLibrary.material_table()

	var origin := Vector2(2, 8)
	var direction := Vector2(0, -1)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	var aim_point: Vector2 = _joint_region(plane, shoulder).rect.get_center()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 2.0, 0.0, state, table, rng
	)

	assert_eq(results.size(), 1)
	assert_eq(results[0].region.socket, shoulder, "a bare joint hits directly, same as before")
	assert_eq(shoulder.joint_hp, 2, "4 joint hp - ceil(2.0 damage), same mechanism as before")
	assert_eq(arm.hp, 5, "still never touches the part's own hp")
