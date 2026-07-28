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
## **It moved out of the AI planner because three callers outlive that file.**
## `StepOutPlanner` reads it for both halves of its move/fire/return triple and
## `TacticsController` reads it for the player's own step-out affordance; neither
## is AI, and taskblock-45 Pass E deletes the planner they were reaching into.
## A shared predicate parked inside a file scheduled for deletion is how a "clear
## out completely, no hanging references" acceptance turns into a scramble.


## True when `candidate_cell` is covered from `threat_cell`: the line is fully
## opaque (no LoS at all — maximally covered), or a real blocker or another living
## unit sits strictly between the two cells.
##
## `self_unit` never counts as its own cover. Standing on the threat's own cell is
## never cover either — there is no line left to interpose anything on.
static func is_covered_from(
	candidate_cell: Vector2i, threat_cell: Vector2i, view: WorldView, self_unit: Unit
) -> bool:
	if candidate_cell == threat_cell:
		return false
	if not LoS.has_los(view.grid, threat_cell, candidate_cell):
		return true
	var cells: Array[Vector2i] = Grid.line(threat_cell, candidate_cell)
	for i in range(1, cells.size() - 1):
		var cell: Vector2i = cells[i]
		if view.grid.blockers.has(cell):
			return true
		for other: Unit in view.units_visible_to(self_unit):
			if other != self_unit and other.alive and other.cell == cell:
				return true
	return false
