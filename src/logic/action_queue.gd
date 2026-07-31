class_name ActionQueue
extends RefCounted

## Per-unit, ordered list of queued actions (docs/09): TACTICS previews here,
## the authoritative CombatState is never mutated until RESOLUTION replays
## this queue for real via CombatState.resolve_turn(). Queuing validates
## against a disposable CombatState.dup() with every already-queued action
## replayed onto it first, so an attack queued after a move previews from
## the moved-to position — but a queued attack's own damage/hit outcome is
## never known until RESOLUTION actually rolls it; TACTICS can only ever
## confirm an action is structurally attemptable.

var unit: Unit
var actions: Array[CombatAction] = []
## taskblock-51 (`BR26.02`): **bumped on every change to `actions`.**
##
## Exists so a reader can ask "has this queue changed?" without calling `preview()`, which
## costs a full `CombatState.dup` — measured at **26 784 usec** on a 214-blocker board, more
## than twice a `ShotPlane.build`. A cache keyed on the previewed *position* has to clone to
## learn it; one keyed on this does not.
##
## Compared, never interpreted: only equality matters, so it never needs to mean anything.
var revision: int = 0


func _init(p_unit: Unit) -> void:
	unit = p_unit


## Validates `action` against a speculative preview of `state` — this
## queue's own already-queued actions replayed onto a dup(), never the real
## `state`. Appends and returns true only if legal there.
func enqueue(action: CombatAction, state: CombatState) -> bool:
	if not action.is_legal(preview(state)):
		return false
	actions.append(action)
	revision += 1
	return true


## The state this queue's actions would produce, without touching `state`.
func preview(state: CombatState) -> CombatState:
	var speculative: CombatState = state.dup()
	for action: CombatAction in actions:
		if action.is_legal(speculative):
			action.apply(speculative)
	return speculative
