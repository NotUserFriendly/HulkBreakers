class_name SelectionController
extends RefCounted

## Pure TACTICS-time selection/queuing logic (docs/10 Phase 12.2): the view
## only ever reads this and draws what it says. Nothing here mutates
## `state` — every queued action previews against ActionQueue's own
## speculative dup(), never the authoritative CombatState (docs/09:
## "queuing mutates nothing").

var state: CombatState
## taskblock-22 Pass A2: optional, same reason `EndTurnAction`'s own
## constructor takes one — the player squad's own passive extraction hold
## (checked there) only ever fires for a HUMAN-driven unit through this
## controller's own `queue_end_turn()`. `null` (every existing caller/test)
## simply skips it, unchanged.
var mission: MissionState = null
## taskblock-51 Pass K: **what is selected, which is not necessarily a unit.** A barrel, a
## wall, a loose field item or a bare cell are all selectable now; see `SelectionTarget`.
##
## taskblock-51 Pass L: **read through a guard, because death is not an event this listens
## for.** `BR51.09` — killing a unit during its own turn advanced the turn but left the corpse
## selected, so its reachable-cell overlay stayed drawn into the next unit's turn. Fixing that
## by notifying the selection from `kill_unit` would put a TACTICS-time concern inside a
## RESOLUTION-time mutation and leave every *other* way a unit can stop being valid unhandled.
## Invalidating on read cannot be missed by a call site that forgot to subscribe.
var selected_target: SelectionTarget:
	get:
		_release_invalid_selection()
		return _selected_target
## **Derived, not stored.** Eighty-one readers across the view ask "what unit is selected",
## and every one of them still means it — so this stays, answering `null` whenever the
## selection is a prop or a cell. Making it a property rather than a second field is what
## keeps the two from drifting apart, which is the failure mode that would have made Pass K
## worse than the gap it closes.
var selected_unit: Unit:
	get:
		return selected_target.unit if selected_target.is_unit() else null
var _selected_target: SelectionTarget = SelectionTarget.none()
var _queues: Dictionary = {}  # unit id (int) -> ActionQueue


func _init(p_state: CombatState, p_mission: MissionState = null) -> void:
	state = p_state
	mission = p_mission


## Click your own unit: selects it only if it's actually the unit whose turn
## it is — the only unit any action can legally queue against right now
## (docs/09's two-phase turn resolves one unit's queue at a time). Anything
## else (an enemy, a dead unit, empty space) clears selection.
##
## taskblock-51 Pass K: a thin wrapper over `select_target` rather than a second path into
## the same field — "no parallel systems" applies inside one class too.
func select(unit: Unit) -> void:
	if unit != null and unit.alive and unit == state.current_unit():
		select_target(SelectionTarget.for_unit(unit))
	elif unit != null and not unit.alive:
		# taskblock-51: the supervisor's decision — a corpse is selectable **as a wreck**, the
		# same way cover is, never as a unit. Inspection, not command.
		select_target(SelectionTarget.for_wreck(unit))
	else:
		select_target(SelectionTarget.none())


## **The general entry: select anything the picker can return.**
##
## A `UNIT` target is gated exactly as before — only the current unit, only while alive — so
## the rule that "you may only queue against whoever's turn it is" is unchanged. **A prop or
## a cell has no such gate**: selecting a barrel is inspection, not command, and nothing
## downstream can queue an action against one.
func select_target(target: SelectionTarget) -> void:
	if target == null:
		_selected_target = SelectionTarget.none()
		return
	if target.is_unit() and not (target.unit.alive and target.unit == state.current_unit()):
		_selected_target = SelectionTarget.none()
		return
	_selected_target = target


## **A dead unit is not a selection**, and its plan dies with it.
##
## taskblock-51 Pass L / `BR51.09`. Selecting a corpse is a real design question the addendum
## raises — a wreck is a thing on the board with parts on it, and Pass K made non-unit targets
## expressible — but "the unit you were commanding is still selected and still drawing its
## movement range" is not that question. It is a stale pointer, and it is cleared here.
##
## The queue goes too: `_queues` is keyed by unit id and would otherwise hand a dead unit's
## plan back if its id were ever selected again.
func _release_invalid_selection() -> void:
	if not _selected_target.is_unit():
		return
	if _selected_target.unit.alive:
		return
	_queues.erase(_selected_target.unit.id)
	_selected_target = SelectionTarget.none()


## Whether the current selection has a body the inspect panel can describe — `BR51.10`'s
## "Inspect should be disabled when there is nothing to inspect", asked of the selection
## rather than of "has anything been clicked".
func can_inspect() -> bool:
	return selected_target.can_inspect()


func current_queue() -> ActionQueue:
	if selected_unit == null:
		return null
	if not _queues.has(selected_unit.id):
		_queues[selected_unit.id] = ActionQueue.new(selected_unit)
	return _queues[selected_unit.id]


## The selected unit as it would stand after every already-queued action —
## the position the next queued move actually starts from. docs/10
## taskblock03 F1: also the source for the end-position ghost — its `.cell`/
## `.orientation` already ARE the queued end state, no separate override
## needed.
func previewed_unit() -> Unit:
	var queue: ActionQueue = current_queue()
	if queue == null:
		return null
	var preview: CombatState = queue.preview(state)
	var actual: Unit = preview.find_unit(selected_unit.id)
	return actual if actual != null and actual.alive else null


## Every cell the selected unit could still reach this turn, given whatever
## is already queued — exactly `Pathfinder.reachable`, no highlight logic
## duplicated here.
func reachable_cells() -> Array[Vector2i]:
	var actual: Unit = previewed_unit()
	if actual == null:
		return []
	var pf := Pathfinder.for_unit(state.grid, actual)
	var budget: float = actual.mp + actual.mp_per_ap() * actual.ap
	return pf.reachable(actual.cell, budget)


## taskblock-57 Pass D: **the one place a player-queued action enters a queue.**
##
## `queue_panel` retires this pass and its confirmation role moves to the combat log, so every
## queued action has to announce itself. Before this there were nine ways in — five `queue_*`
## methods here and four direct `selection.current_queue().enqueue(...)` calls in
## `TacticsController` — and a log line at each would have been nine chances to forget one.
##
## **Only logs what actually landed.** `ActionQueue.enqueue` validates against a speculative
## preview and refuses an illegal action; a confirmation for a click that was rejected is worse
## than none, because it says the queue holds something it does not.
func enqueue(action: CombatAction) -> bool:
	var queue: ActionQueue = current_queue()
	if queue == null or not queue.enqueue(action, state):
		return false
	QueueLog.queued(state, action)
	return true


## Click a reachable cell: queues a MoveAction from wherever the selected
## unit's already-queued path leaves it to `cell`. Returns whether the
## queue actually accepted it.
func queue_move(cell: Vector2i) -> bool:
	var actual: Unit = previewed_unit()
	if actual == null:
		return false
	var pf := Pathfinder.for_unit(state.grid, actual)
	var path: Array[Vector2i] = pf.astar(actual.cell, cell)
	if path.size() < 2:
		return false
	return enqueue(MoveAction.new(selected_unit, path))


## One path per queued MoveAction, in queue order — draw one ghost per
## entry; two queued moves must show two ghosts.
func ghost_paths() -> Array[Array]:
	var queue: ActionQueue = current_queue()
	if queue == null:
		return []
	var paths: Array[Array] = []
	for action: CombatAction in queue.actions:
		if action is MoveAction:
			paths.append((action as MoveAction).path)
	return paths


## docs/10 taskblock03 D2: "show the running MP cost per leg and the
## total" — one entry per ghost_paths() leg, in the same order, so a view
## can zip the two arrays together without re-deriving cost itself.
func leg_costs() -> Array[float]:
	var actual: Unit = previewed_unit()
	var pf := Pathfinder.for_unit(state.grid, actual)
	var costs: Array[float] = []
	for path: Array in ghost_paths():
		var typed_path: Array[Vector2i] = []
		typed_path.assign(path)
		costs.append(pf.path_cost(typed_path))
	return costs


## Queues ending the selected unit's turn — the last action any queue needs.
func queue_end_turn() -> bool:
	if selected_unit == null:
		return false
	return enqueue(EndTurnAction.new(selected_unit, mission))


## taskblock-19 Pass F: "available to AI and player (same-queue
## discipline)" — Hold's own player-facing entry point, the same shape
## queue_end_turn() already has (an alternative last action, never both).
func queue_hold() -> bool:
	if selected_unit == null:
		return false
	return enqueue(HoldAction.new(selected_unit))


## taskblock-22 Pass E: repair's own player-facing entry point — a mid-turn
## action, not a turn-ender (unlike queue_end_turn/queue_hold above),
## queued the same way a move or attack is: MORE actions can follow it in
## the same TACTICS pass. `mission` is this controller's own (required for
## a real repair to ever be legal — RepairAction.is_legal always fails
## against a null one).
func queue_repair(welder_id: StringName, target_part_id: StringName) -> bool:
	if selected_unit == null:
		return false
	return enqueue(RepairAction.new(selected_unit, welder_id, target_part_id, mission))


## docs/10 taskblock02 F3: the selected unit's orientation as it would
## stand after every already-queued action — Q/E (TacticsController.
## turn_selected) turns relative to THIS, not the raw pre-queue value, so
## two queued turns in the same TACTICS pass compose instead of colliding.
func previewed_orientation() -> float:
	var actual: Unit = previewed_unit()
	return actual.orientation if actual != null else 0.0


## Queues a FaceAction turning the selected unit toward `direction`
## (docs/10 taskblock02 F3) — the same MP/AP-burn legality every other
## queued action goes through, checked lazily at RESOLUTION time.
func queue_face(direction: float) -> bool:
	if selected_unit == null:
		return false
	return enqueue(FaceAction.new(selected_unit, direction))


## docs/10 taskblock03 D3: "RMB pops the last queued action and refunds its
## cost against the speculative state." No refund bookkeeping needed —
## preview() always rebuilds from a fresh state.dup() and replays whatever
## remains in `actions`, so simply removing the last entry IS the refund.
## Returns whether anything was actually popped, so the caller (RMB with an
## empty queue -> deselect) knows which case it's in.
func undo_last() -> bool:
	var queue: ActionQueue = current_queue()
	if queue == null or queue.actions.is_empty():
		return false
	var dropped: CombatAction = queue.actions.pop_back()
	queue.revision += 1
	# taskblock-57 Pass D: the other half of the queue panel's confirmation role. Emitted AFTER the
	# pop, so a log line can never claim a cancellation the queue did not actually make.
	QueueLog.cancelled(state, dropped)
	return true


## BR27.08 (supervisor follow-up): a partial resolve must not discard
## everything still planned after the resolve point — only the prefix
## that actually just resolved is gone; a player who only meant to lock
## in the first few legs of a longer plan shouldn't lose the rest. Safe to
## replay the SAME `CombatAction` objects unmodified: every action already
## re-validates itself against whatever real `state` it's actually handed
## at apply time (docs/09), and a queued `MoveAction`'s own `path[0]` was
## always wherever the PRECEDING leg's own preview left the unit — exactly
## where the real resolve just moved it to.
func keep_queue_suffix(from_index: int) -> void:
	if selected_unit == null:
		return
	var queue: ActionQueue = current_queue()
	if queue == null:
		return
	var remaining := ActionQueue.new(selected_unit)
	remaining.actions = queue.actions.slice(from_index)
	_queues[selected_unit.id] = remaining


## docs/10 taskblock03 D4: "Reset Turn" — discard everything queued this
## TACTICS phase and restore the unit to exactly how it started. Unlike
## reset() (called once a turn actually resolves), this keeps the unit
## selected: the human is still mid-TACTICS, just starting over. Erasing the
## queue is the whole fix — preview() always reclones from authoritative
## `state` on demand, so there is no speculative position/facing/MP/AP left
## to separately roll back (docs/09: TACTICS never mutates authoritative
## state in the first place).
func reset_turn() -> void:
	if selected_unit == null:
		return
	# taskblock-57 Pass D: one cancellation line per action, newest first, so Reset Turn reads as
	# the undo-everything it is rather than as the queue silently emptying. Folded into one counted
	# row by `LogFold`, and still drillable — see `QueueLog`.
	var queue: ActionQueue = _queues.get(selected_unit.id)
	if queue != null:
		for i in range(queue.actions.size() - 1, -1, -1):
			QueueLog.cancelled(state, queue.actions[i])
	_queues.erase(selected_unit.id)


## Clears every queue and the current selection — called once whatever
## queue was active has actually been resolved (docs/09: RESOLUTION owns
## the mutation; TACTICS starts clean for whichever unit is current next).
func reset() -> void:
	_queues.clear()
	_selected_target = SelectionTarget.none()


## docs/10 taskblock06 G2: "each entry: what, its cost, the running AP/MP
## total after it." One entry per queued action, in order — `short_
## describe()` for "what" (BR27.08 follow-up: the queue-row-safe label;
## `describe()`'s own full text only rides along as "detail," and only
## when it actually says more, so a hover tooltip can still show it
## without every row paying for it), and the unit's own ap/mp immediately
## after that action resolves against a speculative preview. Replays
## exactly the way ActionQueue.preview() already does (a fresh state.dup(),
## stepping through `actions` in order) rather than inventing a
## per-action-type cost accessor: this can never show a number "Resolve to
## Here" wouldn't actually produce, because it's the same replay.
func queue_entries() -> Array[Dictionary]:
	var queue: ActionQueue = current_queue()
	if queue == null:
		return []
	var speculative: CombatState = state.dup()
	var entries: Array[Dictionary] = []
	for action: CombatAction in queue.actions:
		if action.is_legal(speculative):
			action.apply(speculative)
		var actual: Unit = speculative.find_unit(selected_unit.id)
		var short: String = action.short_describe()
		var full: String = action.describe()
		var entry: Dictionary = {
			"describe": short,
			"ap": actual.ap if actual != null else 0,
			"mp": actual.mp if actual != null else 0.0,
		}
		if full != short:
			entry["detail"] = full
		entries.append(entry)
	return entries
