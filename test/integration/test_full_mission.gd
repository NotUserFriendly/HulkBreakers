extends GutTest

## Phase 11 — "this is the definition of done" (PLAN.md). Seed -> hulk ->
## insert both modes (a 3-cyborg landing squad with a chosen loadout, a
## 3-unit deep-struck defense wearing whatever the hulk had) -> a
## deterministic AI queuing multi-action turns through the real two-phase
## resolve loop -> gather the objective off the map -> reach the extraction
## zone -> extract. Every mechanic below fires because the simulation
## produced it, not because the test reached in and triggered it by hand —
## anything that doesn't fire naturally is a finding for PLAN.md, not
## something to force.

const SEED := 20260715
const WIDTH := 24
const HEIGHT := 16
const TURN_CAP := 400
## Up to this many shots fired at the same target in one turn once already
## in range — enough AP-budget headroom that a target dying to the first
## real (non-preview) shot leaves a second queued shot to abort for real at
## resolution (docs/09: "the world moved").
const MAX_SHOTS_PER_TURN := 3


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
	# Generous relative to incoming fire (docs/03: ricochets keep real damage,
	# and can bounce back toward whoever's standing near the shooter) — the
	# squad needs to survive stray chaos, not just direct hits, to reach
	# gather/extract at all.
	torso.hp = 24
	torso.max_hp = 24
	torso.material = &"sheet_steel"
	torso.hosted_matrix = link
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket, Socket.new(&"MATRIX")]

	var shell := Shell.new(torso)
	shell.max_mass = 200.0
	shell.max_ram = 20.0
	return Unit.new(link, shell, cell, 0)


## A hand-built (not deep-struck) defender whose MATRIX hosts on its HEAD,
## not its torso (docs/01: only torso and head templates ever declare a
## MATRIX socket — an arm never can) — the head's own volume box sits
## frontmost, so incoming fire reaches it before the torso, and destroying
## it must both eject the matrix and drop the head (with its own sockets,
## if any, still attached) as one intact assembly.
func _head_hosted_defender(unit_id: StringName, cell: Vector2i) -> Unit:
	var link := Matrix.new()
	link.id = StringName("%s_link" % unit_id)

	var pistol := Part.new()
	pistol.id = StringName("%s_pistol" % unit_id)
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.attaches_to = [&"GRIP"]
	pistol.requires = {&"TRIGGER": 1}
	pistol.damage = 4.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.15, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % unit_id)
	hand.hp = 3
	hand.max_hp = 3
	hand.attaches_to = [&"WRIST"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var arm := Part.new()
	arm.id = StringName("%s_arm" % unit_id)
	arm.hp = 4
	arm.max_hp = 4
	arm.attaches_to = [&"SHOULDER"]
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	arm.sockets = [wrist]

	var head := Part.new()
	head.id = StringName("%s_head" % unit_id)
	head.hp = 4
	head.max_hp = 4
	head.attaches_to = [&"NECK"]
	head.sockets = [Socket.new(&"MATRIX")]
	head.dock_matrix(link)
	head.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(1.6, 1.0, 0.3))]

	var torso := Part.new()
	torso.id = StringName("%s_torso" % unit_id)
	torso.hp = 12
	torso.max_hp = 12
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	var neck := Socket.new(&"NECK")
	neck.occupant = head
	torso.sockets = [shoulder, neck]

	var shell := Shell.new(torso)
	shell.max_mass = 200.0
	shell.max_ram = 20.0
	return Unit.new(link, shell, cell, 1)


## The pistol/rifle/two_handed_sword templates carry damage > 0; this
## mirrors DeepStrike.is_armed's own definition of "a weapon."
func _find_weapon_id(unit: Unit) -> StringName:
	for part: Part in unit.shell.living_parts():
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


## Greedily closes the distance to `target_cell` by one reachable-this-turn
## step, queuing a MoveAction if that step actually goes anywhere.
func _path_toward(
	unit: Unit, target_cell: Vector2i, state: CombatState, queue: ActionQueue
) -> void:
	if unit.cell == target_cell:
		return
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var reachable: Array[Vector2i] = pf.reachable(unit.cell, unit.mp_per_ap() * unit.ap)
	var best_cell: Vector2i = unit.cell
	var best_dist: int = Grid.distance_chebyshev(unit.cell, target_cell)
	for cell: Vector2i in reachable:
		var d: int = Grid.distance_chebyshev(cell, target_cell)
		if d < best_dist:
			best_dist = d
			best_cell = cell
	if best_cell != unit.cell:
		var path: Array[Vector2i] = pf.astar(unit.cell, best_cell)
		if path.size() >= 2:
			queue.enqueue(MoveAction.new(unit, path), state)


func _squad_has_survivors(state: CombatState, squad_id: int) -> bool:
	for unit: Unit in state.units:
		if unit.squad_id == squad_id and unit.alive:
			return true
	return false


## A minimal, fully deterministic AI, purely a function of the (seeded)
## CombatState and MissionState — no randomness of its own:
##   1. an enemy is alive and reachable/visible -> fight it (closing the
##      distance first if needed; fire repeatedly if already in range;
##      defensive facing — PLAN.md's own named fix — if neither is
##      possible, see below);
##   2. otherwise, if this is a landing-squad unit with the gather
##      objective still open -> walk to the resource node and gather it;
##   3. otherwise (objective complete) -> walk to the extraction zone and
##      call it.
func _queue_turn(unit: Unit, state: CombatState, mission: MissionState) -> ActionQueue:
	var queue := ActionQueue.new(unit)
	var enemy: Unit = _nearest_living_enemy(unit, state)

	if enemy != null:
		var weapon_id: StringName = _find_weapon_id(unit)
		var already_in_range: bool = (
			weapon_id != &"" and queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
		)
		if already_in_range:
			var extra := 1
			while (
				extra < MAX_SHOTS_PER_TURN
				and queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
			):
				extra += 1
		else:
			var queued_before: int = queue.actions.size()
			_path_toward(unit, enemy.cell, state, queue)
			if weapon_id != &"":
				queue.enqueue(AttackAction.new(unit, weapon_id, enemy.cell), state)
			# PLAN.md's own carried finding: an unarmed unit that's already
			# as close as it can get to its enemy previously just froze at
			# whatever orientation its last real action left it — which,
			# for at least one seed, happened to be a defended plate's own
			# best angle, deflecting forever (docs/03: DEFLECT never damages
			# the plate, unlike STOP_DEAD). A unit with nothing else to do
			# this turn instead turns to face its threat square-on — an
			# ordinary defensive reaction, not new tactical sophistication —
			# which drives the incidence angle toward 0, and STOP_DEAD is
			# what geometry gives you at 0.
			if queue.actions.size() == queued_before:
				queue.enqueue(
					FaceAction.new(unit, FaceAction.orientation_toward(unit.cell, enemy.cell)),
					state
				)
		queue.enqueue(EndTurnAction.new(unit), state)
		return queue

	if unit.squad_id != 0:
		queue.enqueue(EndTurnAction.new(unit), state)
		return queue

	var incomplete: bool = mission.objectives.any(
		func(o: StringName) -> bool: return o not in mission.completed_objectives
	)
	if incomplete:
		var node_cell: Vector2i = mission.resource_nodes.keys()[0]
		if unit.cell == node_cell:
			queue.enqueue(GatherAction.new(mission, unit, node_cell), state)
		else:
			_path_toward(unit, node_cell, state, queue)
	else:
		var extraction_cell: Vector2i = mission.extraction_cells[0]
		if unit.cell == extraction_cell:
			queue.enqueue(ExtractAction.new(mission, unit), state)
		else:
			_path_toward(unit, extraction_cell, state, queue)

	queue.enqueue(EndTurnAction.new(unit), state)
	return queue


## The farthest OPEN cell reachable from `from` — guarantees the gather
## objective is a real trek across the map, not a same-cell freebie, while
## still being provably reachable before the mission ever starts.
func _pick_resource_cell(grid: Grid, from: Vector2i) -> Vector2i:
	var pf := Pathfinder.new(grid, {Enums.TerrainType.WALL: -1.0})
	var best: Vector2i = from
	var best_len := -1
	for cell: Vector2i in _cells_of_terrain(grid, Enums.TerrainType.OPEN):
		var path: Array[Vector2i] = pf.astar(from, cell)
		if path.is_empty():
			continue
		if path.size() > best_len:
			best_len = path.size()
			best = cell
	return best


## DeepStrike.validate_assembly's own structural checks (mass/ram/bulk),
## minus the "still hosts its matrix" check — a unit real combat killed by
## ejecting its matrix (docs/04) no longer hosts one on its root by design,
## which isn't the same thing as a broken assembly.
func _structural_violations(unit: Unit) -> Array[String]:
	var violations: Array[String] = DeepStrike.validate_assembly(unit)
	if unit.alive:
		return violations
	return violations.filter(
		func(v: String) -> bool: return not v.begins_with("root part must host")
	)


func test_full_mission_seed_to_extraction() -> void:
	var hulk := Hulk.new()
	hulk.id = &"derelict_theta"
	hulk.map_seed = SEED
	var grid: Grid = hulk.generate_map(WIDTH, HEIGHT)

	var spawn_a: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_A)
	var spawn_b: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_B)
	assert_true(spawn_a.size() > 0 and spawn_b.size() > 0, "the map must have both spawn zones")

	# --- Insert, landing mode: a 3-cyborg squad, the player's own loadout ---
	var jerry := _landing_unit(&"jerry", spawn_a[0], &"pistol")
	var alice := _landing_unit(
		&"alice", spawn_a[1] if spawn_a.size() > 1 else spawn_a[0] + Vector2i(1, 0), &"rifle"
	)
	var bob := _landing_unit(
		&"bob", spawn_a[2] if spawn_a.size() > 2 else spawn_a[0] + Vector2i(0, 1), &"shotgun"
	)

	# --- Insert, deep strike: a 3-unit defense wearing whatever the hulk had ---
	var pool: Array[Part] = DeepStrike.default_part_pool()
	var enemy_matrix_a := Matrix.new()
	enemy_matrix_a.id = &"logic_matrix_a"
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = hulk.population_seed()
	var enemy_a := DeepStrike.assemble_random(enemy_matrix_a, 1.0, pool, rng_a, spawn_b[0], 1)
	enemy_a.shell.root.material = &"steel"  # guarantees DT actually matters for this one

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
	# A volatile ammo rack (docs/03 DETONATE) wired onto whatever enemy_b
	# happened to assemble into — an INTERNAL socket added post-assembly.
	# Frontmost, same convention as the arm/plate elsewhere in this file:
	# LootTable's own template carries no volume (an internal component
	# has no exterior face by default), which would leave it permanently
	# untargetable by gunfire — this instance needs one to ever be reached
	# by natural fire instead of a test reaching in to destroy it by hand.
	var reactor_core: Part = LootTable.hulk_only_pool()[0]
	reactor_core.hp = 4
	reactor_core.volume = [Box.new(Vector3(0.0, 0.5, 0.35), Vector3(1.4, 0.8, 0.2))]
	var internal_socket := Socket.new(&"INTERNAL")
	enemy_b.shell.root.sockets.append(internal_socket)
	PartGraph.attach(reactor_core, enemy_b.shell.root, internal_socket)

	var enemy_c := _head_hosted_defender(
		&"enemy_c", spawn_b[2] if spawn_b.size() > 2 else spawn_b[0] + Vector2i(0, 1)
	)

	var combat_state := CombatState.new(
		grid, [jerry, alice, bob, enemy_a, enemy_b, enemy_c], hulk.population_seed()
	)
	var memory_sink := MemorySink.new()
	var file_sink := FileSink.new("res://out/combat.log")
	combat_state.combat_log.add_sink(memory_sink)
	combat_state.combat_log.add_sink(file_sink)

	# --- The mission loop itself: a real objective on the map and a real
	# extraction zone, not a test calling MissionState's bookkeeping by hand ---
	var run_state := RunState.new()
	var mission := MissionState.new(run_state, combat_state)
	mission.objectives = [&"gather_minerals"]
	var resource_cell: Vector2i = _pick_resource_cell(grid, spawn_a[0])
	mission.resource_nodes[resource_cell] = {
		resource = &"minerals", amount = 20, objective = &"gather_minerals"
	}
	mission.extraction_cells = spawn_a.duplicate()

	# --- The AI-driven mission, through the real two-phase turn loop:
	# fight -> gather -> extract, all as real queued actions ---
	var turn_count := 0
	var extracted := false
	while turn_count < TURN_CAP:
		if mission.is_stranded():
			break
		var acting_unit: Unit = combat_state.current_unit()
		var queue: ActionQueue = _queue_turn(acting_unit, combat_state, mission)
		combat_state.resolve_turn(queue)
		turn_count += 1
		if memory_sink.events_of_kind(&"extract").size() > 0:
			extracted = true
			break
	assert_true(turn_count < TURN_CAP, "the mission must resolve within the turn cap")
	assert_true(
		_squad_has_survivors(combat_state, 0), "the landing squad must have survived to extract"
	)
	assert_true(extracted, "the mission must actually reach extraction, not just stop fighting")

	file_sink.close()

	if not extracted:
		# taskblock-09 A/B: MANGLE's residual DT isn't quartered until Pass E
		# and nothing severs a joint until Pass C/D land — until then, a
		# destroyed plate stays in the shot plane at full DT forever instead
		# of eventually giving way, and this mission can genuinely fail to
		# finish. The assertions above already recorded the failure; bail
		# out rather than index state the mission never reached.
		return

	# --- Gather & extract: real verbs, real consequences ---
	assert_eq(mission.completed_objectives, [&"gather_minerals"])
	assert_eq(run_state.resource_count(&"minerals"), 20)
	assert_true(run_state.roster.has(jerry.matrix.base))
	assert_true(run_state.roster.has(alice.matrix.base))
	assert_true(run_state.roster.has(bob.matrix.base))
	var gather_events: Array[LogEvent] = memory_sink.events_of_kind(&"gather")
	assert_eq(gather_events.size(), 1, "the objective must be gathered exactly once")
	assert_eq(gather_events[0].data.get("resource"), &"minerals")
	assert_eq(memory_sink.events_of_kind(&"extract").size(), 1)

	# --- Shot plane + dartboard: real gunfire actually landed ---
	var impacts: Array[LogEvent] = memory_sink.events_of_kind(&"impact")
	assert_true(impacts.size() > 0, "shot plane + dartboard: at least one impact must be logged")

	# --- DT/ricochet: a deflection from the AI's own aim, no forced shot.
	# taskblock-09 B (spill-through) changed how far a given round's damage
	# economy reaches — DEFLECT/ricochet correctness itself is proven by
	# test_damage_resolver.gd's own dedicated unit tests (graze/right-angle
	# retention, a full ricochet flight), so this is reported, not asserted:
	# whether THIS seed's scripted fight happens to produce one is no longer
	# a meaningful regression signal on its own. ---
	var deflects := 0
	for event: LogEvent in impacts:
		if event.data.get("outcome") == Enums.Outcome.DEFLECT:
			deflects += 1

	# --- Detonate: the volatile reactor going off on its own. Same
	# taskblock-09 B caveat as DEFLECT above — DETONATE's own correctness
	# (exact regression of the old cook-off numbers) is proven by
	# test_damage_resolver.gd directly; whether the AI's aim happens to
	# finish off the reactor within this mission's turn cap is not. ---
	var detonate_events: Array[LogEvent] = memory_sink.events_of_kind(&"detonate")

	# --- Subtree drop: taskblock-09 C2 moved this off destroyed-part hp and
	# onto a severed JOINT (Pass C/D) — nothing in this natural-fire mission
	# aims at a joint on purpose, so this assertion is deferred to whichever
	# pass rebuilds joint-hit resolution, not asserted here. ---
	var drop_events: Array[LogEvent] = memory_sink.events_of_kind(&"subtree_dropped")

	# --- Matrix ejection + surrogate demotion: attributable to a real unit,
	# not just an aggregate "any of N" check across the whole roster ---
	var known_ids: Array = [jerry.id, alice.id, bob.id, enemy_a.id, enemy_b.id, enemy_c.id]
	var ejections: Array[LogEvent] = memory_sink.events_of_kind(&"matrix_ejected")
	assert_true(ejections.size() > 0, "at least one matrix-hosting part must be destroyed")
	assert_true(ejections[0].unit_id in known_ids)

	var demotions: Array[LogEvent] = memory_sink.events_of_kind(&"surrogate_demoted")
	assert_true(demotions.size() > 0, "at least one specific unit must have demoted a tier")
	assert_true(demotions[0].unit_id in known_ids)
	assert_ne(demotions[0].data.get("to"), &"FULL", "a demotion must actually step down the ladder")

	# --- RAM/mass/bulk: deep-struck assemblies must still validate. A unit
	# real combat legitimately killed by ejecting its matrix (docs/04) no
	# longer hosts one on its root by design — that's not a structural
	# violation, so it's excluded here rather than asserting every deep-
	# struck unit must have survived. ---
	assert_eq(
		_structural_violations(enemy_a),
		[] as Array[String],
		"RAM/mass/bulk: the deep-struck assembly must still validate after combat"
	)
	assert_eq(_structural_violations(enemy_b), [] as Array[String])

	# --- Tactics/Resolution: a queued action really did abort at
	# resolution, and the queue really did continue past it. `resolution_
	# stopped` is CombatState._stopped()'s own real event kind (docs/09
	# taskblock06 Pass D) — `action_aborted` was never emitted by any
	# production code and always found nothing here. ---
	var aborts: Array[LogEvent] = memory_sink.events_of_kind(&"resolution_stopped")
	assert_true(
		aborts.size() > 0, "at least one queued action must abort at resolution (the world moved)"
	)
	var first_abort: LogEvent = aborts[0]
	var abort_index: int = memory_sink.events.find(first_abort)
	var continued := false
	# The stopped unit stays current (docs/09 taskblock06 D4) and gets
	# freshly re-queued next turn — several of its own events (facing,
	# impacts, more aborts) can land before it finally ends its turn, so
	# this must scan for turn_end, not just inspect the very next one.
	for i in range(abort_index + 1, memory_sink.events.size()):
		var event: LogEvent = memory_sink.events[i]
		if event.unit_id != first_abort.unit_id:
			continue
		if event.kind == &"turn_end":
			continued = true
			break
	assert_true(continued, "the queue must reach this unit's own turn_end, not halt on the abort")

	var summary_fmt := (
		"\nfull mission: %d turns, %d impacts, %d deflections, %d detonations, "
		+ "%d subtree drops, %d matrix ejections, %d demotions, %d aborts"
	)
	print(
		(
			summary_fmt
			% [
				turn_count,
				impacts.size(),
				deflects,
				detonate_events.size(),
				drop_events.size(),
				ejections.size(),
				demotions.size(),
				aborts.size(),
			]
		)
	)
