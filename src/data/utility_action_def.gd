class_name UtilityActionDef
extends Resource

## One thing a unit might choose to do, and how it decides whether it wants to.
## `docs/11` has the model and why these are `.tres` rather than code.
##
## **Preconditions are separate from considerations on purpose.** A consideration
## answers "how much do I want this" and can veto by returning zero; a precondition
## answers "is this even possible" and is checked first, so an impossible action
## costs one boolean rather than a full curve evaluation. It is also what lets the
## decision log say "not offered" distinctly from "offered and scored zero".

@export var id: StringName = &""
@export var display_name: String = ""
## The existing executor this selects (`&"shoot"`, `&"move"`, `&"overwatch"`, ...),
## resolved by `UtilityExecutors`. Never a new implementation.
@export var executor_id: StringName = &""
## Named predicates the scoring context evaluates. All must hold. Open
## `StringName`s, resolved by the context, so a new gate is data plus one
## published predicate — never a branch in the scorer.
@export var preconditions: Array[StringName] = []
@export var considerations: Array[ConsiderationDef] = []
## The action's baseline appeal before any consideration applies. A profile
## scales this (`UtilityProfile.action_weight`).
@export var base_weight: float = 1.0
## Whether one turn may select this action more than once.
##
## Firing is repeatable and moving is not, but neither belongs in the planner as a
## branch. As data, "fire until the AP runs out" falls out of re-scoring plus
## `ActionQueue.enqueue` refusing the shot that cannot be paid for — no
## `MAX_SHOTS_PER_TURN` constant deciding it in advance.
@export var repeatable: bool = false
## This action IS the end of the turn, so nothing may be queued behind it.
##
## `HoldAction` defers to the next unit and `ShutdownAction` ends outright; both are
## "this IS the last action". The planner appends `EndTurnAction` as a backstop, and
## putting that behind one of these is a contradiction — hold means *do not end my
## turn yet*. It surfaced as an AI unit holding forever without the turn advancing.
##
## Data rather than an `is HoldAction` check, for the same reason `repeatable` is.
@export var ends_turn: bool = false
## Intelligence tiers this action is offered to. **Empty means every tier**, which
## is what the whole authored pool uses today — the gap between tiers is deliberately
## INFORMATION rather than the action list (`docs/11`).
##
## The field exists because the tier table does eventually restrict pools, and that
## must land as a `.tres` edit. Membership rather than a minimum rank, for the same
## reason `WorldView.MEMORY_TIERS` is a list: `intelligence_tier` is an open
## `StringName` with no defined ordering to take a minimum of.
@export var tiers: Array[StringName] = []


func _init(p_id: StringName = &"", p_executor_id: StringName = &"") -> void:
	id = p_id
	executor_id = p_executor_id
