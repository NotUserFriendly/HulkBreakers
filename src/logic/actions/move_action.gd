class_name MoveAction
extends CombatAction

## A full path (inclusive of the unit's current cell). Movement spends MP per
## tile; when MP runs short the unit burns 1 AP for +mp_per_ap MP, repeating
## while AP remains (Appendix E). Fails (is_legal == false) if AP runs out
## before the path completes.

var unit: Unit
var path: Array[Vector2i]
## taskblock-27 Pass B2: true for a Step Out's own two automated legs
## (StepOutPlanner.build_triple, TacticsController's own player-path
## equivalent) — no MP/AP cost either direction, for both the AI and the
## player (the one shared entry point). Reverses tb18/tb19's original
## "real MP/AP cost for both legs, no discount" design (docs/SUPERSEDED.md).
## An ordinary player- or AI-queued move is never free — this defaults to
## false, and nothing about path/legality validity (an impassable step is
## still illegal) is affected, only the MP/AP deduction itself.
var free: bool = false


func _init(p_unit: Unit, p_path: Array[Vector2i], p_free: bool = false) -> void:
	unit = p_unit
	path = p_path
	free = p_free


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
		if free:
			continue
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
	# taskblock: "bots visibly spin through every facing, then move" — the
	# STATE was already correct per-tile (taskblock-16 Pass A), but every
	# `faced` LogEvent below fired DURING this loop while the single `move`
	# event only ever fired once, at the very end, via `_finish()` — so a
	# curved path's whole combat_log stream read as N `faced` events back
	# to back, THEN one `move` covering the entire path, and any playback
	# that plays events in log order (ResolutionPlayer) has no choice but
	# to show every turn up front before any sliding starts. `run_start`
	# is the path index the next not-yet-logged `move` run begins at —
	# flushed (via `_finish`) right before a direction change actually
	# re-faces, so the log interleaves faced/move/faced/move per straight
	# leg instead of batching every faced event ahead of one aggregate
	# move. A straight, single-direction path never re-faces mid-flight,
	# so it still produces exactly one `move` event, unchanged.
	var run_start: int = 0

	for i in range(1, path.size()):
		var target_orientation: float = FaceAction.orientation_toward(actual.cell, path[i])
		if not is_equal_approx(actual.orientation, target_orientation):
			if i - 1 > run_start:
				_finish(state, actual, path.slice(run_start, i))
				run_start = i - 1
			# free, the same primitive _finish() used to call ONCE, on the
			# aggregate start->end direction, before this pass — now called
			# once per direction actually taken, right where that leg
			# begins.
			FaceAction.face_for_free(state, actual, target_orientation, &"free_with_move")
		var per_ap: float = actual.mp_per_ap()
		var step_cost: float = pf.move_cost(path[i])
		if not free:
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

		# taskblock-18 D3: a triggered hook forces a freeze UNCONDITIONALLY
		# (this function's own doc comment already says so) — but until
		# this fix, that promise silently broke for a move's own LAST step:
		# `is_final_step` used to gate BOTH halves of this check, so a
		# single-step move (exactly what a step out's own outbound/return
		# leg always is — taskblock-19 Pass B: Lean -> Step Out rename)
		# could trigger overwatch, spend the watch, and still
		# sail on to complete the ENTIRE rest of the queue — the "ghost
		# bullet" case D3 exists to prevent, undetected until now because
		# every prior Overwatch test happened to trigger on an EARLIER,
		# non-final step. `_can_still_complete`'s own check stays exempt on
		# the final step (nothing left to "complete" beyond what already
		# happened — and its own loop is a no-op on a 1-cell remainder
		# anyway); only `hook_forces_stop` needed to escape the gate.
		var is_final_step: bool = i == path.size() - 1
		if (
			hook_forces_stop
			or (not is_final_step and not _can_still_complete(state, actual, path.slice(i), free))
		):
			_finish(state, actual, path.slice(run_start, i + 1))
			return {"stopped": true}

	_finish(state, actual, path.slice(run_start, path.size()))
	return {"stopped": false}


## Re-simulates `remaining` (the untraversed tail, inclusive of the cell
## just stepped onto) exactly like is_legal() simulates the whole path —
## against `actual`'s CURRENT mp/ap/mp_per_ap, which mid_move_hook may
## have just changed. `free` mirrors `is_legal()`'s own skip: a step-out
## leg's own remaining tail can never run out of MP/AP to stop it, since
## none of it was ever going to be charged.
static func _can_still_complete(
	state: CombatState, actual: Unit, remaining: Array[Vector2i], free: bool = false
) -> bool:
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var sim_ap: int = actual.ap
	var sim_mp: float = actual.mp
	var per_ap: float = actual.mp_per_ap()
	for i in range(1, remaining.size()):
		var step_cost: float = pf.move_cost(remaining[i])
		if step_cost < 0.0:
			return false
		if free:
			continue
		while sim_mp < step_cost:
			if sim_ap <= 0:
				return false
			sim_ap -= 1
			sim_mp += per_ap
		sim_mp -= step_cost
	return true


## taskblock-16 Pass A: "the end-of-move facing is now just the last step's
## facing — no separate final face needed." The loop above already faced
## toward every tile, `path[-1]` included, before ever stepping onto it —
## an interrupted move (traversed stops short of the full path) is left
## facing whichever tile its OWN last completed step faced, i.e. its real
## direction of travel at the interrupt point, never re-derived here.
## Known consequence, confirmed by direct A/B testing, not yet resolved
## (flagged rather than hacked around, CLAUDE.md's own rule): a unit that
## stops moving because it's already in weapon range keeps whatever
## orientation its last step left it with, rather than a constant
## default — for at least one scripted integration scenario
## (test_full_mission.gd) this happens to freeze the last defender facing
## its best armor at the attackers, stalemating the mission past its turn
## cap. The mission AI has no facing awareness at all (it never queues a
## FaceAction); making combat AI account for its own defensive facing is
## a real follow-up, not something to invent unasked here.
func _finish(state: CombatState, actual: Unit, traversed: Array[Vector2i]) -> void:
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
				"moved to %s" % actual.cell
			)
		)


func describe() -> String:
	return "MoveAction(unit=%d, path=%s)" % [unit.id, path]


## BR27.08 (supervisor follow-up): the full path (`describe()` above)
## grows without bound — a long queued move stretched the queue panel's
## own readout across the whole display. The coordinates themselves still
## reach the tooltip via `describe()`'s own full text (`SelectionController
## .queue_entries()` surfaces it as hover detail whenever it differs from
## this); the row itself just says what kind of action this is.
func short_describe() -> String:
	return "Move"
