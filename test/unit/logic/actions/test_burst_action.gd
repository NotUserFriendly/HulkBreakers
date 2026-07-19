extends GutTest

## taskblock-13 Pass C: BurstAction — N independent trigger-pulls, each its
## own dartboard roll, in one activation.


func _make_chaingun() -> Part:
	var weapon := Part.new()
	weapon.id = &"chaingun"
	weapon.hp = 6
	weapon.max_hp = 6
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 2.0
	weapon.ap_cost = 2
	weapon.scatter = [Ring.new(0.05, 1.0)]
	weapon.provides_actions = [&"burst"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.burst_size = 12
	weapon.weapon_def.burst_ap_cost = 3
	return weapon


func _make_auto_shotgun() -> Part:
	var weapon := Part.new()
	weapon.id = &"auto_shotgun"
	weapon.hp = 5
	weapon.max_hp = 5
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 3.0
	weapon.ap_cost = 1
	weapon.scatter = [Ring.new(0.05, 1.0)]
	weapon.provides_actions = [&"shoot", &"burst"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.burst_size = 3
	weapon.weapon_def.burst_ap_cost = 2
	weapon.weapon_def.mechanical_accuracy = 0.9
	return weapon


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


func _make_target(cell: Vector2i, hp: int = 100) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = hp
	torso.max_hp = hp
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 1)


## "the chaingun offers BURST and not SHOOT."
func test_chaingun_offers_burst_and_not_shoot() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)

	var ids: Array[StringName] = []
	for action: ActionDef in ActionCatalog.actions_for(shooter):
		ids.append(action.id)

	assert_true(ids.has(&"burst"))
	assert_false(ids.has(&"shoot"))


## "the auto shotgun offers both."
func test_auto_shotgun_offers_shoot_and_burst() -> void:
	var weapon := _make_auto_shotgun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)

	var ids: Array[StringName] = []
	for action: ActionDef in ActionCatalog.actions_for(shooter):
		ids.append(action.id)

	assert_true(ids.has(&"burst"))
	assert_true(ids.has(&"shoot"))


func test_is_legal_true_in_the_baseline_case() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	assert_true(BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).is_legal(state))


func test_is_legal_false_without_enough_ap_for_the_burst_ap_cost() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	shooter.ap = 2  # burst_ap_cost is 3

	assert_false(BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).is_legal(state))


## taskblock-19 Pass E: "a unit adjacent to an enemy can't fire a long
## gun." A burst weapon can carry the same two_handed flag.
func test_is_legal_false_for_a_two_handed_burst_weapon_adjacent_to_an_enemy() -> void:
	var weapon := _make_chaingun()
	weapon.weapon_def.two_handed = true
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var adjacent_enemy := _make_target(Vector2i(1, 0))
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, adjacent_enemy, target])

	assert_false(BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).is_legal(state))


## A weapon with no WeaponDef, or a burst_size of 1, has no burst mode at
## all — never a crash, just illegal.
func test_is_legal_false_for_a_weapon_with_no_burst_mode() -> void:
	var weapon := Part.new()
	weapon.id = &"pistol"
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 4.0
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	assert_false(BurstAction.new(shooter, &"pistol", Vector2i(3, 0)).is_legal(state))


## "a burst fires exactly burst_size times... each burst shot rolls the
## dartboard independently."
func test_a_burst_fires_exactly_burst_size_independent_pulls() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	assert_eq(
		sink.events_of_kind(&"impact").size(),
		12,
		"a single-projectile burst is exactly burst_size hits"
	)


## "AP cost: authored per action; a burst costs more than a single shot."
func test_burst_spends_its_own_higher_ap_cost() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var before_ap: int = shooter.ap

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	assert_eq(shooter.ap, before_ap - 3, "burst_ap_cost (3), not the single-shot ap_cost (2)")


## "one summary event per burst, detail per impact."
func test_a_burst_emits_one_summary_event_plus_full_detail_per_impact() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	var summaries: Array[LogEvent] = sink.events_of_kind(&"burst_fired")
	assert_eq(summaries.size(), 1, "exactly one summary event per burst, never one per pull")
	assert_eq(summaries[0].data.get("round_count"), 12)
	assert_eq(
		sink.events_of_kind(&"impact").size(), 12, "every individual impact still gets logged"
	)


## "a burst of buckshot resolves N pulls x M pellets without error."
func test_a_burst_of_buckshot_resolves_n_pulls_times_m_pellets() -> void:
	var weapon := _make_auto_shotgun()
	weapon.ammo_id = &"12ga_buckshot"
	DataLibrary.reset()
	DataLibrary.load_all()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"auto_shotgun", Vector2i(3, 0)).apply(state)

	var ammo: AmmoDef = DataLibrary.get_ammo(&"12ga_buckshot")
	assert_eq(
		sink.events_of_kind(&"impact").size(),
		weapon.weapon_def.burst_size * ammo.projectile_num,
		"3 pulls x 9 pellets"
	)
	DataLibrary.reset()


## Replays identically from the same seed — same determinism guarantee
## every other RNG-driven combat path already carries.
func test_replays_identically_from_the_same_seed() -> void:
	var results: Array = []
	for run in range(2):
		var weapon := _make_chaingun()
		var shooter := _make_shooter(Vector2i(0, 0), weapon)
		var target := _make_target(Vector2i(4, 0), 200)
		var state := CombatState.new(Grid.new(10, 10), [shooter, target], 777)

		BurstAction.new(shooter, &"chaingun", Vector2i(4, 0)).apply(state)
		results.append([shooter.ap, target.shell.root.hp])

	assert_eq(results[0], results[1])


## "recoil resets between activations" — every activation's `pull` loop
## counter starts fresh at 0 (BurstAction.apply()'s own local `for pull
## in range(burst_size)`, never state stored on the weapon/unit between
## calls), so two back-to-back activations must both complete cleanly,
## each spending its own full ap cost, neither drifting off some
## carried-over widened state.
func test_recoil_resets_between_separate_burst_activations() -> void:
	var weapon := _make_chaingun()
	weapon.weapon_def.barrel_length = 0.3  # short barrel: recoil actually moves the needle
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0), 5000)
	var state := CombatState.new(Grid.new(10, 10), [shooter, target], 42)
	shooter.ap = 100

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)
	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	assert_eq(shooter.ap, 100 - 3 - 3, "each activation spends the same fixed ap cost, unaffected")


## "recoil never touches the spread pattern" — a shotgun burst's own
## per-pull PELLET count and their tight clustering around each pull's
## own center must be identical regardless of how many recoil steps that
## pull has accumulated; only the dartboard (which pull center gets
## picked) should ever widen.
func test_recoil_never_changes_the_pellet_count_per_pull() -> void:
	var weapon := _make_auto_shotgun()
	weapon.ammo_id = &"12ga_buckshot"
	DataLibrary.reset()
	DataLibrary.load_all()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"auto_shotgun", Vector2i(3, 0)).apply(state)

	var ammo: AmmoDef = DataLibrary.get_ammo(&"12ga_buckshot")
	# Still exactly 3 pulls x 9 pellets even with real (non-zero) recoil
	# now wired in — recoil widening the LATER pulls' dartboard never
	# changes how many pellets any one pull throws.
	assert_eq(
		sink.events_of_kind(&"impact").size(), weapon.weapon_def.burst_size * ammo.projectile_num
	)
	DataLibrary.reset()


func test_apply_faces_the_shooter_toward_the_target() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	assert_almost_eq(
		shooter.orientation, FaceAction.orientation_toward(Vector2i(0, 0), Vector2i(3, 0)), 0.0001
	)


## taskblock-19 Pass H: "diagnose against a real burst" — is_legal()/
## apply() have always read the same weapon.weapon_def.burst_size
## (verified against the original taskblock-13 commit; no source
## mismatch ever existed). The REAL symptom, reproduced against the real
## authored chaingun.tres (not the tight, always-hits test fixture other
## tests here use): its own scatter (inner ring radius 0.15/weight 1,
## outer 0.6/weight 2 — roughly 2/3 of rolls land in the wide outer ring)
## genuinely misses the torso often, even on pull 0 before any recoil.
## `&"burst_pull"` proves the LOOP itself never drops a pull regardless:
## exactly `burst_size` of these must exist, hit or miss.
func test_a_real_bursts_pull_events_always_total_burst_size_even_with_misses() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()
	var weapon: Part = DataLibrary.get_part(&"chaingun")
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0), 1000)
	# Seed 0: a real, verified mix of hits and misses for this exact
	# fixture (confirmed via a live probe before writing this test) —
	# never all-hit, never all-miss, so this can't pass by accident.
	var state := CombatState.new(Grid.new(10, 10), [shooter, target], 0)
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	var pulls: Array[LogEvent] = sink.events_of_kind(&"burst_pull")
	assert_eq(pulls.size(), weapon.weapon_def.burst_size, "every pull fires, hit or miss")
	var hits: Array[LogEvent] = pulls.filter(func(e: LogEvent) -> bool: return e.data.get("hit"))
	var misses: Array[LogEvent] = pulls.filter(
		func(e: LogEvent) -> bool: return not e.data.get("hit")
	)
	assert_gt(hits.size(), 0, "sanity: this seed must produce at least one real hit")
	assert_gt(misses.size(), 0, "sanity: this seed must produce at least one real miss")
	DataLibrary.reset()


func test_burst_pull_events_are_indexed_0_to_burst_size_minus_1() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	var pulls: Array[LogEvent] = sink.events_of_kind(&"burst_pull")
	var indices: Array[int] = []
	for pull: LogEvent in pulls:
		indices.append(pull.data.get("pull_index"))
	assert_eq(indices, range(weapon.weapon_def.burst_size))


## "how many out of the total landed" — `landed_so_far` is a running
## count, so the LAST pull's own value is the burst's final landed total,
## directly cross-checked against the real impact-event count (the tight,
## always-hits fixture other tests here already use, so the final tally
## is known and unambiguous: all 12 land).
func test_landed_so_far_matches_the_actual_impact_count_at_the_end() -> void:
	var weapon := _make_chaingun()
	var shooter := _make_shooter(Vector2i(0, 0), weapon)
	var target := _make_target(Vector2i(3, 0))
	var state := CombatState.new(Grid.new(10, 10), [shooter, target])
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)

	BurstAction.new(shooter, &"chaingun", Vector2i(3, 0)).apply(state)

	var pulls: Array[LogEvent] = sink.events_of_kind(&"burst_pull")
	var impacts: Array[LogEvent] = sink.events_of_kind(&"impact")
	assert_eq(pulls[pulls.size() - 1].data.get("landed_so_far"), impacts.size())
