class_name UtilityExecutors
extends RefCounted

## taskblock-45 Pass B: the one place a `UtilityActionDef.executor_id` becomes a
## real `CombatAction`.
##
## **This is an arming seam, not a second action layer.** `src/logic/actions/`
## already holds twenty tested executors and none of them are reimplemented here;
## this file is to the AI exactly what `TacticsController`'s arm-and-click path is
## to the player — the step that turns "I have chosen to shoot" into the concrete
## `AttackAction` instance. Everything it can build, it builds through
## `ActionCatalog`, which is the same seam the player's action bar reads, so the AI
## can never fire something a player's own bar would not have offered.
##
## ## The `&"hold"` collision, stated rather than worked around
##
## `ActionCatalog`'s `&"hold"` is **`GrindAction`** — taskblock-25's many-hit melee
## grind, which took the taskblock's own payload name. taskblock-19's
## `HoldAction` ("defer to the next ally") has no catalog id at all and never
## appears on the action bar. So the utility action that means *hold position* uses
## the executor id `&"hold_position"`, and the two stay distinguishable by name
## instead of by which caller happened to ask. Adding `&"hold_position"` to
## `ActionCatalog.defs()` would have been the other fix and is wrong: that registry
## is what the PLAYER is offered, and this is not a button.

## Executor ids this file resolves itself, because `ActionCatalog` has no entry for
## them. Everything not on this list is delegated to the catalog unchanged.
const MOVE := &"move"
const HOLD_POSITION := &"hold_position"
## taskblock-45 Pass D: the mission executors. `GatherAction` and `ExtractAction`
## are existing, tested classes; naming them here is what lets a mission be
## finished by the same scorer that fights, with no non-combat branch anywhere.
const GATHER := &"gather"
const EXTRACT := &"extract"

## `ActionCatalog`'s own `&"hold"`, named here only so the collision above is
## greppable from both sides — nothing in this file builds it.
const CATALOG_HOLD := &"hold"


## The concrete action `action` names, or null when it cannot be built at all.
##
## **Null is a legitimate answer and never an error.** A scorer can select an
## action whose executor declines to instantiate — a weapon that provides no legal
## firing action, a move to the cell already occupied — and the caller simply
## enqueues nothing, the same "no further action, no silent rollback" contract
## `ActionQueue.enqueue` and `ActionCatalog.build_firing_action` already have.
##
## Legality is deliberately NOT checked here. `ActionQueue.enqueue` validates
## against a speculative preview with every already-queued action replayed onto it,
## which is the only place that can answer "is this legal AFTER the move I queued
## in front of it" — asking here would answer from the pre-move cell and be wrong
## in exactly the case that matters.
static func build(
	action: UtilityActionDef,
	unit: Unit,
	target: Unit,
	path: Array[Vector2i],
	weapon_id: StringName,
	mission: MissionState = null
) -> CombatAction:
	if action == null:
		return null
	match action.executor_id:
		MOVE:
			return MoveAction.new(unit, path) if path.size() >= 2 else null
		HOLD_POSITION:
			return HoldAction.new(unit)
		GATHER:
			if mission == null or mission.resource_nodes.is_empty():
				return null
			return GatherAction.new(mission, unit, mission.resource_nodes.keys()[0])
		EXTRACT:
			return ExtractAction.new(mission, unit) if mission != null else null
		&"overwatch":
			return (
				ActionCatalog.build_untargeted_action(&"overwatch", unit, weapon_id)
				if weapon_id != &""
				else null
			)
		_:
			if target == null or weapon_id == &"":
				return null
			return ActionCatalog.build_firing_action(
				action.executor_id, unit, weapon_id, target.cell
			)


## Whether `action` moves the unit, and therefore needs a path built for it before
## `build` can produce anything. Asked by the planner so the path — the one
## genuinely expensive thing per candidate — is computed for the WINNER only,
## never for every candidate scored.
static func needs_path(action: UtilityActionDef) -> bool:
	return action != null and action.executor_id == MOVE
