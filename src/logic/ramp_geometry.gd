class_name RampGeometry
extends RefCounted

## > **A RAMP IS NOT A SLOPE YET. Read this before using anything here.** taskblock-69 follow-up.
## >
## > **Nothing in `src/` calls `edge_heights`.** The profile below is a rule that was built and
## > tested before its first consumer (tb38 Pass C's own stated posture) and has never acquired
## > one. `ramp.tres` authors a **flat 0.2 slab whose `volume` is byte-identical to
## > `ship_floor.tres`'s**, so a placed ramp is a floor tile that `CellInspection` labels `RAMP`.
## >
## > **A ramp's `facing` does nothing at all today**, which is easy to miss because several
## > comments still say otherwise. `Surface.facing` never reached the pathfinder, tb60 Pass A
## > deleted the traversal reading of `Surface.RAMP_TAG`, and `MapGen` builds stairs out of
## > ordinary `ship_floor` tiles at fractional heights and records no facing for them. Even the
## > function below ignores the argument — `test_ramp_geometry.gd::
## > test_edge_heights_are_unaffected_by_facing` is the assertion that says so.
## >
## > **Ramps are meant to become real**, not to go away — `PLAN`'s *Ramps become real slopes*
## > item is where that work lives, and this file is the half of it that already exists. Until
## > then, treat a `ramp` placement as a labelled floor and do not build anything on the
## > assumption that its facing is read.
##
## taskblock-38 Pass C: docs/PLAN.md's settled ramp profile — 22.5 degrees,
## +0.5 level per cell, two cells per full level. A ramp SURFACE's own four
## edges, relative to its OWN base height (its `Grid.level` endpoint —
## tb37's "authored at the lower endpoint" convention, unchanged): the low
## edge sits at the base itself, the high edge a full +0.5 level above it,
## and the two lateral edges at the +0.25 midpoint. A unit standing on the
## cell (at its own center, not an edge) sits at that same +0.25 midpoint —
## `UnitGeometry.true_height_for_cell`'s own ramp offset.
##
## `facing` (radians, `Surface.facing`'s own convention) is the direction of
## ASCENT — which real-world edge ends up "high" is a VIEW-layer concern
## (composing this against the surface's world transform) resolved later;
## this returns the four RELATIVE heights alone, in the ramp's own local
## frame, unaffected by which way it happens to face — proven now, even
## though nothing renders it yet, the same "build and test the rule before
## the first real consumer" posture Pass A's attachment grammar used.
const LOW_OFFSET: float = 0.0
const HIGH_OFFSET: float = UnitGeometry.LEVEL_HEIGHT * 0.5
const LATERAL_OFFSET: float = UnitGeometry.LEVEL_HEIGHT * 0.25
## The height a unit standing on the cell itself (its own center) would rest at, once a ramp is
## a slope.
##
## **`MapGen` no longer bakes this into anything**, which is what this line used to say. tb60
## Pass A dissolved `MapGenScratch.CellKind.RAMP` into `OPEN` at a fractional level and deleted
## the offset with it — *"a cell's height is now simply its height"* — so nothing in `src/`
## reads this constant. `GridFixture.stepped` still uses it to build a ramp-shaped fixture.
const STANDING_OFFSET: float = UnitGeometry.LEVEL_HEIGHT * 0.25


static func edge_heights(base_height: float, facing: float) -> Dictionary:
	return {
		"low": base_height + LOW_OFFSET,
		"high": base_height + HIGH_OFFSET,
		"left": base_height + LATERAL_OFFSET,
		"right": base_height + LATERAL_OFFSET,
		"facing": facing,
	}
