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


## Queue-row-safe label — `describe()` itself can be arbitrarily long
## (`MoveAction`'s own path grows without bound), fine for a debug log
## line but not a fixed-width UI row. `SelectionController.queue_entries()` reads this for a queue
## row's own visible text and surfaces the full `describe()` on hover only when the two differ.
##
## **`BR34.03`, taskblock-61 Pass D: derived here rather than overridden per action.** The entry
## asked for `AttackAction(unit=2)` and added *"while in there, check the remaining action types
## rather than fixing one and leaving the next to be reported separately"* — and there are twenty,
## every one of them formatted `Name(first=..., rest...)`. Seven near-identical overrides would
## have been seven things to remember; keeping the first field and closing the paren is the same
## rule expressed once, and it covers an action nobody has written yet with no edit here.
##
## `MoveAction`'s own override is retired by this: truncating `MoveAction(unit=%d, path=%s)` at its
## first field produces exactly the text that override was written to produce.
func short_describe() -> String:
	return first_field_only(describe())


## `"Name(a=1, b=2)"` -> `"Name(a=1)"`, leaving anything without a second field untouched.
##
## **Depth-aware on purpose.** A field whose own value contains a comma — a `Vector2i` prints as
## `(3, 4)` — must not be cut through the middle, and one of these is a coordinate away from
## existing: `MoveAction` already formats an `Array[Vector2i]`. Splitting on the first `", "` would
## read correctly today and silently mangle the first action that puts a vector first.
static func first_field_only(text: String) -> String:
	var depth: int = 0
	for i in range(text.length()):
		var c: String = text[i]
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth -= 1
			if depth == 0:
				return text
		elif c == "," and depth == 1:
			return text.substr(0, i) + ")"
	return text


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
## contained ordering (no personal_speed/perk bonus, no re-validation).
## taskblock-19 Pass A re-ranked the constants deliberately for the new
## direction: `Overwatch.SPEED` (20.0) < default weapon `speed` (40.0,
## `Part.speed`) < `FaceAction.SPEED` (100.0) — overwatch resolves fastest,
## facing slowest. Flagged placeholders; only the relative ORDER is design
## intent, not the exact numbers.
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
