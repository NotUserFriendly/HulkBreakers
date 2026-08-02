class_name Surface
extends RefCounted

## taskblock-38 Pass A: one placed walkable/attached surface at a cell — the
## placement model's own unit. Distinct from a socket-tree Part (docs/01):
## this is CELL placement (a part plus its own real world height and
## facing), not body assembly. A cell holds an ORDERED `Array[Surface]`
## (`Grid.surfaces`) — multi-surface is the point, not a later extension: a
## catwalk over a floor is one cell with two walkable surfaces at different
## heights, reusing the same `cell -> Array` shape `Grid.field_items`
## already established rather than inventing a parallel container.

## taskblock-38 Pass C: the open tag vocabulary a placed surface's own
## `Part.tags` is checked against — never a closed enum (CLAUDE.md): a
## designer adds a new walkable, or walkable-and-ramp-shaped, surface by
## tagging a Part, no code edit. `WALKABLE_TAG` gates `Pathfinder`
## standability; `RAMP_TAG` is what makes a surface's own edge ride the
## corrected ramp profile (`RampGeometry`) instead of a flat top.
const WALKABLE_TAG: StringName = &"walkable"
const RAMP_TAG: StringName = &"ramp"

## taskblock-53 Pass C: the open tag a placed ladder carries. **Not `walkable`** —
## you climb a ladder, you do not stand on it, and tagging it walkable would make
## `Pathfinder` treat the ladder's own cell as a destination at the ladder's height.
const LADDER_TAG: StringName = &"ladder"

## How much height one ladder segment serves, above its own placed height.
##
## **Flagged, not designed** (CLAUDE.md). `UnitGeometry.LEVEL_HEIGHT` is 1.0 and
## `Pathfinder.MAX_CLIMB_LEVELS` is 1.0, so a bare face is climbable to 1.0; 2.0 is
## **two levels**, deliberately more than a bare face, because a ladder that reached
## no further than free-climbing would have no reason to exist. It also matches the
## rise the proving-ground map uses between its tiers, so one segment serves one tier.
## The real answer arrives with authored ladder art, whose box height should drive
## this instead of a constant.
const LADDER_SEGMENT_RISE: float = 2.0

var part: Part
## This surface's own real world elevation — tb37 already made height
## continuous, and that stands; not a level index.
var height: float
## Radians, the same convention `Unit.orientation`/`UnitGeometry.
## assembly_placements` already use — composes directly through the same
## transform chain with no translation step. What makes a `Ramp` directional
## (Pass C).
var facing: float


func _init(p_part: Part = null, p_height: float = 0.0, p_facing: float = 0.0) -> void:
	part = p_part
	height = p_height
	facing = p_facing


## The first surface at `cell` tagged walkable, or null. Multi-surface
## stacking (a catwalk over a floor) picks the FIRST one for now — nothing
## authors more than one surface per cell yet (catwalks are explicitly out
## of this taskblock's scope), so a general "which surface is a unit
## actually standing on" resolution is a flagged follow-on, not solved
## here.
static func first_walkable(surfaces: Array[Surface]) -> Surface:
	for surface: Surface in surfaces:
		if WALKABLE_TAG in surface.part.tags:
			return surface
	return null


## True if any surface placed at `cell` carries the ramp tag — the
## placement-model check for "stepping onto/off this cell is ordinary
## ramp movement, never a discrete Climb/HopDown action" (`Pathfinder`'s
## own "no special-casing" rule; `ClimbAction`/`HopDownAction`'s own
## "never onto a ramp" gate). taskblock-39 Pass C: replaces every direct
## `grid.get_terrain(cell) == Enums.TerrainType.RAMP` check — the shared
## formula so those callers and `Pathfinder`'s own ramp check can never
## quietly drift apart.
static func is_ramp_at(grid: Grid, cell: Vector2i) -> bool:
	for surface: Surface in grid.surfaces_at(cell):
		if RAMP_TAG in surface.part.tags:
			return true
	return false


## True if any surface placed at `cell` carries the ladder tag. The companion to
## `is_ramp_at`, and the same reason it exists: one shared formula, so
## `ClimbAction` and `Pathfinder` cannot quietly drift apart about what a ladder is.
static func has_ladder_at(grid: Grid, cell: Vector2i) -> bool:
	for surface: Surface in grid.surfaces_at(cell):
		if LADDER_TAG in surface.part.tags:
			return true
	return false


## The greatest height a climb starting at `cell` can reach on ladders alone, or
## `-1.0` when there is no ladder there.
##
## **Stacking falls out of taking the maximum**, rather than out of walking a chain
## of segments: three segments at heights 0, 2 and 4 report a reach of 6 because the
## topmost one does, and a gap in the middle is a map that is wrong in a way the
## author can see. Walking the attachment graph instead would answer the same
## question while being able to disagree with the heights actually placed.
static func ladder_reach_at(grid: Grid, cell: Vector2i) -> float:
	var reach: float = -1.0
	for surface: Surface in grid.surfaces_at(cell):
		if LADDER_TAG in surface.part.tags:
			reach = maxf(reach, surface.height + LADDER_SEGMENT_RISE)
	return reach


## True if a ladder standing at `from_cell` serves a climb up to `to_cell`'s own
## walkable height. **The ladder is at the climber's feet, not at the destination** —
## it is the thing you are standing against, and the ledge is what you reach.
static func ladder_serves_climb(grid: Grid, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var reach: float = ladder_reach_at(grid, from_cell)
	if reach < 0.0:
		return false
	var destination: Surface = first_walkable(grid.surfaces_at(to_cell))
	if destination == null:
		return false
	return destination.height <= reach + 0.001
