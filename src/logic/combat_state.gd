class_name CombatState
extends RefCounted

## taskblock-18 C2: "units within the same speed band resolve
## simultaneously for playback... a band tolerance (units within epsilon
## speed) groups them; tunable, flagged default." See simultaneous_group()
## below.
const SIMULTANEOUS_BAND_TOLERANCE := 1.0

var grid: Grid
var units: Array[Unit] = []  # the roster — no longer literally turn order, see below
var squads: Dictionary = {}  # squad_id(int) -> Array[Unit]
## docs/10 taskblock02 F1: squad_id(int) -> Enums.SquadController. Absent
## entries default to HUMAN (controller_for) — "Control All Squads" is
## every squad's starting state, an override never has to opt in for it.
var squad_controllers: Dictionary = {}
## The actual round number (docs/09 LogEvent.turn) — a round is "every
## living unit has acted once," not "one more unit acted"; incremented in
## advance_turn() only when the acted-this-round set exhausts, never on
## every single turn.
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
var material_table: MaterialTable = DataLibrary.material_table()
## docs/10 taskblock05 E1: what a mangling Part.mangles_into resolves
## against — shared across the whole battle, same convention as
## material_table above. taskblock-16 Pass B: FieldObjects (hardcoded
## factories) is retired — every wreckage kind is a real `.tres` loaded
## through DataLibrary now, same as any other part.
var wreckage_pool: Array[Part] = [
	DataLibrary.get_part(&"twisted_sheet_metal"), DataLibrary.get_part(&"metal_scraps")
]
## True only on a dup() built for a TACTICS-time preview (docs/09). An
## attack's hit/damage outcome is the one genuinely probabilistic effect a
## preview must never resolve — not because randomness is expensive, but
## because a preview that *did* accurately predict it would make "the world
## moved" abort case at RESOLUTION unreachable: queuing would already have
## rejected anything RESOLUTION could later invalidate, since both would
## agree. AttackAction checks this to skip real damage resolution here.
var is_preview: bool = false

var _next_id: int = 0
## taskblock-18 C1: "turn order within a round is by resolution speed —
## fastest unit acts first... the SAME speed the resolver uses, not a
## second stat," replacing the old squad-sequential array-index walk.
## The id of whichever unit currently has AP/MP live; -1 before the very
## first turn of a round ever starts (an empty roster). Never trust a
## stored Unit reference across states (docs/09) — `current_unit()` always
## re-resolves through `find_unit()`.
var _current_unit_id: int = -1
## Unit ids that have already had `_start_turn()` called on them THIS
## round (the current unit included, from the moment its turn began) —
## cleared the instant `advance_turn()` finds no living, not-yet-acted
## candidate left and starts a fresh round.
var _acted_this_round: Array[int] = []


## `combat_seed` seeds all rolls made during this fight (Appendix A: hit
## resolution must be reproducible from a seed).
func _init(p_grid: Grid, initial_units: Array[Unit] = [], combat_seed: int = 0) -> void:
	grid = p_grid
	rng = RandomNumberGenerator.new()
	rng.seed = combat_seed
	for unit: Unit in initial_units:
		add_unit(unit)
	var living: Array[Unit] = units.filter(func(u: Unit) -> bool: return u.alive)
	if not living.is_empty():
		_begin_turn(_fastest_by_initiative(living))


## Registers a unit (assigning it an id if it doesn't have one), occupies its
## cell, and adds it to turn order and its squad. Used both for initial roster
## setup and for units spawned mid-combat (ImplantAction) — and for dup()'s
## own re-registration of every unit, dead ones included, onto a fresh
## clone's grid. A dead unit never occupies a cell (kill_unit's own rule),
## so this must not blindly re-mark one on a clone just because it's being
## re-added to a fresh `units` array.
func add_unit(unit: Unit) -> void:
	if unit.id == -1:
		unit.id = _next_id
		_next_id += 1
	units.append(unit)
	if not squads.has(unit.squad_id):
		squads[unit.squad_id] = []
	squads[unit.squad_id].append(unit)
	if unit.alive:
		grid.set_occupant_id(unit.cell, unit.id)


## The one place a unit's alive flag flips to false (docs/09 "if it changed
## the world, it's in the log" — the world-state half of that: a dead unit
## stops occupying its cell, same as MoveAction vacates a cell it steps off
## of, so its corpse never permanently blocks the grid for `Pathfinder`.
## `grid.field_items`/`blockers` (loot, dropped subtrees, cover) are a
## separate overlay untouched by this — a cell can be walkable and still
## hold something to pick up.
func kill_unit(unit: Unit) -> void:
	if not unit.alive:
		return
	unit.alive = false
	grid.set_occupant_id(unit.cell, -1)


func current_unit() -> Unit:
	return find_unit(_current_unit_id)


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
	cloned._current_unit_id = _current_unit_id
	cloned._acted_this_round = _acted_this_round.duplicate()
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
			"stopped (%s)" % reason
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
	# taskblock-08 Pass C: leftover MP from a prior turn is discarded
	# (Appendix E), but every turn starts with one AP's worth of MP
	# already banked, free — a turn-start grant, not a permanent mp_per_ap
	# change, so the AP itself is never spent and stays fully available.
	# "The first bit of movement is free tempo."
	unit.mp = unit.mp_per_ap()
	# docs/10 taskblock03 E2: the free-refacing unlock is a per-turn toll,
	# not a permanent one — a new turn always starts locked again.
	unit.facing_unlocked = false
	# docs/09 taskblock06 Pass F: overwatch is spent the instant it fires,
	# but an UNTRIGGERED watch also lapses once its own next turn comes
	# around — it was holding against threats that turn, not forever.
	unit.overwatch_weapon_id = &""
	var tier_before: SurrogateTier = unit.surrogate_tier
	LifeSupport.tick(unit, SurrogateLadder.default_ladder())
	# taskblock-09 A4: MELTDOWN countdowns tick on the same seam LifeSupport
	# already uses — the mutation (a part's own countdown, and detonate()'s
	# real damage if one expires) always runs, preview or not, exactly like
	# LifeSupport.tick() above; only the LOGGING below is preview-gated.
	var meltdowns: Array[Dictionary] = DamageResolver.tick_meltdowns(unit, self)

	if not is_preview:
		# The one place turn/unit gets announced at all now (LogEvent._to_
		# string() no longer echoes either per line) — everything else this
		# unit does for the rest of its turn is understood to still be it.
		combat_log.emit(
			LogEvent.new(
				round_number,
				Enums.Phase.RESOLUTION,
				unit.id,
				&"turn_start",
				{},
				"Turn %d — unit %d" % [round_number, unit.id]
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
					"%s -> %s (organics decay)" % [tier_before.id, unit.surrogate_tier.id]
				)
			)
		for entry: Dictionary in meltdowns:
			var part: Part = entry.part
			var affected: Array[Unit] = entry.units
			var affected_ids: Array = []
			for affected_unit: Unit in affected:
				affected_ids.append(affected_unit.id)
			combat_log.emit(
				LogEvent.new(
					round_number,
					Enums.Phase.RESOLUTION,
					unit.id,
					&"detonate",
					{"source_part": part.id, "units": affected_ids, "cause": "meltdown_expired"},
					"%s meltdown expired" % part.id
				)
			)


## Advances to the next living unit by INITIATIVE (taskblock-18 C1:
## fastest resolution speed first, not the old squad-sequential array
## walk), resetting its AP/MP. Bumps round_number and clears the
## acted-this-round set the instant every living unit has gone once —
## "everyone's had a turn," not "one more unit acted."
func advance_turn() -> void:
	var living: Array[Unit] = units.filter(func(u: Unit) -> bool: return u.alive)
	if living.is_empty():
		return
	var candidates: Array[Unit] = living.filter(
		func(u: Unit) -> bool: return not _acted_this_round.has(u.id)
	)
	if candidates.is_empty():
		round_number += 1
		_acted_this_round.clear()
		candidates = living
	_begin_turn(_fastest_by_initiative(candidates))


func _begin_turn(unit: Unit) -> void:
	_current_unit_id = unit.id
	_acted_this_round.append(unit.id)
	_start_turn(unit)


## taskblock-18 C1: fastest-first — lower ResolutionSpeed.initiative()
## acts sooner (A2's own "lower resolves first" direction), tie-broken by
## unit.id ascending for deterministic replay. personal_speed is already
## the entirety of initiative() (no action is chosen yet at turn-start),
## so a tie on speed here is a tie on both of Pass B's own first two
## tie-break terms at once — id is the only thing left to break it with.
static func _fastest_by_initiative(candidates: Array[Unit]) -> Unit:
	var best: Unit = candidates[0]
	var best_speed: float = ResolutionSpeed.initiative(best).current
	for candidate: Unit in candidates.slice(1):
		var speed: float = ResolutionSpeed.initiative(candidate).current
		var better: bool = speed < best_speed
		if not better and is_equal_approx(speed, best_speed):
			better = candidate.id < best.id
		if better:
			best = candidate
			best_speed = speed
	return best


## taskblock-18 C2: "units within the same speed band resolve
## simultaneously for playback... a band tolerance (units within epsilon
## speed) groups them; tunable, flagged default." "Equal speed =
## simultaneous is not a separate feature — it's the ordering already
## expressing a tie," so this is a pure grouping query, not a second
## mechanism: LOGIC-level only (this pass's own scope) — actually
## skipping the inter-turn pause for a group during playback is a
## BoutRunner/ResolutionPlayer change flagged for later, untouched here.
##
## Every LIVING unit (this one included) whose own initiative value falls
## within SIMULTANEOUS_BAND_TOLERANCE of `unit`'s — ordered fastest-first,
## then by id, the same order `_fastest_by_initiative` would resolve them
## in one at a time, so a caller can present the group without changing
## what "next" means.
func simultaneous_group(unit: Unit) -> Array[Unit]:
	var living: Array[Unit] = units.filter(func(u: Unit) -> bool: return u.alive)
	var target_speed: float = ResolutionSpeed.initiative(unit).current
	var group: Array[Unit] = living.filter(
		func(u: Unit) -> bool:
			var speed: float = ResolutionSpeed.initiative(u).current
			return absf(speed - target_speed) <= SIMULTANEOUS_BAND_TOLERANCE
	)
	group.sort_custom(
		func(a: Unit, b: Unit) -> bool:
			var speed_a: float = ResolutionSpeed.initiative(a).current
			var speed_b: float = ResolutionSpeed.initiative(b).current
			if not is_equal_approx(speed_a, speed_b):
				return speed_a < speed_b
			return a.id < b.id
	)
	return group
