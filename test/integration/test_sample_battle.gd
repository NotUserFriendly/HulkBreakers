extends GutTest

## Headless end-to-end proof: seed -> MapGen -> two assembled squads -> a
## simple deterministic AI (approach, attack, swap a destroyed weapon) fights
## until one squad is down. No rendering; progress is logged to stdout via
## print().
##
## Movement always follows a real shortest path (see _try_move_toward) rather
## than greedily chasing straight-line distance, which is a known local-
## minima trap on maze-like maps — deliberate cover-seeking was dropped in
## favor of that correctness guarantee. Cover itself still gets exercised
## naturally: MapGen scatters it across ~8-30% of floor cells, so plenty of
## shots land near/behind it during a normal fight.

const MAP_WIDTH := 24
const MAP_HEIGHT := 18
const TURN_CAP := 500
const BATTLE_SEED := 20260711
const SQUAD_SIZE := 2

# Appendix C's default table, reshuffled so this fight actually exercises
# every mechanic within a bounded number of turns: TORSO is the vital slot
# (its destruction disables the chassis and ejects the matrix), and the
# weapon needs to be squishy and heavily exposed so it reliably breaks and
# forces an in-combat swap: TORSO 35, LEGS 15, L_ARM 10, HEAD 10,
# R_ARM(weapon) 30 -> 100.


func _build_chassis(prefix: String) -> Chassis:
	var chassis := Chassis.new()
	chassis.max_mass = 1000.0  # generous; mass isn't this test's concern

	var torso := Part.new()
	torso.id = StringName("%s_torso" % prefix)
	torso.slot_type = Enums.SlotType.TORSO
	torso.part_type = Enums.PartType.ARMOR
	torso.exposure_weight = 35.0
	torso.hp = 10
	torso.max_hp = 10
	torso.is_container = true  # doubles as the unit's spare-parts container
	torso.max_volume = 10.0
	chassis.install(torso)

	var legs := Part.new()
	legs.id = StringName("%s_legs" % prefix)
	legs.slot_type = Enums.SlotType.LEGS
	legs.part_type = Enums.PartType.MOBILITY
	legs.exposure_weight = 15.0
	legs.hp = 8
	legs.max_hp = 8
	legs.stat_mods = {"agility": 1.0}
	chassis.install(legs)

	var l_arm := Part.new()
	l_arm.id = StringName("%s_l_arm" % prefix)
	l_arm.slot_type = Enums.SlotType.L_ARM
	l_arm.part_type = Enums.PartType.SENSOR
	l_arm.exposure_weight = 10.0
	l_arm.hp = 6
	l_arm.max_hp = 6
	chassis.install(l_arm)

	var head := Part.new()
	head.id = StringName("%s_head" % prefix)
	head.slot_type = Enums.SlotType.HEAD
	head.part_type = Enums.PartType.SENSOR
	head.exposure_weight = 10.0
	head.hp = 6
	head.max_hp = 6
	chassis.install(head)

	var weapon := Part.new()
	weapon.id = StringName("%s_weapon" % prefix)
	weapon.slot_type = Enums.SlotType.R_ARM
	weapon.part_type = Enums.PartType.WEAPON
	weapon.exposure_weight = 30.0  # heavily exposed and squishy: this fight needs weapons to break
	weapon.hp = 3  # one AttackAction hit (DEFAULT_DAMAGE = 3) destroys it
	weapon.max_hp = 3
	chassis.install(weapon)

	var spare_weapon := Part.new()
	spare_weapon.id = StringName("%s_spare_weapon" % prefix)
	spare_weapon.slot_type = Enums.SlotType.R_ARM
	spare_weapon.part_type = Enums.PartType.WEAPON
	spare_weapon.hp = 3
	spare_weapon.max_hp = 3
	spare_weapon.volume = 2.0
	torso.contents.append(spare_weapon)

	return chassis


func _find_cells(grid: Grid, terrain_code: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain_code:
				result.append(cell)
	return result


func _make_squad(spawn_cells: Array[Vector2i], squad_id: int, prefix: String) -> Array[Unit]:
	var units: Array[Unit] = []
	var count: int = mini(SQUAD_SIZE, spawn_cells.size())
	for i in range(count):
		var chassis: Chassis = _build_chassis("%s%d" % [prefix, i])
		var matrix := Matrix.new()
		matrix.id = StringName("%s_matrix_%d" % [prefix, i])
		units.append(Unit.new(matrix, chassis, spawn_cells[i], squad_id))
	return units


func _has_living_weapon(unit: Unit) -> bool:
	for part: Part in unit.chassis.slots.values():
		if part.part_type == Enums.PartType.WEAPON and part.hp > 0:
			return true
	return false


func _pick_best_target(unit: Unit, enemies: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_dist: int = -1
	for enemy: Unit in enemies:
		if not enemy.alive:
			continue
		var d: int = Grid.distance_chebyshev(unit.cell, enemy.cell)
		if best == null or d < best_dist or (d == best_dist and enemy.id < best.id):
			best = enemy
			best_dist = d
	return best


func _try_swap_weapon(state: CombatState, unit: Unit) -> bool:
	var container: Part = null
	for part: Part in unit.chassis.slots.values():
		if part.is_container:
			container = part
			break
	if container == null:
		return false

	for spare: Part in container.contents:
		if (
			spare.slot_type == Enums.SlotType.R_ARM
			and spare.part_type == Enums.PartType.WEAPON
			and spare.hp > 0
		):
			var action := SwapPartAction.new(unit, Enums.SlotType.R_ARM, container, spare)
			if state.try_apply(action):
				print("  unit %d swapped in a spare weapon" % unit.id)
				return true
	return false


## Closes distance to `target` along a real shortest path to a walkable cell
## adjacent to it (target's own cell is occupied, so unreachable). Straight-
## line "closer" cells are a local-minima trap on maze-like maps — a maze can
## force a detour that temporarily increases raw distance before decreasing
## it, so picking by raw distance alone can strand a unit forever. Real path
## cost guarantees monotonic progress whenever any route exists.
func _try_move_toward(state: CombatState, unit: Unit, target: Unit) -> bool:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)

	var best_path: Array[Vector2i] = []
	var best_cost: float = INF
	for neighbor: Vector2i in state.grid.neighbors(target.cell):
		if not pf.is_walkable(neighbor):
			continue
		var path: Array[Vector2i] = pf.astar(unit.cell, neighbor)
		if path.is_empty():
			continue
		var cost: float = 0.0
		for i in range(1, path.size()):
			cost += pf.move_cost(path[i])
		if cost < best_cost:
			best_cost = cost
			best_path = path

	if best_path.size() < 2:
		return false  # no route to the target at all

	# Trim to whatever the unit can actually afford this turn.
	var budget: float = unit.mp + float(unit.ap) * unit.mp_per_ap()
	var affordable_path: Array[Vector2i] = [best_path[0]]
	var spent: float = 0.0
	for i in range(1, best_path.size()):
		var step_cost: float = pf.move_cost(best_path[i])
		if spent + step_cost > budget:
			break
		spent += step_cost
		affordable_path.append(best_path[i])

	if affordable_path.size() < 2:
		return false  # can't afford even one step this turn

	if not state.try_apply(MoveAction.new(unit, affordable_path)):
		return false
	print("  unit %d moved to %s" % [unit.id, unit.cell])
	return true


func _take_ai_turn(state: CombatState, unit: Unit, enemies: Array[Unit]) -> void:
	print(
		(
			"--- unit %d (squad %d) turn, ap=%d, cell=%s ---"
			% [unit.id, unit.squad_id, unit.ap, unit.cell]
		)
	)
	while unit.ap > 0:
		var target: Unit = _pick_best_target(unit, enemies)
		if target == null:
			break  # enemy squad already wiped mid-turn

		if state.try_apply(AttackAction.new(unit, target)):
			print("  unit %d attacked unit %d" % [unit.id, target.id])
			continue

		if not _has_living_weapon(unit) and _try_swap_weapon(state, unit):
			continue

		if _try_move_toward(state, unit, target):
			continue

		break  # nothing productive left this turn

	state.try_apply(EndTurnAction.new(unit))


func test_sample_battle_runs_to_a_conclusion() -> void:
	var grid: Grid = MapGen.generate(BATTLE_SEED, MAP_WIDTH, MAP_HEIGHT)
	var spawn_a: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_A)
	var spawn_b: Array[Vector2i] = _find_cells(grid, Enums.TerrainType.SPAWN_B)
	assert_true(spawn_a.size() > 0)
	assert_true(spawn_b.size() > 0)

	var squad_a: Array[Unit] = _make_squad(spawn_a, 0, "a")
	var squad_b: Array[Unit] = _make_squad(spawn_b, 1, "b")
	assert_true(squad_a.size() > 0 and squad_b.size() > 0)

	var all_units: Array[Unit] = squad_a + squad_b
	var state := CombatState.new(grid, all_units, BATTLE_SEED)

	print("=== Sample battle: seed %d, %dx%d map ===" % [BATTLE_SEED, MAP_WIDTH, MAP_HEIGHT])
	print(
		(
			"Squad A spawns at %s; Squad B spawns at %s"
			% [spawn_a.slice(0, squad_a.size()), spawn_b.slice(0, squad_b.size())]
		)
	)

	var turn_count := 0
	while not state.is_over() and turn_count < TURN_CAP:
		var unit: Unit = state.current_unit()
		assert_true(unit.alive, "turn order must never land on a dead unit")
		var enemies: Array[Unit] = squad_b if unit.squad_id == 0 else squad_a
		_take_ai_turn(state, unit, enemies)
		turn_count += 1

	print("=== Battle finished after %d unit-turns ===" % turn_count)

	assert_true(turn_count < TURN_CAP, "combat must conclude before the turn cap")
	assert_true(state.is_over(), "one squad must be fully down")

	var a_alive: bool = squad_a.any(func(u: Unit) -> bool: return u.alive)
	var b_alive: bool = squad_b.any(func(u: Unit) -> bool: return u.alive)
	assert_true(a_alive != b_alive, "exactly one squad should have survivors")
	print("Winner: %s" % ("Squad A" if a_alive else "Squad B"))

	# The fight must have actually exercised the full stack, not just moved around.
	assert_gt(state.action_log.size(), 0)
	var joined_log: String = "\n".join(state.action_log)
	assert_true(joined_log.contains("AttackAction"), "combat should have included attacks")
	assert_true(joined_log.contains("MoveAction"), "combat should have included movement")
	assert_true(
		joined_log.contains("SwapPartAction"), "a destroyed weapon should have forced a swap"
	)
