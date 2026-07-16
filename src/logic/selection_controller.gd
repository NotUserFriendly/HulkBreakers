class_name SelectionController
extends RefCounted

## Pure TACTICS-time selection/queuing logic (docs/10 Phase 12.2): the view
## only ever reads this and draws what it says. Nothing here mutates
## `state` — every queued action previews against ActionQueue's own
## speculative dup(), never the authoritative CombatState (docs/09:
## "queuing mutates nothing").

var state: CombatState
var selected_unit: Unit = null
var _queues: Dictionary = {}  # unit id (int) -> ActionQueue


func _init(p_state: CombatState) -> void:
	state = p_state


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
## the position the next queued move actually starts from.
func _previewed_unit() -> Unit:
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
	var actual: Unit = _previewed_unit()
	if actual == null:
		return []
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var budget: float = actual.mp + actual.mp_per_ap() * actual.ap
	return pf.reachable(actual.cell, budget)


## Click a reachable cell: queues a MoveAction from wherever the selected
## unit's already-queued path leaves it to `cell`. Returns whether the
## queue actually accepted it.
func queue_move(cell: Vector2i) -> bool:
	var actual: Unit = _previewed_unit()
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


## Queues ending the selected unit's turn — the last action any queue needs.
func queue_end_turn() -> bool:
	if selected_unit == null:
		return false
	return current_queue().enqueue(EndTurnAction.new(selected_unit), state)


## docs/10 taskblock02 F3: the selected unit's orientation as it would
## stand after every already-queued action — Q/E (TacticsController.
## turn_selected) turns relative to THIS, not the raw pre-queue value, so
## two queued turns in the same TACTICS pass compose instead of colliding.
func previewed_orientation() -> float:
	var actual: Unit = _previewed_unit()
	return actual.orientation if actual != null else 0.0


## Queues a FaceAction turning the selected unit toward `direction`
## (docs/10 taskblock02 F3) — the same MP/AP-burn legality every other
## queued action goes through, checked lazily at RESOLUTION time.
func queue_face(direction: float) -> bool:
	if selected_unit == null:
		return false
	return current_queue().enqueue(FaceAction.new(selected_unit, direction), state)


## Clears every queue and the current selection — called once whatever
## queue was active has actually been resolved (docs/09: RESOLUTION owns
## the mutation; TACTICS starts clean for whichever unit is current next).
func reset() -> void:
	_queues.clear()
	selected_unit = null
