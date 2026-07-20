class_name MeleeDelivery
extends RefCounted

## taskblock-25 Pass A (docs/PLAN.md "Phase M — Melee"): the closing half of
## a strike — lean if the weapon's own reach falls short, step in (a real
## move) if even a full lean can't close the distance. "No melee-specific
## exposure system": leaning is a POSE change (Poses.lean, MeleeReach.
## lean_needed), so the existing `Overwatch` torso check fires against it
## unchanged — this file only decides WHETHER to move/lean and asks that
## same existing check, never a second notion of exposure.


## Applies whatever lean `distance` requires (a pose change, `unit.cell`
## untouched) and returns the amount applied. `Poses.lean(0.0)` is
## `idle()`, so a weapon that covers `distance` on its own leaves `unit`'s
## pose exactly as it already was.
static func apply_lean(unit: Unit, weapon: Part, distance: float) -> float:
	var lean: float = MeleeReach.lean_needed(weapon, distance)
	unit.pose = Poses.lean(lean)
	return lean


## Leans `unit` toward a strike at `distance`, then — ONLY if that lean is
## nonzero — fires the exact same `Overwatch.check_trigger` a queued move's
## own mid-move hook fires, with `unit` itself as the exposed `mover`.
## Returns true if some overwatcher fired (the caller reads this exactly
## like `MoveAction`'s own interrupt: a striker hit mid-lean may die before
## ever landing the strike). A weapon that covers `distance` unleaned never
## calls `Overwatch.check_trigger` at all — "an un-exposed striker cannot
## be interrupted" is not merely "happened not to trigger," nothing is
## ever asked.
static func resolve_exposure(
	state: CombatState, unit: Unit, weapon: Part, distance: float
) -> bool:
	var lean: float = apply_lean(unit, weapon, distance)
	if lean <= 0.0:
		return false
	return Overwatch.check_trigger(state, unit)


## Snaps `unit`'s pose back to idle — the lean is momentary (docs/PLAN.md:
## a swing is a very short, very accurate shot), never a sticky stance like
## `Poses.prone()`. The strike itself (Pass C) resolves BEFORE this is
## called, while the leaned geometry is still live; called after, whether
## the strike hit or not.
static func reset_pose(unit: Unit) -> void:
	unit.pose = Poses.idle()


## The nearest cell `unit` can actually walk to (within its own `mp`) from
## which `target` is within `MeleeReach.total_reach()` — the step-in case,
## reach-gated rather than `StepOutPlanner`'s own cover-gated candidates,
## reusing its Dijkstra-reachability structure. Ties break by cell
## coordinate (x then y), same determinism convention `StepOutPlanner.
## sort_by_safety` already uses. Null (as a bare `Variant`) if nothing
## reachable is in range, or if `unit.cell` is already in range (nothing
## to step in for — the caller should lean/strike from where it stands).
static func find_step_in_cell(
	state: CombatState, unit: Unit, target: Unit, weapon: Part
) -> Variant:
	if MeleeReach.in_reach(unit.shell, weapon, Grid.distance_chebyshev(unit.cell, target.cell)):
		return null
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var best: Variant = null
	var best_cost: float = INF
	for cell: Vector2i in pf.reachable(unit.cell, unit.mp):
		if cell == unit.cell or cell == target.cell:
			continue
		var distance: float = Grid.distance_chebyshev(cell, target.cell)
		if not MeleeReach.in_reach(unit.shell, weapon, distance):
			continue
		var cost: float = Vector2(cell - unit.cell).length()
		if best == null or cost < best_cost or (cost == best_cost and _breaks_tie(cell, best)):
			best = cell
			best_cost = cost
	return best


static func _breaks_tie(candidate: Vector2i, current_best: Vector2i) -> bool:
	if candidate.x != current_best.x:
		return candidate.x < current_best.x
	return candidate.y < current_best.y
