extends GutTest

## taskblock-18 Pass D: StepOutPlanner (taskblock-19 Pass B: renamed from
## LeanPlanner) — verified geometry throughout: a
## blocker sits directly in front of the unit's own origin cell (so the
## origin itself reads as covered from the target dead ahead), while
## both orthogonal side-step neighbors read as exposed (clear of the
## blocker's own narrow line) — a real, checked fixture, not assumed.


func _blocker() -> Part:
	var blocker := Part.new()
	blocker.id = &"cover"
	blocker.is_destructible = false
	blocker.material = &"hull_plate"
	blocker.volume = [Box.new(Vector3.ZERO, Vector3(0.5, 1.0, 0.5))]
	return blocker


## Mirrors test_overwatch.gd's own _make_overwatcher exactly (WRIST
## socket, not HAND) — UnitGeometry.muzzle_point's own placement math
## depends on that specific socket type; a GRIP-via-HAND unit (this
## file's own _armed_unit convention, used everywhere else here) never
## resolves a real muzzle point, so _torso_visible silently reads false
## for every candidate regardless of geometry, and would_trigger_at can
## never tell two cells apart. Overwatch-exposure fixtures need this one.
func _overwatcher(cell: Vector2i, orientation: float, squad_id: int) -> Unit:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3
	pistol.damage = 5.0
	pistol.ap_cost = 1
	pistol.scatter = [Ring.new(0.1, 1.0)]
	pistol.requires = {&"TRIGGER": 1}
	pistol.weapon_def = WeaponDef.new()
	pistol.weapon_def.max_range = 15.0

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	torso.sockets = [wrist]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)
	unit.orientation = orientation
	return unit


func _armed_unit(cell: Vector2i, squad_id: int, weapon_id: StringName = &"") -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	if weapon_id != &"":
		var weapon := Part.new()
		weapon.id = weapon_id
		weapon.hp = 3
		weapon.max_hp = 3
		weapon.attaches_to = [&"GRIP"]
		weapon.requires = {&"TRIGGER": 1}
		weapon.damage = 5.0
		weapon.ap_cost = 1
		weapon.weapon_def = WeaponDef.new()
		weapon.weapon_def.max_range = 15.0
		weapon.scatter = [Ring.new(0.1, 1.0)]

		var hand := Part.new()
		hand.id = &"hand"
		hand.hp = 4
		hand.max_hp = 4
		hand.attaches_to = [&"HAND"]
		hand.capabilities = [&"TRIGGER"]
		var grip := Socket.new(&"GRIP")
		grip.occupant = weapon
		hand.sockets = [grip]
		var hand_socket := Socket.new(&"HAND")
		hand_socket.occupant = hand
		torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


## Origin (3,0), a blocker immediately in front at (3,1), target dead
## ahead at (3,9). Verified live: origin reads as covered, both orthogonal
## neighbors (4,0)/(2,0) read as exposed, (3,1) itself is the blocker's
## own cell (unwalkable) and out-of-bounds (3,-1) doesn't exist.
func _covered_scene() -> Dictionary:
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(3, 1)] = _blocker()
	var unit := _armed_unit(Vector2i(3, 0), 0, &"rifle")
	var target := _armed_unit(Vector2i(3, 9), 1)
	var state := CombatState.new(grid, [unit, target])
	return {"state": state, "unit": unit, "target": target}


func test_a_step_out_is_legal_when_origin_covered_firing_cell_exposed_and_orthogonal() -> void:
	var scene: Dictionary = _covered_scene()

	assert_true(
		StepOutPlanner.is_legal_step_out(
			scene.state, scene.unit, Vector2i(3, 0), Vector2i(4, 0), scene.target
		)
	)
	assert_true(
		StepOutPlanner.is_legal_step_out(
			scene.state, scene.unit, Vector2i(3, 0), Vector2i(2, 0), scene.target
		)
	)


func test_an_uncovered_origin_makes_the_step_out_illegal() -> void:
	var grid := Grid.new(10, 10)  # no blocker at all
	var unit := _armed_unit(Vector2i(3, 0), 0, &"rifle")
	var target := _armed_unit(Vector2i(3, 9), 1)
	var state := CombatState.new(grid, [unit, target])

	assert_false(
		StepOutPlanner.is_legal_step_out(state, unit, Vector2i(3, 0), Vector2i(4, 0), target),
		"nothing to step back into — no free movement out of an already-open position"
	)


func test_a_firing_cell_that_is_itself_covered_is_illegal() -> void:
	var scene: Dictionary = _covered_scene()

	# The origin cell itself, offered as its own "firing cell" — still
	# covered (nothing changed), so exposing nothing: illegal.
	assert_false(
		StepOutPlanner.is_legal_step_out(
			scene.state, scene.unit, Vector2i(3, 0), Vector2i(3, 0), scene.target
		)
	)


func test_a_diagonal_neighbor_is_never_a_legal_step_out_cell() -> void:
	var scene: Dictionary = _covered_scene()

	# (4, 1) is diagonally adjacent to origin (3, 0) and — verified by the
	# same geometry — clear of the blocker, so ONLY the orthogonal rule
	# excludes it; cover alone would have allowed it.
	assert_eq(
		Grid.distance_manhattan(Vector2i(3, 0), Vector2i(4, 1)), 2, "sanity: a true diagonal step"
	)
	assert_false(
		StepOutPlanner.is_legal_step_out(
			scene.state, scene.unit, Vector2i(3, 0), Vector2i(4, 1), scene.target
		)
	)


func test_candidate_step_out_cells_lists_every_legal_orthogonal_neighbor() -> void:
	var scene: Dictionary = _covered_scene()

	var candidates: Array[Vector2i] = StepOutPlanner.candidate_step_out_cells(
		scene.state, scene.unit, scene.unit.cell, scene.target
	)

	assert_eq(candidates.size(), 2)
	assert_true(Vector2i(4, 0) in candidates)
	assert_true(Vector2i(2, 0) in candidates)
	assert_false(Vector2i(3, 1) in candidates, "the blocker's own cell is unwalkable")


func test_sort_by_safety_prefers_the_cell_with_no_known_overwatch() -> void:
	var scene: Dictionary = _covered_scene()
	# 1 cell south of (4,0), facing south: (4,0) is dead ahead (0 degrees
	# off); (2,0)'s 2-cell lateral offset at this range is a ~63 degree
	# swing, well outside the 45-degree arc.
	var overwatcher := _overwatcher(
		Vector2i(4, 1), BodyProjector.orientation_for(Vector2(0, -1)), 1
	)
	scene.state.add_unit(overwatcher)
	overwatcher.overwatch_weapon_id = &"pistol"

	var exposed_hits: Array[Unit] = Overwatch.would_trigger_at(
		scene.state, scene.unit, Vector2i(4, 0)
	)
	var safe_hits: Array[Unit] = Overwatch.would_trigger_at(scene.state, scene.unit, Vector2i(2, 0))
	assert_true(
		exposed_hits.size() > safe_hits.size(), "sanity: the fixture's own exposure must differ"
	)

	var sorted: Array[Vector2i] = StepOutPlanner.sort_by_safety(
		scene.state, scene.unit, [Vector2i(4, 0), Vector2i(2, 0)]
	)

	assert_eq(sorted[0], Vector2i(2, 0), "the less-exposed cell must sort first")


func test_build_triple_assembles_a_real_move_attack_move_queue() -> void:
	var scene: Dictionary = _covered_scene()
	var queue := ActionQueue.new(scene.unit)

	var ok: bool = StepOutPlanner.build_triple(
		queue,
		scene.state,
		scene.unit,
		&"shoot",
		&"rifle",
		scene.target,
		Vector2i(3, 0),
		Vector2i(4, 0)
	)

	assert_true(ok)
	assert_eq(queue.actions.size(), 3)
	assert_true(queue.actions[0] is MoveAction)
	assert_true(queue.actions[1] is AttackAction)
	assert_true(queue.actions[2] is MoveAction)
	var out_move: MoveAction = queue.actions[0]
	assert_eq(out_move.path[out_move.path.size() - 1], Vector2i(4, 0))
	var back_move: MoveAction = queue.actions[2]
	assert_eq(
		back_move.path[back_move.path.size() - 1], Vector2i(3, 0), "the return leg lands on origin"
	)


## D1: "the return is only free when the origin is a better defensive
## position — never a discount." Both moves must spend real MP/AP, same
## as any other queued move.
func test_the_triple_costs_real_mp_for_both_legs_no_discount() -> void:
	var scene: Dictionary = _covered_scene()
	var unit: Unit = scene.unit
	var starting_mp: float = unit.mp
	var queue := ActionQueue.new(unit)

	assert_true(
		StepOutPlanner.build_triple(
			queue,
			scene.state,
			unit,
			&"shoot",
			&"rifle",
			scene.target,
			Vector2i(3, 0),
			Vector2i(4, 0)
		)
	)
	var preview: CombatState = queue.preview(scene.state)
	var previewed: Unit = preview.find_unit(unit.id)

	# 2 real steps (out + back), 1 MP each, at the same cost any ordinary
	# MoveAction would pay — never refunded or waived.
	assert_almost_eq(previewed.mp, starting_mp - 2.0, 0.0001)


func test_assemble_for_shoot_returns_null_when_already_directly_attackable() -> void:
	var grid := Grid.new(10, 10)  # no cover anywhere
	var unit := _armed_unit(Vector2i(0, 0), 0, &"rifle")
	var target := _armed_unit(Vector2i(5, 0), 1)
	var state := CombatState.new(grid, [unit, target])

	assert_null(StepOutPlanner.assemble_for_shoot(state, unit, &"shoot", &"rifle", target))


func test_assemble_for_shoot_returns_null_when_no_legal_step_out_exists() -> void:
	var grid := Grid.new(10, 10)  # covered origin, but NO cover blocker at all
	var unit := _armed_unit(Vector2i(0, 0), 0, &"rifle")
	# Wall the whole board off from the target so nothing (origin or any
	# neighbor) ever gets LoS to it — no legal step out is even possible.
	for y in range(10):
		grid.set_terrain(Vector2i(5, y), Enums.TerrainType.WALL)
	var target := _armed_unit(Vector2i(9, 0), 1)
	var state := CombatState.new(grid, [unit, target])

	assert_null(StepOutPlanner.assemble_for_shoot(state, unit, &"shoot", &"rifle", target))


func test_assemble_for_shoot_builds_the_triple_via_the_safest_candidate() -> void:
	var scene: Dictionary = _covered_scene()

	var queue: ActionQueue = StepOutPlanner.assemble_for_shoot(
		scene.state, scene.unit, &"shoot", &"rifle", scene.target
	)

	assert_not_null(queue)
	assert_eq(queue.actions.size(), 3)
	var out_move: MoveAction = queue.actions[0]
	var firing_cell: Vector2i = out_move.path[out_move.path.size() - 1]
	assert_true(firing_cell == Vector2i(4, 0) or firing_cell == Vector2i(2, 0))
