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
## taskblock-45 Pass B: whether one turn may select this action more than once.
##
## Firing is repeatable — the old planner spent a turn on up to three shots at the
## same target — and moving is not, but neither fact belongs in the planner as a
## branch. Expressed as data, "fire until the AP runs out" falls out of re-scoring
## and `ActionQueue.enqueue` refusing the shot that cannot be paid for, with no
## `MAX_SHOTS_PER_TURN` constant deciding it in advance.
@export var repeatable: bool = false
## taskblock-45 Pass E: this action IS the end of the turn, so nothing may be
## queued behind it.
##
## `HoldAction` defers the turn to the next unit and `ShutdownAction` ends it
## outright; both are documented as "this IS the last action". The planner appends
## `EndTurnAction` to every turn as a backstop, and appending it behind one of
## these is a contradiction — hold means *do not end my turn yet*, and ending it
## anyway threw the deferral away. It surfaced as an AI unit that held forever
## without the turn advancing.
##
## Data rather than an `is HoldAction` check in the planner, for the same reason
## `repeatable` is: the next action with this property should be a `.tres` field,
## not a new branch.
@export var ends_turn: bool = false
## Intelligence tiers this action is offered to. **Empty means every tier**, which
## is what the whole Pass B pool uses: the gap this block stands up between
## `MINDLESS` and `TRAINED` is deliberately INFORMATION, not the action list
## (`docs/PLAN.md`: gating actions alone produces a unit with fewer options that
## still plays them optimally, which reads as *limited* rather than dumb).
##
## The field exists because `PLAN.md`'s tier table does eventually restrict pools
## — Elite alone gets bait and ambush — and that must land as a `.tres` edit rather
## than a code edit. Membership rather than a minimum rank, for the same reason
## `WorldView.MEMORY_TIERS` is a list: `intelligence_tier` is an open `StringName`
## with no defined ordering to take a minimum of.
@export var tiers: Array[StringName] = []


func _init(p_id: StringName = &"", p_executor_id: StringName = &"") -> void:
	id = p_id
	executor_id = p_executor_id
