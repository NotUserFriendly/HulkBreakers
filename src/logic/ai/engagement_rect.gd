class_name EngagementRect
extends RefCounted

## taskblock-43 Pass B: which reachable cells `UnitAI._pick_engagement_position`
## is worth scoring at all.
##
## The planner used to score every cell `Pathfinder.reachable` returned — a blob
## centred on the acting unit, most of which faces away from the fight. This
## keeps the portion inside a rectangle with two corners on the unit and its
## target, which is roughly the half to the quarter facing the target. It
## compounds with the Pass A score early-out rather than replacing it: A makes a
## hopeless cell cheap to reject, this stops it being a candidate at all.
##
## **Its own file rather than more lines in `unit_ai.gd`**, which was already at
## the linter's file cap after five bumps. This is pure candidate-set geometry
## with no planner state in it, so it separates cleanly — and it takes only a
## `target_distance` float rather than reaching back for `UnitAI._target_distance`
## itself, keeping the dependency one-directional (no `class_name` cycle) and
## leaving that function the single source of what the standoff distance is.

## How far the rectangle is padded SIDEWAYS, beyond the box spanned by the acting
## unit and its target. "A couple of cells laterally" — enough to keep a
## sidestep-into-cover candidate, not enough to keep the whole reachable blob.
## Flagged, not a tuned design number. The far side is padded separately and
## asymmetrically; see `cull`.
const LATERAL_PAD := 2


## FILTERS `reachable`, and never replaces it as the source — so a cell that
## isn't genuinely walkable this turn still cannot appear in the result.
##
## **Not identical output, unlike Pass A.** A cell outside the rect could have
## won before; that is the trade this makes deliberately, and its honest size is
## measured (`tools/bench_ai_planning.gd`) rather than assumed.
##
## **The pad is asymmetric on purpose, and this is the part most easily got
## wrong.** A unit whose standoff distance exceeds its current distance to the
## target wants to move AWAY — and those cells sit behind it, outside a box drawn
## between the two, in exactly the direction a symmetric pad is thinnest. So the
## far side (beyond the unit, away from the target) is extended by
## `target_distance` while the other three sides get only `LATERAL_PAD`. Without
## this, the optimisation quietly shoves long-range units into knife fights — and
## `test_full_mission.gd`'s completion canary may well still pass while it does,
## which is why `test_engagement_rect_cull.gd` tests the retreat case directly.
##
## The extension is unconditional rather than gated on "does this unit actually
## want to retreat right now": a superset is always sound here, and a predicate
## re-deriving that intent would be a second place for the scorer's own judgement
## to live and drift from.
##
## An axis where unit and target share a coordinate has no "away" direction along
## it at all — retreating happens along the other axis — so it takes only the
## lateral pad, which is what the per-axis sign already produces.
##
## **`unit.cell` is always retained** regardless of the rect: it is the standing
## fallback, `_pick_engagement_position` seeds `best_cell` with it, and
## `_plan_ranged`'s step-out fallback is gated on `best_cell == unit.cell`. It is
## a corner of the rectangle and so cannot be culled by the geometry as written;
## the guard is for a direct caller handing in an arbitrary `reachable`.
static func cull(
	unit: Unit, enemy: Unit, target_distance: float, reachable: Array[Vector2i]
) -> Array[Vector2i]:
	var min_x: int = mini(unit.cell.x, enemy.cell.x) - LATERAL_PAD
	var max_x: int = maxi(unit.cell.x, enemy.cell.x) + LATERAL_PAD
	var min_y: int = mini(unit.cell.y, enemy.cell.y) - LATERAL_PAD
	var max_y: int = maxi(unit.cell.y, enemy.cell.y) + LATERAL_PAD
	var far_pad: int = int(ceilf(target_distance))
	if far_pad > 0:
		var away: Vector2i = unit.cell - enemy.cell
		if away.x > 0:
			max_x += far_pad
		elif away.x < 0:
			min_x -= far_pad
		if away.y > 0:
			max_y += far_pad
		elif away.y < 0:
			min_y -= far_pad

	var culled: Array[Vector2i] = []
	for cell: Vector2i in reachable:
		if cell.x >= min_x and cell.x <= max_x and cell.y >= min_y and cell.y <= max_y:
			culled.append(cell)
	if not culled.has(unit.cell):
		culled.append(unit.cell)
	return culled
