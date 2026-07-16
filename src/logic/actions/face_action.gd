class_name FaceAction
extends CombatAction

## docs/10 taskblock02 F3: turning to face costs MP, not AP directly — the
## same AP-to-MP burn `MoveAction` already uses (Appendix E) when the unit
## is short on MP, so turning to cover a flank costs distance, same as any
## other movement spend. `direction` is an absolute orientation in radians
## (docs/02: the same continuous, never-snapped angle `BodyProjector`
## already reads from `Unit.orientation`) — not a delta, so queuing two
## FaceActions back to back is idempotent on the second one's own target,
## never additive.

const COST := 1.0

var unit: Unit
var direction: float


func _init(p_unit: Unit, p_direction: float) -> void:
	unit = p_unit
	direction = p_direction


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	return actual.mp >= COST or actual.ap > 0


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	if actual.mp < COST:
		actual.ap -= 1
		actual.mp += actual.mp_per_ap()
	actual.mp -= COST
	actual.orientation = direction
	_log(state, actual, &"manual", COST)


## docs/10 taskblock02 F3: "any action taken with a target faces for free —
## firing... — inside apply(). Never charge for it." Called from inside
## another action's own apply(), never queued on its own, so it never pays
## MP/AP — but the turn itself is still real and still logged (docs/09:
## "if it changed the world, it's in the log"). A no-op if `actual` was
## already facing that way.
static func face_for_free(state: CombatState, actual: Unit, direction: float) -> void:
	if actual.orientation == direction:
		return
	actual.orientation = direction
	_log(state, actual, &"free_with_action", 0.0)


## The absolute orientation (docs/02 convention) that faces `from_cell`
## toward `to_cell` — `BodyProjector.WORLD_FORWARD` rotated by this exact
## angle lands on the direction between them. Callers own the "is there
## even a direction to face" question (e.g. GatherAction/PickUpAction
## always interact with the actor's own cell — zero delta, nothing to
## turn toward, so neither calls this at all).
static func orientation_toward(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var delta := Vector2(to_cell - from_cell)
	return BodyProjector.WORLD_FORWARD.angle_to(delta.normalized())


static func _log(state: CombatState, actual: Unit, reason: StringName, cost: float) -> void:
	var text: String = (
		"FaceAction: unit %d faced %.2f rad (%s)" % [actual.id, actual.orientation, reason]
	)
	state.log_action(text)
	if state.is_preview:
		return
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			actual.id,
			&"faced",
			{"direction": actual.orientation, "cost": cost, "reason": reason},
			text
		)
	)


func describe() -> String:
	return "FaceAction(unit=%d, direction=%.2f)" % [unit.id, direction]
