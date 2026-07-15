extends GutTest

## docs/02/03/09, Phase 6: aim point -> dartboard -> shot plane -> impact,
## queued and resolved through the two-phase turn.


func _make_weapon(
	id: StringName, damage: float, ap_cost: int = 1, weapon_max_range: float = 0.0
) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = damage
	weapon.ap_cost = ap_cost
	weapon.burst = 1
	weapon.weapon_max_range = weapon_max_range
	weapon.scatter = [Ring.new(0.05, 1.0)]
	return weapon


## A shooter whose torso holds a trigger-capable hand gripping `weapon`.
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

	return Unit.new(Matrix.new(), Frame.new(torso), cell, 0)


func _make_target(cell: Vector2i, hp: int = 10) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Frame.new(torso), cell, 1)


func test_is_legal_true_in_the_baseline_case() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])

	var action := AttackAction.new(shooter, &"pistol", Vector2i(3, 0))
	assert_true(action.is_legal(state))


func test_is_legal_false_without_enough_ap() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 3)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	shooter.ap = 1  # after construction: CombatState._init resets ap to max_ap

	assert_false(AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).is_legal(state))


func test_is_legal_false_beyond_weapon_range() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 1, 3.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(9, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])

	assert_false(AttackAction.new(shooter, &"pistol", Vector2i(9, 0)).is_legal(state))


func test_is_legal_false_without_line_of_sight() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	grid.set_opacity(Vector2i(1, 0), 1.0)
	grid.set_terrain(Vector2i(1, 0), Enums.TerrainType.WALL)
	var state := CombatState.new(grid, [shooter, target])

	assert_false(AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).is_legal(state))


func test_is_legal_false_without_a_capable_manipulator() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	# Strip the hand's TRIGGER capability — a saw, say.
	shooter.frame.find_part(&"hand").capabilities = []
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])

	assert_false(AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).is_legal(state))


func test_apply_deals_damage_and_spends_ap() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 2)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var before_ap: int = shooter.ap

	AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).apply(state)

	assert_eq(shooter.ap, before_ap - 2)
	assert_lt(target.frame.root.hp, 10, "an unarmored torso hit with damage 20 must penetrate")


func test_a_queued_attack_on_a_target_that_dies_earlier_aborts_and_the_queue_continues() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0), 5)  # dies to a single 20-damage hit
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var queue := ActionQueue.new(shooter)

	# Both attacks are legal when queued: the preview doesn't (and can't)
	# predict that the first shot's real, RNG-resolved damage will kill the
	# target before the second one gets its turn (docs/09).
	var first := AttackAction.new(shooter, &"pistol", Vector2i(3, 0))
	var second := AttackAction.new(shooter, &"pistol", Vector2i(3, 0))
	assert_true(queue.enqueue(first, state))
	assert_true(queue.enqueue(second, state))
	assert_true(queue.enqueue(EndTurnAction.new(shooter), state))

	state.resolve_turn(queue)

	assert_true(
		state.action_log.any(func(line: String) -> bool: return line.begins_with("aborted")),
		"the second attack must have aborted with a logged reason: %s" % [state.action_log]
	)


## torso is steel (dt 6) so a damage-3 dead-on hit stops dead at the torso
## instead of overpenetrating into whatever's behind it — occlusion, not
## just "the round punched through everything anyway."
func _make_armored_target(cell: Vector2i, rack: Part) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.material = &"steel"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var back_socket := Socket.new(&"BACK")
	back_socket.occupant = rack
	torso.sockets = [back_socket]
	return Unit.new(Matrix.new(), Frame.new(torso), cell, 1)


func _make_rack() -> Part:
	var rack := Part.new()
	rack.id = &"rack"
	rack.hp = 5
	rack.max_hp = 5
	rack.attaches_to = [&"BACK"]
	rack.volume = [Box.new(Vector3(0.0, 0.5, -0.3), Vector3(0.8, 1.0, 0.2))]
	return rack


func test_flanking_exposes_a_rear_part_a_frontal_shot_cannot_reach() -> void:
	# The unit's front faces world +Y (orientation 0), so a shooter at larger
	# Y firing in -Y hits the front dead-on; at smaller Y firing in +Y hits
	# the back instead.
	var weapon_front := _make_weapon(&"pistol", 3.0)
	var rack_front := _make_rack()
	var shooter_front := _make_shooter(Vector2i(0, 5), weapon_front)
	var target_front := _make_armored_target(Vector2i(0, 0), rack_front)
	var state_front := CombatState.new(Grid.new(20, 20), [shooter_front, target_front])
	AttackAction.new(shooter_front, &"pistol", Vector2i(0, 0)).apply(state_front)
	assert_eq(rack_front.hp, 5, "the front-mounted torso must occlude the rear rack")

	var weapon_rear := _make_weapon(&"pistol2", 3.0)
	var rack_rear := _make_rack()
	var shooter_rear := _make_shooter(Vector2i(0, -5), weapon_rear)
	var target_rear := _make_armored_target(Vector2i(0, 0), rack_rear)
	var state_rear := CombatState.new(Grid.new(20, 20), [shooter_rear, target_rear])
	AttackAction.new(shooter_rear, &"pistol2", Vector2i(0, 0)).apply(state_rear)
	assert_lt(rack_rear.hp, 5, "attacking from behind must expose the rear rack instead")


func test_replays_identically_from_the_same_seed() -> void:
	var results: Array = []
	for run in range(2):
		var weapon := _make_weapon(&"pistol", 3.0)  # low damage: leaves crit/scatter room to vary
		weapon.crit_chance = 0.5
		var shooter := _make_shooter(Vector2i(0, 0), weapon)
		var target := _make_target(Vector2i(4, 0), 30)
		var grid := Grid.new(10, 10)
		var state := CombatState.new(grid, [shooter, target], 777)

		for i in range(5):
			AttackAction.new(shooter, &"pistol", Vector2i(4, 0)).apply(state)
		results.append([shooter.ap, target.frame.root.hp])

	assert_eq(results[0], results[1])
