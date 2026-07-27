class_name UtilityActionDef
extends Resource

## taskblock-45 Pass A: one thing a unit might choose to do, and how it decides
## whether it wants to.
##
## **This is a selection layer over an existing action layer.** `src/logic/actions/`
## already holds twenty tested executors — attack, burst, move, climb, overwatch,
## extract, slash, stab, hold, repair. `executor_id` NAMES one of them through the
## same `ActionCatalog` seam the player's own action bar reads; nothing here
## reimplements what an action does, only what makes it appealing.
##
## **Preconditions are separate from considerations on purpose.** A consideration
## answers "how much do I want this" and can veto by returning zero; a
## precondition answers "is this even possible" and is checked first, so an
## impossible action costs one boolean rather than a full curve evaluation and a
## log entry. Keeping them separate is also what lets the decision log say "not
## offered" distinctly from "offered and scored zero", which are different
## answers to "why didn't it do that".

@export var id: StringName = &""
@export var display_name: String = ""
## The existing executor this selects, by `ActionCatalog` id (`&"shoot"`,
## `&"move"`, `&"overwatch"`, ...). Never a new implementation.
@export var executor_id: StringName = &""
## Named predicates the scoring context evaluates. All must hold. Open
## `StringName`s, resolved by the context, so a new gate is data plus one
## published predicate — never a branch in the scorer.
@export var preconditions: Array[StringName] = []
@export var considerations: Array[ConsiderationDef] = []
## The action's baseline appeal before any consideration applies. A profile
## scales this (`UtilityProfile.action_weight`).
@export var base_weight: float = 1.0


func _init(p_id: StringName = &"", p_executor_id: StringName = &"") -> void:
	id = p_id
	executor_id = p_executor_id
