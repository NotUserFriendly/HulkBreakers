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
##
## ## taskblock-55 Pass B: a `Surface` is not a tile, it is where a tile is
##
## Worth stating outright, because the two are easy to run together and the
## distinction is what makes the placement model coherent:
##
## - A **tile** is the walkable `Part` itself — `ship_floor`, a discrete part
##   with authored `volume`, material, sockets and hp, exactly like any other.
##   It is a thing.
## - A **`Surface`** is the *record of one being placed*: which part, at what
##   `height`, at what `facing`. It is a fact about a cell.
## - A **cell** is the grid square, and carries no elevation of its own at all.
##
## So "height lives on the tile" is served by `height` living here: this is the
## only place that says where that part is, and `BoardView` and `RayCaster` both
## read it through the same `UnitGeometry.assembly_placements` call. A cell has
## a height only in the derived sense of `UnitGeometry.true_height_for_cell` —
## "how high is the tile you would be standing on here" — never as a property of
## its own.
##
## Not every `Surface` holds a tile: a ladder is placed the same way and is
## explicitly **not** walkable (`LADDER_TAG` below). `Surface` is the general
## placement; a tile is the walkable case.

## taskblock-38 Pass C: the open tag vocabulary a placed surface's own
## `Part.tags` is checked against — never a closed enum (CLAUDE.md): a
## designer adds a new walkable, or walkable-and-ramp-shaped, surface by
## tagging a Part, no code edit. `WALKABLE_TAG` gates `Pathfinder`
## standability.
##
## **`RAMP_TAG` is a rendering tag and nothing more, as of tb60 Pass A.** It still makes a
## surface's own edges ride the sloped `RampGeometry` profile instead of a flat top, and
## `CellInspection` still names the shape to a player. What it no longer does is grant
## traversal: the shared "stepping onto this cell is ordinary movement, never a
## Climb/HopDown" check that `Pathfinder`, `ClimbAction` and `HopDownAction` all read is
## **deleted**, replaced by `Unit.step_height()` compared against the actual rise. A ramp is
## content now: sloped geometry a unit walks over because it is shallow, not because it is
## labelled. Do not reintroduce a traversal reading of this tag; that is the categorical
## check the pass existed to remove.
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

## taskblock-58 Pass B: **the placement's own cell.** Until this pass a surface's position was
## its dictionary *key* in `Grid.surfaces` — so a floor could not exist except as something a
## cell held, and moving one meant delete-and-re-add. Now the placement carries where it is and
## the per-cell dictionary is an index built from that.
##
## **`Grid.add_surface` is the only writer.** A `Surface` that has not been placed has no
## meaningful cell, and letting a caller set one directly would put the placement and the index
## in a position to disagree — which is the entire failure mode an index has. `Grid.
## move_placement` is how a placed surface changes cells, because moving is an index update as
## much as it is a position change.
var cell: Vector2i = Vector2i.ZERO


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


## True if any surface placed at `cell` carries the ladder tag. One shared formula, so
## `ClimbAction` and `Pathfinder` cannot quietly drift apart about what a ladder is.
##
## **The last of its kind.** Its ramp-tag twin was deleted at tb60 Pass A, and the difference
## between the two is worth keeping in view. A ladder is a real mechanical category: it is
## *the route up that needs no capability*, and nothing about the geometry of the cell tells
## you it is there. A ramp was never that; it was a label on a shallow rise, and a shallow
## rise can simply be measured.
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
