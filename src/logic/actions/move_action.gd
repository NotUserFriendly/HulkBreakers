class_name MoveAction
extends CombatAction

## A full path (inclusive of the unit's current cell). Movement spends MP per
## tile; when MP runs short the unit burns 1 AP for +mp_per_ap MP, repeating
## while AP remains (Appendix E). Fails (is_legal == false) if AP runs out
## before the path completes.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


## Actions never trust a bare Unit reference across states (docs/09): a
## preview's units are independent clones sharing `unit.id`, not the same
## object, so every read/write below goes through the unit `state` itself
## actually holds.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive:
		return false
	if state.current_unit() != actual:
		return false
	if path.size() < 2 or path[0] != actual.cell:
		return false

	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var sim_ap: int = actual.ap
	var sim_mp: float = actual.mp
	var per_ap: float = actual.mp_per_ap()

	for i in range(1, path.size()):
		if Grid.distance_chebyshev(path[i - 1], path[i]) != 1:
			return false
		var step_cost: float = pf.move_cost(path[i])
		if step_cost < 0.0:
			return false
		while sim_mp < step_cost:
			if sim_ap <= 0:
				return false
			sim_ap -= 1
			sim_mp += per_ap
		sim_mp -= step_cost

	return true


func apply(state: CombatState) -> void:
	apply_stepwise(state)


## docs/09 taskblock06 Pass D: like apply(), but checks `mid_move_hook`
## (Callable(state, unit) -> Variant, e.g. Pass F's Overwatch trigger check)
## after EVERY cell actually stepped onto, then re-validates whether the
## REST of the path is still completable given whatever that hook just
## did to the world — MP dropping (a lost leg lowering mp_per_ap, say)
## can turn a queued move illegal partway through even though nothing
## about the path itself changed. Stops there if so: docs/09 taskblock06
## D2's rule ("stop when the next [step] is no longer legal, not when
## anything changes") applies at cell granularity, not just between
## queued actions. A hook may also force an immediate freeze by returning
## `true` (docs/09 taskblock06 F2: "the mover freezes" the instant
## overwatch triggers, unconditionally — Pass D's own legality rule only
## governs the queue AFTER that freeze, not whether it happens); a void
## hook's `null` return is simply not `true`, so every pre-Overwatch hook
## keeps its old unconditional-continue behaviour untouched. `apply()` is
## just this with no hook, matching its old unconditional behaviour
## exactly.
##
## Returns {stopped: bool} — `state.find_unit(unit.id)`'s own `.mp` at
## the stopping point IS the refund (docs/09 taskblock06 D3: "they just
## get their MP back as change" — nothing extra to credit, the AP-to-MP
## conversion only ever buys as much MP as the step in front of it
## needs, so whatever's left in the pool when resolution stops already
## IS the untraversed remainder's own leftover).
func apply_stepwise(state: CombatState, mid_move_hook: Callable = Callable()) -> Dictionary:
	var actual: Unit = state.find_unit(unit.id)
	var pf := Pathfinder.new(state.grid, state.terrain_costs)

	for i in range(1, path.size()):
		var per_ap: float = actual.mp_per_ap()
		var step_cost: float = pf.move_cost(path[i])
		while actual.mp < step_cost:
			actual.ap -= 1
			actual.mp += per_ap
		actual.mp -= step_cost
		state.grid.set_occupant_id(actual.cell, -1)
		actual.cell = path[i]
		state.grid.set_occupant_id(actual.cell, actual.id)

		var hook_forces_stop: bool = false
		if mid_move_hook.is_valid():
			var hook_result: Variant = mid_move_hook.call(state, actual)
			hook_forces_stop = hook_result is bool and hook_result

		var is_final_step: bool = i == path.size() - 1
		if (
			not is_final_step
			and (hook_forces_stop or not _can_still_complete(state, actual, path.slice(i)))
		):
			_finish(state, actual, path.slice(0, i + 1))
			return {"stopped": true}

	_finish(state, actual, path)
	return {"stopped": false}


## Re-simulates `remaining` (the untraversed tail, inclusive of the cell
## just stepped onto) exactly like is_legal() simulates the whole path —
## against `actual`'s CURRENT mp/ap/mp_per_ap, which mid_move_hook may
## have just changed.
static func _can_still_complete(
	state: CombatState, actual: Unit, remaining: Array[Vector2i]
) -> bool:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var sim_ap: int = actual.ap
	var sim_mp: float = actual.mp
	var per_ap: float = actual.mp_per_ap()
	for i in range(1, remaining.size()):
		var step_cost: float = pf.move_cost(remaining[i])
		if step_cost < 0.0:
			return false
		while sim_mp < step_cost:
			if sim_ap <= 0:
				return false
			sim_ap -= 1
			sim_mp += per_ap
		sim_mp -= step_cost
	return true


func _finish(state: CombatState, actual: Unit, traversed: Array[Vector2i]) -> void:
	# runNotes.md: "a character's facing after movement should update to
	# face away from where they started" — free, same primitive
	# AttackAction's own free-with-action facing uses, so a queued move
	# updates the previewed wedge exactly like every other facing change.
	# Known consequence, confirmed by direct A/B testing, not yet resolved
	# (flagged rather than hacked around, CLAUDE.md's own rule): a unit
	# that stops moving because it's already in weapon range now keeps
	# whatever orientation its last step left it with, rather than a
	# constant default — for at least one scripted integration scenario
	# (test_full_mission.gd) this happens to freeze the last defender
	# facing its best armor at the attackers, stalemating the mission past
	# its turn cap. The mission AI has no facing awareness at all (it never
	# queues a FaceAction); making combat AI account for its own defensive
	# facing is a real follow-up, not something to invent unasked here.
	FaceAction.face_for_free(
		state,
		actual,
		FaceAction.orientation_toward(traversed[0], traversed[traversed.size() - 1]),
		&"free_with_move"
	)

	var text: String = "MoveAction: unit %d moved to %s" % [actual.id, actual.cell]
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"move",
				{"path": traversed, "destination": actual.cell},
				text
			)
		)


func describe() -> String:
	return "MoveAction(unit=%d, path=%s)" % [unit.id, path]
