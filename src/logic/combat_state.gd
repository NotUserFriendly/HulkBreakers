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
## docs/10 taskblock05 E1: what a mangling Part.mangles_into resolves
## against — shared across the whole battle, same convention as
## material_table above.
var wreckage_pool: Array[Part] = FieldObjects.wreckage_pool()
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
	cloned.wreckage_pool = wreckage_pool
	for unit: Unit in cloned_units:
		cloned.add_unit(unit)
	cloned.turn_index = turn_index
	cloned.round_number = round_number
	return cloned


## docs/09 taskblock06 Pass D: kept for every existing caller that just
## wants "run the queue" with no interest in the outcome — a thin wrapper
## over resolve_until(), which owns the real logic now. Discards the
## Outcome; the STOPPED case is already fully logged by resolve_until
## itself, so nothing is silently lost by ignoring the return value here.
func resolve_turn(queue: ActionQueue) -> void:
	resolve_until(queue)


## Executes `queue`'s actions in order against this (authoritative) state,
## re-validating each one first (docs/09): the world may have moved since
## it was queued against a mere preview.
##
## docs/09 taskblock06 D1/D2: RESOLUTION is a loop with re-entry now, not
## one atomic pass — TACTICS -> RESOLUTION -> (interrupt) -> TACTICS ->
## RESOLUTION -> .... Stops the instant the next thing to happen is no
## longer legal (never "abort this one and keep going," taskblock02 F's
## rule, reversed) and returns control to just this unit
## (docs/10 taskblock06 D4 — other units' own queues are unaffected,
## since each is resolved by its own separate call). A MoveAction is
## re-checked at cell granularity too (MoveAction.apply_stepwise,
## `mid_move_hook` — Pass F's Overwatch trigger plugs in there later),
## since a queued move can turn illegal partway through even though the
## path itself never changed (a lost leg lowering mp_per_ap, say).
##
## Returns `{"kind": Enums.ResolveOutcome.COMPLETED}` or
## `{"kind": STOPPED, "unit": Unit, "reason": StringName, "refund": {"ap":
## int, "mp": float}}` — docs/09 taskblock06 D3: AP always stays spent (it
## already bought whatever MP got used), MP is whatever the interrupted
## unit's own pool holds at the stopping point (there is nothing extra to
## credit — the AP-to-MP conversion only ever buys as much as the very
## next step needs).
func resolve_until(queue: ActionQueue, mid_move_hook: Callable = Callable()) -> Dictionary:
	for action: CombatAction in queue.actions:
		if not action.is_legal(self):
			return _stopped(queue.unit, &"next_action_illegal")
		if action is MoveAction:
			var result: Dictionary = (action as MoveAction).apply_stepwise(self, mid_move_hook)
			if result.stopped:
				return _stopped(queue.unit, &"mid_move_interrupt")
		else:
			action.apply(self)
	return {"kind": Enums.ResolveOutcome.COMPLETED}


func _stopped(unit: Unit, reason: StringName) -> Dictionary:
	var actual: Unit = find_unit(unit.id)
	var outcome: Dictionary = {
		"kind": Enums.ResolveOutcome.STOPPED,
		"unit": actual,
		"reason": reason,
		"refund": {"ap": 0, "mp": actual.mp if actual != null else 0.0},
	}
	var text: String = "resolve_until: unit %d stopped (%s)" % [unit.id, reason]
	log_action(text)
	combat_log.emit(
		LogEvent.new(
			round_number,
			Enums.Phase.RESOLUTION,
			unit.id,
			&"resolution_stopped",
			{"reason": reason, "refund_mp": outcome.refund.mp},
			text
		)
	)
	return outcome


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
	# docs/10 taskblock03 E2: the free-refacing unlock is a per-turn toll,
	# not a permanent one — a new turn always starts locked again.
	unit.facing_unlocked = false
	# docs/09 taskblock06 Pass F: overwatch is spent the instant it fires,
	# but an UNTRIGGERED watch also lapses once its own next turn comes
	# around — it was holding against threats that turn, not forever.
	unit.overwatch_weapon_id = &""
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
