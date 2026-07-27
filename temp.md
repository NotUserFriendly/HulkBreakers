Proceed as proposed — the shape is right — but two of the four "pass-through" fields aren't pass-through, and the guard as described has a hole.

CC's core call is correct and worth affirming: tiers gate knowledge about units, not geometry. A Mindless unit still knows where walls are; what it doesn't know is who's behind them. And a unit planning against a believed enemy position asks the resolver about geometry to a cell — the resolver answers objectively, and the unit's error lives in choosing the wrong cell, not in degraded geometry. So the resolver never needs a filtered world, and ShotPlane staying canonical is fully compatible with a gated view. The literal "not reachable" reading was mine being imprecise about what shouldn't be reachable.

Three amendments before it's built, since it's 62 call sites:

1. grid is not geometry. Grid carries occupant_id: Array[int] and get_occupant_id(cell) right alongside blockers, surfaces, and opacity. Hand the planner a raw grid and it can read the position of every unit on the board — including ones units_visible_to(observer) just filtered out. That's the whole seam bypassed by a one-line accessor, and it'd pass a guard that only watches the four CombatState fields.

Occupancy is exactly the thing tiers gate. Either the view exposes a geometry-only facade, or the guard forbids occupant_id/get_occupant_id from the planner path and occupancy arrives solely through units_visible_to. The second is cheaper and probably right, but it has to be deliberate rather than implied.

2. batch_plans is gated information, not infrastructure. The team blackboard is a Trained-and-above capability in the tier table — a Grunt doesn't get one. So batch plans belong on the observer-parameterized side with units_visible_to, not the free side with round_number. Something like batch_objective_for(observer), returning nothing for a unit whose tier lacks blackboard access. Today it returns everything and nothing changes; it means part two doesn't have to move it.

3. The resolver door needs a guard on derived access, or it's a hole rather than a door. view.resolution_state() handed to ShotPlane is legal. view.resolution_state().units is the entire seam defeated, and a guard watching direct field access on unit_ai.gd won't see it.

The rule that closes it is mechanical and testable: resolution_state() may appear only as a bare argument, never followed by a dot. That's greppable in the same shape as the guards from tb40 and tb41, and it makes the distinction enforceable rather than conventional. Worth naming it so misuse looks wrong at the call site too — canonical_state_for_resolvers() reads as a door; resolution_state() reads as an accessor.

The general form of all three: the seam's boundary isn't CombatState versus not-CombatState, it's knowledge-about-units versus everything else — and that line runs through Grid and through BatchPlan rather than around them. Worth writing at the seam in exactly those terms, since that's the sentence that tells part two where new fields go.
