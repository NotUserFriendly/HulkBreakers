class_name ResolutionSpeed
extends RefCounted

## taskblock-18 A2: the single ordering axis every contender in the
## re-validating resolver (Pass B) is sorted by — LOWER resolves first
## ("time to resolve," CombatAction.speed()'s own reframed direction, see
## its doc comment). Built from three terms:
##   resolution_speed = base_action_speed - action_family_bonus - personal_speed
## `base_action_speed` is `action.speed(state)` (taskblock-06 E, kept
## unchanged as the per-action axis). `action_family_bonus` (A3) and
## `personal_speed` (A1, on the acting unit's own Matrix) both subtract —
## a bonus/higher personal speed makes the action resolve SOONER. Routed
## through StatResolver (docs/08: "nothing computes a final stat outside
## the pipeline") so a future perk/effect shows its own provenance line,
## the same as damage or recoil.

const STAT_ID: StringName = &"resolution_speed"


## `action.unit_id()`'s own unit, looked up fresh through `state` (docs/09:
## never trust a bare Unit reference across states) — a preview clone
## shares the id, not the object. A missing unit (an action with no real
## `unit_id()` override, e.g. the base `CombatAction` itself) contributes
## no personal_speed/family_bonus term; `base_action_speed` alone still
## resolves.
static func resolve(action: CombatAction, state: CombatState) -> StatValue:
	return _resolve(action.speed(state), action, state.find_unit(action.unit_id()))


## taskblock-18 C1: a unit's own INITIATIVE, for turn order — the exact
## same formula, just with no action chosen yet (TACTICS hasn't happened
## for this unit's turn) so `base_action_speed` is 0 and
## `action_family_bonus` is queried with a null action (today's hook
## ignores its action argument regardless, A3). "The same speed the
## resolver uses, not a second stat."
static func initiative(unit: Unit) -> StatValue:
	return _resolve(0.0, null, unit)


static func _resolve(base_action_speed: float, action: CombatAction, unit: Unit) -> StatValue:
	var context := ResolverContext.new()
	context.base = base_action_speed

	if unit != null:
		var sources: Array[ModSource] = []
		var family_bonus: float = action_family_bonus(action, unit)
		if not is_zero_approx(family_bonus):
			sources.append(
				ModSource.new(
					"Action Family Bonus", Enums.ModSourceKind.PERK, Enums.ModOp.ADD, -family_bonus
				)
			)
		if not is_zero_approx(unit.matrix.personal_speed):
			sources.append(
				ModSource.new(
					"Personal Speed",
					Enums.ModSourceKind.SKILL,
					Enums.ModOp.ADD,
					-unit.matrix.personal_speed
				)
			)
		context.extra_sources = sources

	return StatResolver.resolve(STAT_ID, context)


## A3 hook: "Quickdraw isn't a lane-reorder, it's a flat bonus to one
## action family" — Ghost Step/Sixth Sense/Quickdraw are all DATA on this
## hook (a unit's `matrix.active_perks()` naming a family + magnitude),
## built when the perk system itself is (out of scope here, taskblock-18's
## own scope fence). Returns 0.0 today: no perk carries a family bonus yet,
## so every action's resolution speed is `base_action_speed -
## personal_speed` until perks exist to read here.
static func action_family_bonus(_action: CombatAction, _unit: Unit) -> float:
	return 0.0
