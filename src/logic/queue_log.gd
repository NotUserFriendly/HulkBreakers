class_name QueueLog
extends RefCounted

## taskblock-57 Pass D: **queueing and cancelling, in the combat log.**
##
## `queue_panel` retires this pass. The taskblock is explicit about what that costs and what pays
## for it: *"What is lost is confirmation that a click registered, which has confused people
## before — so it moves to the combat log under a queuing fold."*
##
## Four shapes, the taskblock's own:
##
##     unit 0 queued a move to (0,0,1)
##     unit 0 queued action: burst
##     unit 0 cancelled move
##     unit 0 cancelled action: burst
##
## ## Logic, and one emitter rather than one per call site
##
## Every player-queued action goes through `SelectionController.enqueue`, which calls this. That is
## the point: before this pass, `TacticsController` reached into `selection.current_queue().enqueue`
## from four places and `SelectionController` had five `queue_*` methods of its own — nine call
## sites, and a confirmation line at each would have been nine chances to forget one. Routing them
## all through one method is the "no parallel systems" rule applied to a log line.
##
## ## Why the AI's queueing is not logged
##
## The entries exist to confirm **a click registered**. An AI planner enqueues, discards and
## re-enqueues while it evaluates, and logging that would bury the player's own confirmation in
## someone else's deliberation. The planner's decisions already have their own reporting.
##
## ## Folding
##
## Both kinds join `LogFold.PLUMBING_KINDS`, which folds a consecutive run of one kind into a single
## counted row with the detail still drillable. A five-leg move plan is one row that opens into
## five, rather than five rows pushing the fight off the top of the panel. **Presentation only**
## (tb22 F2): `out/combat.log` carries every line either way.

## A player queued an action. Folded — see the class note.
const QUEUED: StringName = &"action_queued"
## A player took one back, by RMB-undo or by resetting the turn.
const CANCELLED: StringName = &"action_cancelled"


## Emits `unit N queued ...` for `action`. A null log is a legal state — a `SelectionController`
## built against a state with no log, which several fixtures are — and emits nothing.
static func queued(state: CombatState, action: CombatAction) -> void:
	_emit(state, action, QUEUED, "queued")


## Emits `unit N cancelled ...` for `action`.
static func cancelled(state: CombatState, action: CombatAction) -> void:
	_emit(state, action, CANCELLED, "cancelled")


## **The label is derived from the action, never passed in**, so the log and the queue panel that
## used to show the same thing cannot describe one action two ways.
##
## A move says where it is going, because "queued a move" without a destination is the confirmation
## failing at the one thing it exists for — you clicked a cell and want to know *which* cell it
## heard. Everything else names the action.
static func describe(action: CombatAction) -> String:
	if action is MoveAction:
		var path: Array[Vector2i] = (action as MoveAction).path
		if path.is_empty():
			return "a move"
		var to: Vector2i = path[path.size() - 1]
		return "a move to (%d,%d)" % [to.x, to.y]
	return "action: %s" % action.short_describe()


## The short form used by a cancellation, which does not repeat the destination — you are being told
## the thing you just did is undone, not re-told what it was.
static func describe_short(action: CombatAction) -> String:
	if action is MoveAction:
		return "move"
	return "action: %s" % action.short_describe()


static func _emit(state: CombatState, action: CombatAction, kind: StringName, verb: String) -> void:
	if state == null or state.combat_log == null or action == null:
		return
	var unit_id: int = action.unit.id if action.unit != null else -1
	var what: String = describe(action) if kind == QUEUED else describe_short(action)
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.TACTICS,
			unit_id,
			kind,
			{"action": action.short_describe()},
			"unit %d %s %s" % [unit_id, verb, what]
		)
	)
