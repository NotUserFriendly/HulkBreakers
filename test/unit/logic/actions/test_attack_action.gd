extends GutTest

## docs/02/03/09, Phase 6: aim point -> dartboard -> shot plane -> impact,
## queued and resolved through the two-phase turn.


func _make_weapon(id: StringName, damage: float, ap_cost: int = 1, max_range: float = 0.0) -> Part:
	var weapon := Part.new()
	weapon.id = id
	weapon.hp = 1
	weapon.max_hp = 1
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = damage
	weapon.ap_cost = ap_cost
	weapon.burst = 1
	# taskblock-24 Pass B: AttackAction.is_legal now requires the weapon
	# actually provide &"shoot" (the same gate ActionCatalog's own action
	# bar already applied) — every weapon built through this helper fires
	# as an ordinary single shot unless a test says otherwise.
	weapon.provides_actions = [&"shoot"]
	if max_range > 0.0:
		weapon.weapon_def = WeaponDef.new()
		weapon.weapon_def.max_range = max_range
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

	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func _make_target(cell: Vector2i, hp: int = 10) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


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


## taskblock-19 Pass E: "a unit adjacent to an enemy can't fire a long
## gun (can fire a short one)."
func test_is_legal_false_for_a_two_handed_weapon_adjacent_to_an_enemy() -> void:
	var weapon := _make_weapon(&"rifle", 20.0)
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.two_handed = true
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var adjacent_enemy := _make_target(Vector2i(1, 0))
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, adjacent_enemy, target])

	assert_false(AttackAction.new(shooter, &"rifle", Vector2i(3, 0)).is_legal(state))


func test_is_legal_true_for_a_short_weapon_adjacent_to_an_enemy() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var adjacent_enemy := _make_target(Vector2i(1, 0))
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, adjacent_enemy, target])

	assert_true(AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).is_legal(state))


## taskblock-19 Pass C2: "a unit under min range with a non-explosive
## weapon can't fire" — the default min_range_failure (&"none") blocks.
func test_is_legal_false_under_min_range_for_a_non_dud_weapon() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 1, 10.0)
	weapon.weapon_def.min_range = 3.0
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(2, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])

	assert_false(AttackAction.new(shooter, &"pistol", Vector2i(2, 0)).is_legal(state))


## taskblock-19 Pass C2: a dud-capable weapon is never blocked by min
## range — it fires anyway, tagged as a dud.
func test_a_dud_capable_weapon_still_fires_under_min_range_and_is_flagged() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 1, 10.0)
	weapon.weapon_def.min_range = 3.0
	weapon.weapon_def.min_range_failure = &"dud"
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(2, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	assert_true(AttackAction.new(shooter, &"pistol", Vector2i(2, 0)).is_legal(state))
	AttackAction.new(shooter, &"pistol", Vector2i(2, 0)).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0)
	assert_true(impacts[0].data.get("is_dud"))


func test_a_normal_shot_within_min_range_is_not_flagged_as_a_dud() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 1, 10.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0)
	assert_false(impacts[0].data.get("is_dud"))


## taskblock-19 Pass C1: beyond effective_range, the dartboard widens —
## a degraded shot's resolved ring radius must be strictly larger than
## the same weapon's radius at full accuracy.
func test_a_shot_beyond_effective_range_scales_up_the_dartboard() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 1, 8.0)
	weapon.scatter = [Ring.new(0.1, 1.0)]
	weapon.weapon_def.effective_range = 2.0

	var close_radius: float = (
		Dartboard
		. resolve_scatter(weapon, [], RangeModel.dartboard_radius_scale(weapon, 2))[0]
		. radius
	)
	var far_radius: float = (
		Dartboard
		. resolve_scatter(weapon, [], RangeModel.dartboard_radius_scale(weapon, 8))[0]
		. radius
	)

	assert_almost_eq(close_radius, 0.1, 0.0001, "full accuracy at effective range")
	assert_gt(far_radius, close_radius, "degraded accuracy widens the ring")


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
	shooter.shell.find_part(&"hand").capabilities = []
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])

	assert_false(AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).is_legal(state))


## taskblock-24 Pass B: "the engine, not just the UI, enforces a burst-only
## weapon can't single-shot" — a weapon that only ever lists &"burst" in
## its own provides_actions must fail is_legal, not just be absent from
## the player's action bar.
func test_is_legal_false_for_a_weapon_that_only_provides_burst() -> void:
	var weapon := _make_weapon(&"chaingun", 20.0)
	weapon.provides_actions = [&"burst"]
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	assert_false(
		AttackAction.new(shooter, &"chaingun", Vector2i(3, 0)).is_legal(state),
		"a burst-only weapon must never single-shot, engine-side"
	)


## The mirror: a weapon providing BOTH must still allow the plain shot.
func test_is_legal_true_for_a_weapon_that_provides_both_shoot_and_burst() -> void:
	var weapon := _make_weapon(&"auto_shotgun", 20.0)
	weapon.provides_actions = [&"shoot", &"burst"]
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	assert_true(AttackAction.new(shooter, &"auto_shotgun", Vector2i(3, 0)).is_legal(state))


func test_apply_deals_damage_and_spends_ap() -> void:
	var weapon := _make_weapon(&"pistol", 20.0, 2)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var before_ap: int = shooter.ap

	AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).apply(state)

	assert_eq(shooter.ap, before_ap - 2)
	assert_lt(target.shell.root.hp, 10, "an unarmored torso hit with damage 20 must penetrate")


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


## taskblock-26 (CC, re-diagnosing A2 "muzzle origin inside the shooter's
## own armor"): the taskblock-26 Pass A2 fix touched `UnitGeometry.
## muzzle_point()`, but no real firing action ever consumed its X/Z —
## every one of them built the shot plane (and therefore the logged/drawn
## `impact.origin`) from the shooter's own bare CELL center regardless.
## A real weapon (like the shipped `pistol.tres`) authors a `volume` box
## offset forward of its own grip — with that offset present, the logged
## origin must now sit forward of the shooter's own cell center, along the
## firing direction, not dead center in its own chest.
func test_impact_origin_comes_from_the_real_muzzle_not_the_bare_cell_center() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	weapon.volume = [Box.new(Vector3(0.0, 0.0, 0.2), Vector3(0.1, 0.2, 0.4))]
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", Vector2i(3, 0)).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0)
	var origin_x: float = impacts[0].data.get("origin_x")
	var origin_y: float = impacts[0].data.get("origin_y")
	assert_ne(
		Vector2(origin_x, origin_y),
		Vector2(shooter.cell.x, shooter.cell.y),
		"the logged origin must move to the weapon's own muzzle, not stay at the bare cell center"
	)
	assert_gt(
		origin_x,
		float(shooter.cell.x),
		"the pistol's own forward tip sits ahead of the shooter, toward the target at (3, 0)"
	)


## docs/09 taskblock06 D2: reverses taskblock02 F — the second attack's
## own illegality (its target is already dead) now STOPS resolve_until
## entirely, so the trailing EndTurnAction queued after it never runs
## either, not just the invalidated attack itself.
func test_a_queued_attack_on_a_target_that_dies_earlier_stops_resolution() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0), 5)  # dies to a single 20-damage hit
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid, [shooter, target])
	var queue := ActionQueue.new(shooter)
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	# Both attacks are legal when queued: the preview doesn't (and can't)
	# predict that the first shot's real, RNG-resolved damage will kill the
	# target before the second one gets its turn (docs/09).
	var first := AttackAction.new(shooter, &"pistol", Vector2i(3, 0))
	var second := AttackAction.new(shooter, &"pistol", Vector2i(3, 0))
	assert_true(queue.enqueue(first, state))
	assert_true(queue.enqueue(second, state))
	assert_true(queue.enqueue(EndTurnAction.new(shooter), state))

	var outcome: Dictionary = state.resolve_until(queue)

	assert_eq(outcome.kind, Enums.ResolveOutcome.STOPPED)
	assert_eq(outcome.reason, &"next_action_illegal")
	assert_eq(
		sink.events_of_kind(&"impact").size(), 1, "only the first attack must have actually fired"
	)
	assert_eq(
		state.current_unit(),
		shooter,
		"the trailing EndTurnAction must never have run once resolution stopped"
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
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


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
## and fails by DETONATE: one shot destroying it should cascade through
## every consequence DamageResolver tracks (destroyed/detonated/ejected),
## and each of those must reach the combat log (docs/09: "if it changed the
## world, it's in the log"), not just the bare "impact" event. Only torso
## and head templates ever declare a MATRIX socket (docs/01) — an arm never
## can — so the non-root host here is a head, docked via a NECK socket.
## taskblock-09 C2: destroying the head no longer drops it — that's a
## severed JOINT now, a separate hit this test doesn't make — so this test
## no longer asserts a subtree_dropped event.
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
	head.failure_mode = &"DETONATE"
	head.detonate_damage = 2.0
	head.detonate_radius = 2.0  # reaches the target itself, not the shooter 5 cells away
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

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 1)
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

	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


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

	var detonations: Array[LogEvent] = sink.events_of_kind(&"detonate")
	assert_eq(detonations.size(), 1)
	assert_eq(detonations[0].data.get("unit"), target.id)

	var ejections: Array[LogEvent] = sink.events_of_kind(&"matrix_ejected")
	assert_eq(ejections.size(), 1)
	assert_eq(ejections[0].data.get("matrix"), link.id)

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
		results.append([shooter.ap, target.shell.root.hp])

	assert_eq(results[0], results[1])


## docs/10 taskblock04 C3: "this is where docs/07's harvest loop finally
## touches the board" — a field object destroyed along the shot's own path
## (never the target itself; that's still center-mass, docs/02) credits
## its salvage_yield to the mission, the exact same
## MissionState.gather_resource() a real GatherAction call uses.
func test_destroying_a_scrap_pile_along_the_shot_credits_its_salvage_to_the_mission() -> void:
	var weapon := _make_weapon(&"pistol", 999.0)
	var shooter := _make_shooter(Vector2i(2, 0), weapon)
	var target := _make_target(Vector2i(2, 4))
	var grid := Grid.new(10, 10)
	var scrap: Part = DataLibrary.get_part(&"scrap_pile")
	grid.blockers[Vector2i(2, 2)] = scrap
	var state := CombatState.new(grid, [shooter, target])
	var mission := MissionState.new(RunState.new(), state)

	AttackAction.new(shooter, &"pistol", target.cell, Vector2.ZERO, [], mission).apply(state)

	assert_eq(scrap.hp, 0, "the overwhelming shot must have actually destroyed the scrap pile")
	assert_eq(mission.gathered_resources.get(&"metals"), 4)


## No mission context (a standalone battle, most tests/BattleScene): the
## same overwhelming shot must not crash for lack of anywhere to credit
## salvage — `mission` defaults to null exactly so attacking works with or
## without one.
func test_destroying_a_field_object_with_no_mission_context_does_not_crash() -> void:
	var weapon := _make_weapon(&"pistol", 999.0)
	var shooter := _make_shooter(Vector2i(2, 0), weapon)
	var target := _make_target(Vector2i(2, 4))
	var grid := Grid.new(10, 10)
	var scrap: Part = DataLibrary.get_part(&"scrap_pile")
	grid.blockers[Vector2i(2, 2)] = scrap
	var state := CombatState.new(grid, [shooter, target])

	AttackAction.new(shooter, &"pistol", target.cell).apply(state)

	assert_eq(scrap.hp, 0)


## taskblock-22 Pass H: a shooter fixture with a REAL, non-identity GRIP
## height (unlike `_make_shooter`'s own identity-transform HAND socket,
## which fires from world Y=0) — `shoulder_y` optional, a real SHOULDER
## socket for `shouldered_muzzle_point` to find, same authored convention
## `data/parts/torso.tres` uses.
func _make_shooter_with_grip_height(
	cell: Vector2i, weapon: Part, grip_y: float, shoulder_y: Variant = null
) -> Unit:
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
	var hand_socket := Socket.new(&"HAND", Transform3D(Basis(), Vector3(0.0, grip_y, 0.0)))
	hand_socket.occupant = hand
	var sockets: Array[Socket] = [hand_socket]
	if shoulder_y != null:
		sockets.append(Socket.new(&"SHOULDER", Transform3D(Basis(), Vector3(0.0, shoulder_y, 0.0))))
	torso.sockets = sockets

	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func _make_low_cover(top_height: float) -> Part:
	var cover := Part.new()
	cover.id = &"low_cover"
	cover.hp = 10
	cover.max_hp = 10
	cover.material = &"steel"
	cover.volume = [Box.new(Vector3(0.0, top_height / 2.0, 0.0), Vector3(1.0, top_height, 0.6))]
	return cover


## taskblock-22 Pass H2: "the shot's ray originates and immediately hits
## the cover if the muzzle is below the cover's height" — a hip-height
## (0.3), un-shouldered muzzle firing through low cover (top 0.6, taller
## than the muzzle) directly ahead hits the cover instead of the target.
func test_a_hip_height_muzzle_behind_low_cover_hits_the_cover_not_the_target() -> void:
	# Below steel's own dt=6.0 (data/materials/steel.tres) — a penetrating
	# round would punch through the cover into the target too, which is
	# correct behavior for a strong enough round, just not what THIS test
	# is isolating (the obstruction itself, not the material fight after).
	var weapon := _make_weapon(&"pistol", 3.0)
	var shooter := _make_shooter_with_grip_height(Vector2i(2, 0), weapon, 0.3)
	var target := _make_target(Vector2i(2, 4))
	var grid := Grid.new(10, 10)
	var cover := _make_low_cover(0.6)
	grid.blockers[Vector2i(2, 2)] = cover
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", target.cell).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_eq(impacts.size(), 1, "one impact — the cover, never reaching the target beyond it")
	assert_eq(impacts[0].data.get("part"), cover.id)
	assert_eq(target.shell.root.hp, 10, "the target must be completely untouched")


## H1: "shouldering clears cover the unshouldered position wouldn't" —
## same low cover, same grip height, but a real SHOULDER socket now
## exists (1.53, above the cover's own 0.4 top) for the firing height to
## raise to. Cover top is kept BELOW the target's own aim height (0.5,
## `_make_target`'s torso center) on purpose — a taller cover would also
## block the aimed-at-target-height shot on its own (the existing,
## unrelated "cover blocks anything passing through its own height range"
## mechanic), which would pass this test for the wrong reason.
func test_shouldering_clears_cover_the_unshouldered_position_would_not() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter_with_grip_height(Vector2i(2, 0), weapon, 0.3, 1.53)
	var target := _make_target(Vector2i(2, 4))
	var grid := Grid.new(10, 10)
	var cover := _make_low_cover(0.4)
	grid.blockers[Vector2i(2, 2)] = cover
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", target.cell).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_eq(impacts.size(), 1)
	assert_eq(
		impacts[0].data.get("target_unit_id"),
		target.id,
		"shouldering must clear the same cover the earlier test hit"
	)
	assert_eq(cover.hp, 10, "the cover itself must be untouched once cleared")
	assert_lt(target.shell.root.hp, 10, "the target must actually have been hit")


## The obstruction check must key off the shooter's REAL geometry
## (`ShotPlane.self_obstruction`, the same plane the real shot resolves
## against) — cover just short of the muzzle height must NOT obstruct.
## Same 0.4 cover (below the target's own 0.5 aim height) as the test
## above, for the same reason.
func test_cover_shorter_than_the_muzzle_does_not_obstruct_the_shot() -> void:
	var weapon := _make_weapon(&"pistol", 20.0)
	var shooter := _make_shooter_with_grip_height(Vector2i(2, 0), weapon, 0.9)
	var target := _make_target(Vector2i(2, 4))
	var grid := Grid.new(10, 10)
	var cover := _make_low_cover(0.4)  # shorter than the 0.9 muzzle
	grid.blockers[Vector2i(2, 2)] = cover
	var state := CombatState.new(grid, [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	AttackAction.new(shooter, &"pistol", target.cell).apply(state)

	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_eq(impacts.size(), 1)
	assert_eq(impacts[0].data.get("target_unit_id"), target.id)
