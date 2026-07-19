class_name CombatAction
extends RefCounted

## Base for all combat actions. Mutations flow only through apply() so combat
## stays a replayable action log (Appendix B: keeps the door open for a future
## networked layer without building any networking now).


func is_legal(_state: CombatState) -> bool:
	return false


func apply(_state: CombatState) -> void:
	pass


func describe() -> String:
	return "CombatAction"


## docs/09 taskblock06 Pass E: a SECOND ordering axis — docs/09 Appendix G
## already orders UNITS by initiative; this orders ACTIONS at one instant
## (a mover's queued shot vs. the overwatch it triggers, say). A method,
## not a stored field, because some actions' speed is genuinely fixed
## (FaceAction) while others read it off their own content at resolve time
## (AttackAction reads its weapon Part's own `speed` — "a fast weapon can
## out-speed an overwatch trigger" needs the number to live on data, never
## a hardcoded ladder in a match statement).
##
## taskblock-18 A2: reframed as "time to resolve" — LOWER now resolves
## FIRST (a small number is less time, so it finishes sooner), the
## opposite of this method's own original "higher resolves first" taskblock
## -06 convention. This is `base_action_speed` in `ResolutionSpeed.resolve()`
## (taskblock-18 A2), the one axis every real contender is actually sorted
## by; `order_by_speed` below stays this class's own narrower, self-
## contained ordering (no personal_speed/perk bonus, no re-validation) —
## flagged: real weapon `speed` data (and `FaceAction.SPEED`) was authored
## under the OLD higher-wins convention and its relative values haven't
## been retuned for the new one yet; only the ORDER DIRECTION changed here,
## not the numbers.
func speed(_state: CombatState) -> float:
	return 0.0


## The unit this action belongs to — every concrete action overrides this
## with its own `unit.id`. Only exists for order_by_speed's own
## deterministic tie-break; -1 (never a real unit id) if left
## unoverridden.
func unit_id() -> int:
	return -1


## Stable ordering by speed(state), ascending (taskblock-18 A2: lower
## resolves first) — ties broken by unit_id ascending, so "simultaneous"
## always resolves the same way regardless of the order `actions` happened
## to arrive in.
static func order_by_speed(actions: Array[CombatAction], state: CombatState) -> Array[CombatAction]:
	var sorted: Array[CombatAction] = actions.duplicate()
	sorted.sort_custom(
		func(a: CombatAction, b: CombatAction) -> bool:
			var speed_a: float = a.speed(state)
			var speed_b: float = b.speed(state)
			if speed_a != speed_b:
				return speed_a < speed_b
			return a.unit_id() < b.unit_id()
	)
	return sorted
