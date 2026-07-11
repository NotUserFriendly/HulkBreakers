class_name CombatState
extends RefCounted

var grid: Grid
var units: Array[Unit] = []  # turn order
var squads: Dictionary = {}  # squad_id(int) -> Array[Unit]
var turn_index: int = 0
var action_log: Array[String] = []
var terrain_costs: Dictionary = {Enums.TerrainType.WALL: -1.0}
var rng: RandomNumberGenerator

var _next_id: int = 0


## `combat_seed` seeds all rolls made during this fight (Appendix A: hit
## resolution must be reproducible from a seed).
func _init(p_grid: Grid, initial_units: Array[Unit] = [], combat_seed: int = 0) -> void:
	grid = p_grid
	rng = RandomNumberGenerator.new()
	rng.seed = combat_seed
	for unit: Unit in initial_units:
		add_unit(unit)
	if not units.is_empty():
		_start_turn(units[0])


## Registers a unit (assigning it an id if it doesn't have one), occupies its
## cell, and adds it to turn order and its squad. Used both for initial roster
## setup and for units spawned mid-combat (ImplantAction).
func add_unit(unit: Unit) -> void:
	if unit.id == -1:
		unit.id = _next_id
		_next_id += 1
	units.append(unit)
	if not squads.has(unit.squad_id):
		squads[unit.squad_id] = []
	squads[unit.squad_id].append(unit)
	grid.set_occupant_id(unit.cell, unit.id)


func current_unit() -> Unit:
	return units[turn_index]


func log_action(text: String) -> void:
	action_log.append(text)


## Attempts an action: rejects (returns false, no mutation) if illegal,
## otherwise applies it and returns true.
func try_apply(action: CombatAction) -> bool:
	if not action.is_legal(self):
		return false
	action.apply(self)
	return true


func _start_turn(unit: Unit) -> void:
	unit.ap = unit.max_ap
	unit.mp = 0.0  # leftover MP from a prior turn is discarded here (Appendix E)


## Advances to the next living unit in turn order, resetting its AP/MP.
func advance_turn() -> void:
	var n: int = units.size()
	if n == 0:
		return
	for i in range(1, n + 1):
		var idx: int = (turn_index + i) % n
		if units[idx].alive:
			turn_index = idx
			_start_turn(units[idx])
			return


## True once at most one squad still has a living unit.
func is_over() -> bool:
	var squads_alive: int = 0
	for squad_units: Array in squads.values():
		for unit: Unit in squad_units:
			if unit.alive:
				squads_alive += 1
				break
	return squads_alive < 2
