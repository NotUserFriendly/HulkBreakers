class_name CombatState
extends RefCounted

var grid: Grid
var units: Array[Unit] = []  # turn order
var squads: Dictionary = {}  # squad_id(int) -> Array[Unit]
## docs/10 taskblock02 F1: squad_id(int) -> Enums.SquadController. Absent
## entries default to HUMAN (controller_for) — "Control All Squads" is
## every squad's starting state, an override never has to opt in for it.
var squad_controllers: Dictionary = {}
var turn_index: int = 0
## The actual round number (docs/09 LogEvent.turn), distinct from turn_index
## (a position in the turn-order array). Incremented in advance_turn() each
## time turn order wraps back to the front, not once per unit's turn.
var round_number: int = 0
var action_log: Array[String] = []
var terrain_costs: Dictionary = {Enums.TerrainType.WALL: -1.0}
var rng: RandomNumberGenerator
## Structured log (docs/09) — no sinks by default; the caller wires whichever
## it wants (Memory/Stdout/File/UI). Every impact and abort in resolve_turn()
## emits here.
var combat_log: CombatLog = CombatLog.new()
## Shared across the whole battle (docs/03) so every attack resolves DT and
## ricochet against the same tuning, not a fresh default per shot.
var material_table: MaterialTable = MaterialTable.default_table()
## True only on a dup() built for a TACTICS-time preview (docs/09). An
## attack's hit/damage outcome is the one genuinely probabilistic effect a
## preview must never resolve — not because randomness is expensive, but
## because a preview that *did* accurately predict it would make "the world
## moved" abort case at RESOLUTION unreachable: queuing would already have
## rejected anything RESOLUTION could later invalidate, since both would
## agree. AttackAction checks this to skip real damage resolution here.
var is_preview: bool = false

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


## The unit with this id, or null. Actions resolve their target through
## this rather than holding a bare Unit reference across states — a
## preview's units are independent clones (docs/09) sharing the same id,
## not the same object, so an identity comparison against a stored
## reference would wrongly read as "not this state's unit."
func find_unit(id: int) -> Unit:
	for unit: Unit in units:
		if unit.id == id:
			return unit
	return null


## docs/10 taskblock02 F1: HUMAN unless a squad was explicitly set to AI —
## "Control All Squads," the default this build ships with, is simply
## never overriding anything.
func controller_for(squad_id: int) -> Enums.SquadController:
	return squad_controllers.get(squad_id, Enums.SquadController.HUMAN)


func set_squad_controller(squad_id: int, controller: Enums.SquadController) -> void:
	squad_controllers[squad_id] = controller


func log_action(text: String) -> void:
	action_log.append(text)


## A fully independent copy — grid, every unit's whole shell tree, ground
## items — for TACTICS-time speculative previews (docs/09): ActionQueue
## replays already-queued actions onto a dup() to preview the next one.
## Marked `is_preview` so a replayed AttackAction spends AP but skips real
## damage resolution — structural mutations (move, swap, pick up) still
## replay for real against this disposable copy, since those aren't
## probabilistic. `action_log`/`combat_log` start empty — a preview's own
## log noise is never worth keeping.
func dup() -> CombatState:
	var cloned_units: Array[Unit] = []
	for unit: Unit in units:
		cloned_units.append(unit.dup())

	var cloned := CombatState.new(grid.dup(), [], rng.seed)
	cloned.is_preview = true
	cloned.terrain_costs = terrain_costs.duplicate()
	cloned.squad_controllers = squad_controllers.duplicate()
	cloned.material_table = material_table
	for unit: Unit in cloned_units:
		cloned.add_unit(unit)
	cloned.turn_index = turn_index
	cloned.round_number = round_number
	return cloned


## Executes every action in `queue` in order against this (authoritative)
## state, re-validating each one first (docs/09): the world may have moved
## since it was queued against a mere preview. An action that's no longer
## legal aborts — logged, never crashed, never silently skipped without a
## trace — and the queue continues to the next one regardless.
func resolve_turn(queue: ActionQueue) -> void:
	for action: CombatAction in queue.actions:
		if action.is_legal(self):
			action.apply(self)
			continue
		var reason: String = "aborted at resolution (no longer legal): %s" % action.describe()
		log_action(reason)
		combat_log.emit(
			LogEvent.new(
				round_number,
				Enums.Phase.RESOLUTION,
				queue.unit.id,
				&"action_aborted",
				{"action": action.describe()},
				reason
			)
		)


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
	var tier_before: SurrogateTier = unit.surrogate_tier
	LifeSupport.tick(unit, SurrogateLadder.default_ladder())

	if not is_preview:
		combat_log.emit(
			LogEvent.new(
				round_number,
				Enums.Phase.RESOLUTION,
				unit.id,
				&"turn_start",
				{},
				"turn_start: unit %d" % unit.id
			)
		)
		if unit.surrogate_tier != tier_before:
			combat_log.emit(
				LogEvent.new(
					round_number,
					Enums.Phase.RESOLUTION,
					unit.id,
					&"surrogate_demoted",
					{
						"from": tier_before.id,
						"to": unit.surrogate_tier.id,
						"cause": "organics_decay"
					},
					(
						"surrogate_demoted: unit %d %s -> %s (organics decay)"
						% [unit.id, tier_before.id, unit.surrogate_tier.id]
					)
				)
			)


## Advances to the next living unit in turn order, resetting its AP/MP.
## Bumps round_number whenever this wraps back to the front of turn order —
## a round is "everyone's had a turn," not "one more unit acted."
func advance_turn() -> void:
	var n: int = units.size()
	if n == 0:
		return
	var previous_index: int = turn_index
	for i in range(1, n + 1):
		var idx: int = (previous_index + i) % n
		if units[idx].alive:
			if idx <= previous_index:
				round_number += 1
			turn_index = idx
			_start_turn(units[idx])
			return
