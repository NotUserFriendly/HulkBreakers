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


func test_impact_event_names_which_unit_actually_took_the_hit() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 2)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0)
	assert_eq(
		impacts[0].data.get("target_unit_id"),
		target.id,
		"docs/09: which unit was actually hit must be in the log, not just which part"
	)


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


## A target whose HEAD — not its torso root — is frontmost, hosts a matrix,
## and is VOLATILE: one shot destroying it should cascade through every
## consequence DamageResolver tracks (destroyed/cooked-off/ejected/dropped),
## and each of those must reach the combat log (docs/09: "if it changed the
## world, it's in the log"), not just the bare "impact" event. Only torso
## and head templates ever declare a MATRIX socket (docs/01) — an arm never
## can — so the non-root host here is a head, docked via a NECK socket.
func _make_armed_matrix_hosting_target(cell: Vector2i) -> Dictionary:
	var head := Part.new()
	head.id = &"head"
	head.hp = 5
	head.max_hp = 5
	head.attaches_to = [&"NECK"]
	head.sockets = [Socket.new(&"MATRIX")]
	var link := Matrix.new()
	link.id = &"link"
	head.dock_matrix(link)
	head.tags = [&"VOLATILE"]
	head.cook_off_damage = 2.0
	head.cook_off_radius = 2.0  # reaches the target itself, not the shooter 5 cells away
	# Frontmost: sits just ahead of the torso's own box along local +z
	# (docs/02's front-facing convention, same as the plate in
	# test_rifle_round_over_dt), wide enough that dartboard scatter can't
	# miss it and land on the torso behind instead.
	head.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(1.5, 1.0, 0.3))]

	# High hp: the cascading shot (docs/03) that destroys the head keeps
	# traveling and also lands on this torso — it must survive so the test
	# isolates exactly one destroyed part (the head).
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 100
	torso.max_hp = 100
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var neck := Socket.new(&"NECK")
	neck.occupant = head
	torso.sockets = [neck]

	var unit := Unit.new(Matrix.new(), Frame.new(torso), cell, 1)
	return {"unit": unit, "torso": torso, "head": head, "link": link}


## Same shape as _make_shooter, but with high torso hp — collinear with the
## target, this shooter's own torso sits in its own shot's path (docs/02: the
## ray always starts at the shooter) and must survive the cascade too.
func _make_tough_shooter(cell: Vector2i, weapon: Part) -> Unit:
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
	torso.id = &"shooter_torso"
	torso.hp = 100
	torso.max_hp = 100
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Frame.new(torso), cell, 0)


func test_destroying_the_head_logs_every_cascading_consequence() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_tough_shooter(Vector2i(0, 5), weapon)
	var built: Dictionary = _make_armed_matrix_hosting_target(Vector2i(0, 0))
	var target: Unit = built.unit
	var head: Part = built.head
	var link: Matrix = built.link
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", Vector2i(0, 0)).apply(state)

	assert_eq(head.hp, 0, "the head must actually have been destroyed by this shot")

	assert_eq(sink.events_of_kind(&"part_destroyed").size(), 1)
	assert_eq(sink.events_of_kind(&"part_destroyed")[0].data.get("part"), &"head")

	var cook_offs: Array[LogEvent] = sink.events_of_kind(&"cook_off")
	assert_eq(cook_offs.size(), 1)
	assert_eq(cook_offs[0].data.get("unit"), target.id)

	var ejections: Array[LogEvent] = sink.events_of_kind(&"matrix_ejected")
	assert_eq(ejections.size(), 1)
	assert_eq(ejections[0].data.get("matrix"), link.id)

	var drops: Array[LogEvent] = sink.events_of_kind(&"subtree_dropped")
	assert_eq(drops.size(), 1)
	assert_eq(drops[0].data.get("part"), &"head")

	var demotions: Array[LogEvent] = sink.events_of_kind(&"surrogate_demoted")
	assert_eq(demotions.size(), 1, "ejection must carry its own demotion into the log")
	assert_eq(demotions[0].unit_id, target.id)
	assert_eq(demotions[0].data.get("from"), &"FULL")
	assert_eq(demotions[0].data.get("to"), &"PERIPHERAL")


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
