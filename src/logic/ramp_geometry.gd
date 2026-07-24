class_name RampGeometry
extends RefCounted

## taskblock-38 Pass C: docs/PLAN.md's settled ramp profile — 22.5 degrees,
## +0.5 level per tile, two tiles per full level. A ramp SURFACE's own four
## edges, relative to its OWN base height (its `Grid.level` endpoint —
## tb37's "authored at the lower endpoint" convention, unchanged): the low
## edge sits at the base itself, the high edge a full +0.5 level above it,
## and the two lateral edges at the +0.25 midpoint. A unit standing on the
## tile (at its own center, not an edge) sits at that same +0.25 midpoint —
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
## The height a unit standing on the tile itself (its own center) rests
## at — the same value `MapGen` bakes into a ramp `Surface.height`.
const STANDING_OFFSET: float = UnitGeometry.LEVEL_HEIGHT * 0.25


static func edge_heights(base_height: float, facing: float) -> Dictionary:
	return {
		"low": base_height + LOW_OFFSET,
		"high": base_height + HIGH_OFFSET,
		"left": base_height + LATERAL_OFFSET,
		"right": base_height + LATERAL_OFFSET,
		"facing": facing,
	}
