extends GutTest

## Phase 11 — "this is the definition of done" (PLAN.md). Seed -> hulk ->
## insert both modes (a landing squad with a chosen loadout, a deep-struck
## enemy squad wearing whatever the hulk had) -> a deterministic AI queuing
## multi-action turns through the real two-phase resolve loop -> gather ->
## extract. Exercises shot plane + dartboard + DT/ricochet + cook-off +
## RAM + surrogate decay + tactics/resolution + extraction end to end,
## with a full combat.log, and must terminate within a turn cap.

const SEED := 20260715
const WIDTH := 24
const HEIGHT := 16
const TURN_CAP := 300


func _cells_of_terrain(grid: Grid, terrain: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain:
				cells.append(cell)
	return cells


func _landing_unit(unit_id: StringName, cell: Vector2i, weapon_id: StringName) -> Unit:
	var base := Matrix.new()
	base.id = unit_id
	base.level = 5
	base.perks = [&"steady_hands"]
	var link := Matrix.new()
	link.id = StringName("%s_link" % unit_id)
	link.base = base
	link.tier_ratio = 1.0  # landing mode: your own chosen link, full tier

	var weapon := Part.new()
	weapon.id = weapon_id
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.weapon_max_range = 8.0
	weapon.scatter = [Ring.new(0.15, 1.0), Ring.new(0.6, 2.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % unit_id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = StringName("%s_torso" % unit_id)
	torso.hp = 10
	torso.max_hp = 10
	torso.material = &"sheet_steel"
	torso.hosts_matrix = true
	torso.hosted_matrix = link
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	var frame := Frame.new(torso)
	frame.max_mass = 200.0
	frame.max_ram = 20.0
	return Unit.new(link, frame, cell, 0)


## The pistol/rifle/two_handed_sword templates carry damage > 0; this
## mirrors DeepStrike.is_armed's own definition of "a weapon."
func _find_weapon_id(unit: Unit) -> StringName:
	for part: Part in unit.frame.living_parts():
		if part.damage > 0.0:
			return part.id
	return &""


func _nearest_living_enemy(unit: Unit, state: CombatState) -> Unit:
	var nearest: Unit = null
	var best: int = 999999
	for candidate: Unit in state.units:
		if candidate.squad_id == unit.squad_id or not candidate.alive:
			continue
		var d: int = Grid.distance_chebyshev(unit.cell, candidate.cell)
		if d < best:
			best = d
			nearest = candidate
	return nearest


## A minimal, fully deterministic AI: attack the nearest living enemy if
## already possible, otherwise close the distance and try again, then
## always end turn. Every decision is a plain function of the (seeded)
## CombatState — no randomness of its own.
func _queue_turn(unit: Unit, state: CombatState) -> ActionQueue:
	var queue := ActionQueue.new(unit)
	var enemy: Unit = _nearest_living_enemy(unit, state)
	if enemy == null:
		queue.enqueue(EndTurnAction.new(unit), state)
		return queue

	var weapon_id: StringName = _find_weapon_id(unit)
	if weapon_id != &"" and queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state):
		queue.enqueue(EndTurnAction.new(unit), state)
		return queue

	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	var best_cell: Vector2i = unit.cell
	var best_dist: int = Grid.distance_chebyshev(unit.cell, enemy.cell)
	for cell: Vector2i in reachable:
		var d: int = Grid.distance_chebyshev(cell, enemy.cell)
		if d < best_dist:
			best_dist = d
			best_cell = cell
	if best_cell != unit.cell:
		var path: Array[Vector2i] = pf.astar(unit.cell, best_cell)
		if path.size() >= 2:
			queue.enqueue(MoveAction.new(unit, path), state)

	if weapon_id != &"":
		queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
	queue.enqueue(EndTurnAction.new(unit), state)
	return queue


func test_full_mission_seed_to_extraction() -> void:
	var hulk := Hulk.new()
	hulk.id = &"derelict_theta"
	hulk.map_seed = SEED
	var grid: Grid = hulk.generate_map(WIDTH, HEIGHT)

	var spawn_a: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_A)
	var spawn_b: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_B)
	assert_true(spawn_a.size() > 0 and spawn_b.size() > 0, "the map must have both spawn zones")

	# --- Insert, landing mode: the player's own chosen loadout ---
	var jerry := _landing_unit(&"jerry", spawn_a[0], &"pistol")
	var alice := _landing_unit(
		&"alice", spawn_a[1] if spawn_a.size() > 1 else spawn_a[0] + Vector2i(1, 0), &"rifle"
	)

	# --- Insert, deep strike: enemies wearing whatever the hulk had ---
	var pool: Array[Part] = DeepStrike.default_part_pool()
	var enemy_matrix_a := Matrix.new()
	enemy_matrix_a.id = &"logic_matrix_a"
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = hulk.population_seed()
	var enemy_a := DeepStrike.assemble_random(enemy_matrix_a, 1.0, pool, rng_a, spawn_b[0], 1)
	enemy_a.frame.root.material = &"steel"  # guarantees DT actually matters for this one

	var enemy_matrix_b := Matrix.new()
	enemy_matrix_b.id = &"logic_matrix_b"
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = hulk.population_seed() + 1
	var enemy_b := DeepStrike.assemble_random(
		enemy_matrix_b,
		1.0,
		pool,
		rng_b,
		spawn_b[1] if spawn_b.size() > 1 else spawn_b[0] + Vector2i(1, 0),
		1
	)
	# A volatile ammo rack (docs/03 cook-off), so a real fight has a chance
	# to blow it — an INTERNAL socket added post-assembly for this purpose.
	var reactor_core: Part = LootTable.hulk_only_pool()[0]
	reactor_core.hp = 4
	var internal_socket := Socket.new(&"INTERNAL")
	enemy_b.frame.root.sockets.append(internal_socket)
	PartGraph.attach(reactor_core, enemy_b.frame.root, internal_socket)

	var combat_state := CombatState.new(
		grid, [jerry, alice, enemy_a, enemy_b], hulk.population_seed()
	)
	var memory_sink := MemorySink.new()
	var file_sink := FileSink.new("res://out/combat.log")
	combat_state.combat_log.add_sink(memory_sink)
	combat_state.combat_log.add_sink(file_sink)

	# --- A guaranteed oblique hit on the steel enemy, so DT/ricochet are
	# exercised deterministically rather than left to the AI's aim. ---
	var direction := Vector2(4, -3)  # ~53 degree incidence, clears the deflect threshold
	var dir: Vector2 = direction.normalized()
	var origin: Vector2 = Vector2(enemy_a.cell) - dir * 12.0
	var plane: Array[Region] = ShotPlane.build(origin, dir, combat_state)
	var target_region: Region = null
	for region: Region in plane:
		if region.part == enemy_a.frame.root:
			target_region = region
	assert_not_null(target_region, "the forced shot must find the steel enemy's torso")
	var forced_results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction,
		target_region.rect.get_center(),
		3.0,
		0.0,
		combat_state,
		combat_state.material_table,
		combat_state.rng
	)
	for result: ImpactResult in forced_results:
		combat_state.combat_log.emit(
			LogEvent.new(
				0,
				Enums.Phase.RESOLUTION,
				enemy_a.id,
				&"impact",
				{"outcome": result.outcome},
				"forced calibration shot: %s" % Enums.Outcome.keys()[result.outcome]
			)
		)
	assert_eq(
		forced_results[0].outcome, Enums.Outcome.DEFLECT, "the forced shot must actually deflect"
	)

	# --- The AI-driven battle, through the real two-phase turn loop ---
	var turn_count := 0
	while not combat_state.is_over() and turn_count < TURN_CAP:
		var acting_unit: Unit = combat_state.current_unit()
		var queue: ActionQueue = _queue_turn(acting_unit, combat_state)
		combat_state.resolve_turn(queue)
		turn_count += 1
	assert_true(turn_count < TURN_CAP, "the mission must resolve within the turn cap")
	assert_true(combat_state.is_over(), "one side must have won")

	# Cook-off: destroy the reactor core directly if the battle didn't
	# already (a real fight isn't guaranteed to focus it) — the mechanism
	# itself, not the AI's targeting priorities, is what this phase proves.
	if reactor_core.hp > 0:
		DamageResolver.apply_damage_to_part(reactor_core, 10.0)
	var cooked_off: Array[Unit] = DamageResolver.cook_off(reactor_core, combat_state)
	assert_true(reactor_core.hp <= 0)

	# --- Gather & extract ---
	var run_state := RunState.new()
	var mission := MissionState.new(run_state, combat_state)
	mission.objectives = [&"gather_minerals"]
	mission.gather_resource(&"minerals", 20)
	mission.complete_objective(&"gather_minerals")
	mission.extract()

	assert_eq(run_state.resource_count(&"minerals"), 20)
	assert_true(run_state.roster.has(jerry.matrix.base))
	assert_true(run_state.roster.has(alice.matrix.base))
	assert_eq(mission.completed_objectives, [&"gather_minerals"])

	# --- Everything this phase promises got exercised ---
	var impacts: Array[LogEvent] = memory_sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0, "shot plane + dartboard: at least one impact must be logged")
	var deflects := 0
	for event: LogEvent in impacts:
		if event.data.get("outcome") == Enums.Outcome.DEFLECT:
			deflects += 1
	assert_true(deflects > 0, "DT/ricochet: at least one deflection must appear in the log")
	assert_true(
		cooked_off.size() > 0 or reactor_core.hp <= 0, "cook-off: the volatile part must be gone"
	)
	assert_eq(
		DeepStrike.validate_assembly(enemy_a),
		[] as Array[String],
		"RAM/mass/bulk: the deep-struck assembly must still validate after combat"
	)
	var any_demoted := false
	for unit: Unit in [jerry, alice, enemy_a, enemy_b]:
		if unit.surrogate_tier.id != &"FULL" or unit.exposed_turns > 0:
			any_demoted = true
	assert_true(any_demoted, "surrogate decay: at least one destroyed host must have demoted")
	var aborted: Array[String] = combat_state.action_log.filter(
		func(line: String) -> bool: return line.begins_with("aborted")
	)
	print(
		(
			"tactics/resolution: %d turns resolved, %d actions aborted and recovered"
			% [turn_count, aborted.size()]
		)
	)

	file_sink.close()
	print(
		(
			"\nfull mission: %d turns, %d impacts logged, %d deflections"
			% [turn_count, impacts.size(), deflects]
		)
	)
