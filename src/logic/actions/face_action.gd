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
## docs/09 taskblock06 Pass E: "facing is faster than overwatch triggering"
## — starting data, a tunable, not a design decision.
const SPEED := 100.0

var unit: Unit
var direction: float


func _init(p_unit: Unit, p_direction: float) -> void:
	unit = p_unit
	direction = p_direction


## docs/10 taskblock03 E2: "1 MP unlocks free refacing for the turn — not 1
## MP per rotation." Once `actual.facing_unlocked` is set, every further
## manual face this turn is free and always legal; only the FIRST one needs
## the MP-or-AP-burn check.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.facing_unlocked:
		return true
	return actual.mp >= COST or actual.ap > 0


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var reason: StringName = &"manual_first"
	var cost: float = COST
	if actual.facing_unlocked:
		reason = &"manual_free"
		cost = 0.0
	else:
		if actual.mp < COST:
			actual.ap -= 1
			actual.mp += actual.mp_per_ap()
		actual.mp -= COST
		actual.facing_unlocked = true
	actual.orientation = direction
	_log(state, actual, reason, cost)


## docs/10 taskblock02 F3: "any action taken with a target faces for free —
## firing... — inside apply(). Never charge for it." Called from inside
## another action's own apply(), never queued on its own, so it never pays
## MP/AP — but the turn itself is still real and still logged (docs/09:
## "if it changed the world, it's in the log"). A no-op if `actual` was
## already facing that way. `reason` defaults to the original attack case;
## runNotes.md's "movement should face the direction of travel" reuses this
## same free-facing primitive with its own `free_with_move` reason instead
## of inventing a second mechanism for the same "actions with an implicit
## direction face for free" rule.
static func face_for_free(
	state: CombatState, actual: Unit, direction: float, reason: StringName = &"free_with_action"
) -> void:
	if actual.orientation == direction:
		return
	actual.orientation = direction
	_log(state, actual, reason, 0.0)


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


func speed(_state: CombatState) -> float:
	return SPEED


func unit_id() -> int:
	return unit.id
