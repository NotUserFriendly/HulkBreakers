class_name StepOutPlanner
extends RefCounted

## taskblock-18 Pass D (taskblock-19 Pass B: renamed Lean -> Step Out, pure
## rename, no behavior change — "lean" implied a specific motion and
## collided with a future literal-lean ability): "a covered unit pops out,
## fires, and returns as one automated motion... three normal actions in
## the ordered resolver, never a special-cased triple." `assemble_for_shoot()`
## is the ONE shared entry point (D2: "shared AI and player path... one
## implementation") — a human's SHOOT click and the AI's own ranged
## planner both call this, never two separate notions of "how do I step
## out to hit this."

const _ORTHOGONAL_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## D1: "the origin cell is covered from the target... the firing cell is
## NOT covered from the target... orthogonally adjacent." Reuses
## `Cover.is_covered_from` as-is for both halves — its own existing
## definition (no LoS at all counts as maximally covered, same as a
## physical blocker in the way) already matches "something blocks the
## shot from here" either way, so this is never a second, narrower cover
## check silently drifting from the one the AI's own cover-seeking
## already reads.
## taskblock-58 Pass C1: the convenience door — builds the field this one question needs. A
## caller asking about several firing cells against the **same** target wants
## `is_legal_step_out_against` and one build; the same relationship `UnitPicker.ray_box_t` has
## with `ray_box_hit`, and for the same reason: one implementation, two entry costs.
static func is_legal_step_out(
	state: CombatState, unit: Unit, origin_cell: Vector2i, firing_cell: Vector2i, target: Unit
) -> bool:
	return is_legal_step_out_against(
		state,
		unit,
		origin_cell,
		firing_cell,
		target,
		VisibilityField.build(state.grid, target.cell)
	)


## **One field, both halves.** Both questions are about the same threat, so they are two reads of
## one build rather than two builds — which is the whole reason `Cover` takes the field rather
## than fetching one itself.
static func is_legal_step_out_against(
	state: CombatState,
	unit: Unit,
	origin_cell: Vector2i,
	firing_cell: Vector2i,
	target: Unit,
	field: VisibilityField
) -> bool:
	if Grid.distance_manhattan(origin_cell, firing_cell) != 1:
		return false
	var view: WorldView = WorldView.full(state)
	if not Cover.is_covered_from(origin_cell, target.cell, view, unit, field):
		return false
	if Cover.is_covered_from(firing_cell, target.cell, view, unit, field):
		return false
	return true


## Every orthogonal, walkable neighbor of `origin_cell` that's a legal
## step-out firing cell toward `target` — unsorted; see `sort_by_safety` for
## "safest first."
static func candidate_step_out_cells(
	state: CombatState, unit: Unit, origin_cell: Vector2i, target: Unit
) -> Array[Vector2i]:
	var pf := Pathfinder.new(state.grid, unit.shell.can_climb())
	var candidates: Array[Vector2i] = []
	# taskblock-58 Pass C1: built once for the whole neighbourhood. Four neighbours asking the
	# same target the same question is four reads, not four builds.
	var field: VisibilityField = VisibilityField.build(state.grid, target.cell)
	for offset: Vector2i in _ORTHOGONAL_OFFSETS:
		var cell: Vector2i = origin_cell + offset
		if not state.grid.in_bounds(cell) or not pf.is_walkable(cell):
			continue
		if is_legal_step_out_against(state, unit, origin_cell, cell, target, field):
			candidates.append(cell)
	return candidates


## D2: "default to the safest legal firing cell (least exposed to known
## overwatch)." Fewest `Overwatch.would_trigger_at()` hits wins; ties
## break by cell coordinate (x then y) — deterministic, never dependent
## on `cells`' own incoming order.
static func sort_by_safety(
	state: CombatState, unit: Unit, cells: Array[Vector2i]
) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = cells.duplicate()
	sorted.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var exposure_a: int = Overwatch.would_trigger_at(state, unit, a).size()
			var exposure_b: int = Overwatch.would_trigger_at(state, unit, b).size()
			if exposure_a != exposure_b:
				return exposure_a < exposure_b
			if a.x != b.x:
				return a.x < b.x
			return a.y < b.y
	)
	return sorted


## D2: builds the Move(->firing)+Attack+Move(->origin) triple into
## `queue`, through the exact same `enqueue()`/`preview()` legality gate
## every other queued action goes through (the AI planner is the
## established precedent for composing a Move+Attack this way; a third
## leg follows identically). taskblock-27 Pass B2 (docs/SUPERSEDED.md):
## reverses this pass's own original "real MP/AP cost for both moves, no
## discount" — both automated legs are now `MoveAction.free` (no MP/AP
## either direction), for the AI and the player alike (the one shared
## entry point). The automation was always in ASSEMBLY, not cost; now
## the cost is waived too, not just the manual pathing.
##
## The return leg is pathed against `queue.preview(state)` (docs/09:
## never trust the raw grid mid-assembly) — `origin_cell` still shows as
## occupied by `unit` itself in the real, pre-move `state.grid`
## (Pathfinder.move_cost treats any occupied cell as unwalkable), so the
## SAME trap the retired planner's own reachability check had to work around for "a
## candidate's own cell is never walkable" — here the fix is reading the
## path off the preview where the outbound move has already actually
## relocated the unit, leaving origin genuinely vacant.
##
## Returns true only if the WHOLE triple enqueued legally. False leaves
## `queue` however far it got — the same "no further action, no silent
## rollback" contract `ActionQueue.enqueue` itself already has.
## taskblock-24 Pass A: `action_id` is which firing action to build for
## the middle leg — `ActionCatalog.build_firing_action` (the same seam
## the player's own action bar and the AI's own firing helper both read),
## never a hardcoded `AttackAction` regardless of what `weapon_id` actually
## provides (a chaingun's own step-out-and-burst used to silently
## downgrade to a single shot here).
static func build_triple(
	queue: ActionQueue,
	state: CombatState,
	unit: Unit,
	action_id: StringName,
	weapon_id: StringName,
	target: Unit,
	origin_cell: Vector2i,
	firing_cell: Vector2i
) -> bool:
	var out_pf := Pathfinder.new(state.grid, unit.shell.can_climb())
	var out_path: Array[Vector2i] = out_pf.astar(origin_cell, firing_cell)
	if out_path.size() < 2:
		return false
	if not queue.enqueue(MoveAction.new(unit, out_path, true), state):
		return false
	var firing_action: CombatAction = ActionCatalog.build_firing_action(
		action_id, unit, weapon_id, target.cell
	)
	if firing_action == null or not queue.enqueue(firing_action, state):
		return false

	var preview: CombatState = queue.preview(state)
	var back_pf := Pathfinder.new(preview.grid, unit.shell.can_climb())
	var back_path: Array[Vector2i] = back_pf.astar(firing_cell, origin_cell)
	if back_path.size() < 2:
		return false
	return queue.enqueue(MoveAction.new(unit, back_path, true), state)


## D2's own one-call entry point: "clicking SHOOT on an enemy the unit
## can't see but could from a legal step-out cell builds the triple
## automatically." Returns null when `unit.cell` is already NOT covered
## from `target` (D1's own trigger condition — a clear origin needs no
## step out, the caller should just queue a normal AttackAction) or when no
## legal step-out exists at all (nothing this can help with — never crash,
## never silently invent). Otherwise assembles the triple against the
## SAFEST candidate cell.
##
## Deliberately `is_covered_from`, never `AttackAction.is_legal()`: a
## blocker sitting in the shot's own path doesn't make firing from here
## ILLEGAL (`is_legal()` only checks LoS, not what a real ray would
## actually hit first) — it just means the shot would likely hit the
## blocker instead of the target, exactly the case a step out exists to
## avoid. Using `is_legal()` here would silently skip stepping out in
## precisely the situation D1/D2 describe.
##
## A caller that wants a DIFFERENT candidate (D2's own mouse-wheel
## cycle) doesn't call this — it calls `candidate_step_out_cells()`/
## `sort_by_safety()` directly and hands its own chosen cell to
## `build_triple()` instead.
static func assemble_for_shoot(
	state: CombatState, unit: Unit, action_id: StringName, weapon_id: StringName, target: Unit
) -> ActionQueue:
	var field: VisibilityField = VisibilityField.build(state.grid, target.cell)
	if not Cover.is_covered_from(unit.cell, target.cell, WorldView.full(state), unit, field):
		return null
	var candidates: Array[Vector2i] = candidate_step_out_cells(state, unit, unit.cell, target)
	if candidates.is_empty():
		return null
	var firing_cell: Vector2i = sort_by_safety(state, unit, candidates)[0]
	var queue := ActionQueue.new(unit)
	if not build_triple(queue, state, unit, action_id, weapon_id, target, unit.cell, firing_cell):
		return null
	return queue
