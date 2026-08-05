class_name Cover
extends RefCounted

## taskblock-14 Pass B1, given its own file by taskblock-45 Pass B: "is a field
## object / ally / wall between it and the threat".
##
## The same shape as Overwatch's own torso-visibility check (`docs/09` taskblock06
## F2: an intervening-object query along a line), simplified to a bare cell walk
## because this is a movement HEURISTIC scoring many candidate cells per turn, not
## a live shot resolution. **It is deliberately not `ShotPlane`** — asking the
## canonical resolver per candidate cell is the exact cost taskblock-45 exists to
## delete, and "am I behind something" does not need the resolver's precision to
## be a useful preference.
##
## **Still flat, and that is a known open item rather than an oversight.** The blocker/unit walk
## below takes two `Vector2i` and has no height in it, so it asks a 2D question about a 3D world
## — the same flatness `Grid.opacity` had. taskblock-58 Pass C fixed *what cover sees* by routing
## the sight half through the geometry-backed `VisibilityField`; making cover itself directional
## in three dimensions is `PLAN.md`'s own item and belongs with the multi-grid work.
##
## **It moved out of the AI planner because three callers outlive that file.**
## `StepOutPlanner` reads it for both halves of its move/fire/return triple and
## `TacticsController` reads it for the player's own step-out affordance; neither
## is AI, and taskblock-45 Pass E deletes the planner they were reaching into.
## A shared predicate parked inside a file scheduled for deletion is how a "clear
## out completely, no hanging references" acceptance turns into a scramble.


## True when `candidate_cell` is covered from `threat_cell`: there is no line at all (maximally
## covered), or a real blocker or another living unit sits strictly between the two cells.
##
## `self_unit` never counts as its own cover. Standing on the threat's own cell is
## never cover either — there is no line left to interpose anything on.
##
## ## taskblock-58 Pass C1: the field answers the sight half, and it is required
##
## This called `LoS.has_los` **per candidate cell**, inside the scoring loop taskblock-43
## measured at 98.3 ms — and that call was itself a duplicate, because a `VisibilityField` for
## this same threat had already computed the answer for every cell this turn. So reading the
## field is the correctness fix and the cost mitigation at once: one `false` bit test replaces a
## line walk that, once sight became geometry, would have been a full ray march per candidate.
##
## **`field` is required rather than optional.** An optional one means two branches deciding the
## same thing, differently, depending on what the caller happened to have lying about — which is
## the arrangement this pass exists to delete. Every caller either already holds a field for this
## threat (`UtilityContext`) or builds one and reuses it across its own several calls.
##
## The field is deliberately over-inclusive: `allows()` false is conclusive, true means "ask the
## real resolver". Only the conclusive direction is used here, so cover is never claimed on the
## strength of a maybe.
static func is_covered_from(
	candidate_cell: Vector2i,
	threat_cell: Vector2i,
	view: WorldView,
	self_unit: Unit,
	field: VisibilityField
) -> bool:
	if candidate_cell == threat_cell:
		return false
	if not field.allows(candidate_cell):
		return true
	var cells: Array[Vector2i] = Grid.line(threat_cell, candidate_cell)
	# taskblock-58 Pass C1: **hoisted out of the cell walk.** `units_visible_to` was called once
	# per intermediate cell of the line, recomputing the same set every step — wasteful when a
	# restricted view answered it with an opacity lookup per unit, and expensive now that it
	# answers with a real sight line. The set does not depend on which cell is being examined.
	var visible: Array[Unit] = view.units_visible_to(self_unit)
	for i in range(1, cells.size() - 1):
		var cell: Vector2i = cells[i]
		if view.grid.blockers.has(cell):
			return true
		for other: Unit in visible:
			if other != self_unit and other.alive and other.cell == cell:
				return true
	return false
