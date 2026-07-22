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
var selected_unit: Unit = null
var _queues: Dictionary = {}  # unit id (int) -> ActionQueue


func _init(p_state: CombatState, p_mission: MissionState = null) -> void:
	state = p_state
	mission = p_mission


## Click your own unit: selects it only if it's actually the unit whose turn
## it is — the only unit any action can legally queue against right now
## (docs/09's two-phase turn resolves one unit's queue at a time). Anything
## else (an enemy, a dead unit, empty space) clears selection.
func select(unit: Unit) -> void:
	if unit != null and unit.alive and unit == state.current_unit():
		selected_unit = unit
	else:
		selected_unit = null


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
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var budget: float = actual.mp + actual.mp_per_ap() * actual.ap
	return pf.reachable(actual.cell, budget)


## Click a reachable cell: queues a MoveAction from wherever the selected
## unit's already-queued path leaves it to `cell`. Returns whether the
## queue actually accepted it.
func queue_move(cell: Vector2i) -> bool:
	var actual: Unit = previewed_unit()
	if actual == null:
		return false
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var path: Array[Vector2i] = pf.astar(actual.cell, cell)
	if path.size() < 2:
		return false
	return current_queue().enqueue(MoveAction.new(selected_unit, path), state)


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
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
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
	return current_queue().enqueue(EndTurnAction.new(selected_unit, mission), state)


## taskblock-19 Pass F: "available to AI and player (same-queue
## discipline)" — Hold's own player-facing entry point, the same shape
## queue_end_turn() already has (an alternative last action, never both).
func queue_hold() -> bool:
	if selected_unit == null:
		return false
	return current_queue().enqueue(HoldAction.new(selected_unit), state)


## taskblock-22 Pass E: repair's own player-facing entry point — a mid-turn
## action, not a turn-ender (unlike queue_end_turn/queue_hold above),
## queued the same way a move or attack is: MORE actions can follow it in
## the same TACTICS pass. `mission` is this controller's own (required for
## a real repair to ever be legal — RepairAction.is_legal always fails
## against a null one).
func queue_repair(welder_id: StringName, target_part_id: StringName) -> bool:
	if selected_unit == null:
		return false
	return current_queue().enqueue(
		RepairAction.new(selected_unit, welder_id, target_part_id, mission), state
	)


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
	return current_queue().enqueue(FaceAction.new(selected_unit, direction), state)


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
	queue.actions.pop_back()
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
	_queues.erase(selected_unit.id)


## Clears every queue and the current selection — called once whatever
## queue was active has actually been resolved (docs/09: RESOLUTION owns
## the mutation; TACTICS starts clean for whichever unit is current next).
func reset() -> void:
	_queues.clear()
	selected_unit = null


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
