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
## traversal: the shared "stepping onto this cell is ordinary movement, never a climb or a
## drop" check that `Pathfinder` and the two discrete vertical actions all read is
## **deleted**, replaced by `Unit.step_height()` compared against the actual rise. A ramp is
## content now: sloped geometry a unit walks over because it is shallow, not because it is
## labelled. Do not reintroduce a traversal reading of this tag; that is the categorical
## check the pass existed to remove. (tb62 Pass C1 retired both of those actions outright —
## a climb is an ordinary `MoveAction` step now — so `Pathfinder` is the only reader left.)
const WALKABLE_TAG: StringName = &"walkable"
const RAMP_TAG: StringName = &"ramp"

## taskblock-53 Pass C: the open tag a placed ladder carries. **Not `walkable`** —
## you climb a ladder, you do not stand on it, and tagging it walkable would make
## `Pathfinder` treat the ladder's own cell as a destination at the ladder's height.
const LADDER_TAG: StringName = &"ladder"

## tb62 Pass B: the open tag a placed **mag lift pad** carries. A lift is a *pair* of
## these — one on the low cell, one on the raised cell it serves — and stepping between
## them is a teleport costing 1 AP (`MagLiftAction`), never a traversal.
##
## **Not `walkable`, for the same reason a ladder is not**: the pad is a terminus marker,
## not a floor. Standing at either end is the ordinary floor's job, and tagging the pad
## walkable would put a second walkable surface in a cell that already has one — which
## `first_walkable` resolves by taking whichever was placed first, i.e. by accident.
##
## **The pad authors no `volume` at all**, which is what makes *"neither surface blocks
## shots"* structurally true rather than approximately true. `UnitGeometry.
## assembly_placements` yields nothing for it, so `RayCaster`, `ShotPlane` and
## `BoardView._build_tiles` all have nothing to find — there is no thin box to get the
## thickness of wrong. Its whole appearance is `BoardView`'s mag-lift overlay, which is an
## annotation about a cell rather than a thing at an elevation (`OverlayMarkers`).
const MAG_LIFT_TAG: StringName = &"mag_lift"

## How much height one ladder segment serves, above its own placed height.
##
## **Flagged, not designed** (CLAUDE.md). `UnitGeometry.LEVEL_HEIGHT` is 1.0 and
## `Pathfinder.MAX_CLIMB_LEVELS` is 1.0, so a bare face is climbable to 1.0; 2.0 is
## **two levels**, deliberately more than a bare face, because a ladder that reached
## no further than free-climbing would have no reason to exist. It also matches the
## rise the proving-ground map uses between its tiers, so one segment serves one tier.
## The real answer arrives with authored ladder art, whose box height should drive
## this instead of a constant.
## How much rise one ladder segment covers, and how tall `ladder.tres`'s own box is — the two
## must agree or a ladder reaches somewhere its mesh does not.
##
## **2.0 -> 1.0 at tb64 Pass F (`BR63.01`), on the supervisor's call.** A 2.0 segment overshot its
## own destination by a full level on the commonest rise the generator makes: `_stamp_ladder`
## computes `ceil(rise / LADDER_SEGMENT_RISE)`, so a 1.0 rise got one piece standing 1.0 proud of
## the floor it served.
##
## **Climb cost does not move, and did not need re-scaling.** `Pathfinder.move_cost` prices a
## ladder edge as `ceil(CLIMB_COST * level_delta * LADDER_COST_SCALE)` — by **rise**, never by
## segment count — so halving this changes how many pieces stand and nothing about what climbing
## costs. The instruction was "hold climb cost steady"; it is held by the arithmetic already
## being height-based, not by a compensating constant.
const LADDER_SEGMENT_RISE: float = 1.0

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
## `Pathfinder` and anything else asking cannot quietly drift apart about what a ladder is.
## **tb62 Pass C1 removed the drift this line was guarding against by removing the second
## reader**: `ClimbAction` had its own copy of the cost formula, unceiled where
## `move_cost` ceils, and it is retired.
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


## **True if any vertical route stands at `cell` — a ladder or a mag lift pad.** taskblock-63
## Pass E, `BR62.03`.
##
## The supervisor's first play of taskblock-62's work found **both in the same cell**, and the
## cause was the shape this closes: the generator's own refusal
## (`MapGen._pad_in_reach_of`) knew about *pads* and nothing else, so a repair pass could
## stamp a ladder into a cell that already carried a lift, or the reverse. Two stampers, two
## private ideas of "is this cell already a way up".
##
## **One predicate, asked by both.** A cell holds at most one route up, which is also what
## makes a route legible: a player reading a cell should get one answer about how to leave it
## vertically, not two overlapping ones.
static func has_vertical_route_at(grid: Grid, cell: Vector2i) -> bool:
	return has_ladder_at(grid, cell) or has_mag_lift_at(grid, cell)


## tb62 Pass B: true if any mag lift pad is placed at `cell`. The shape's twin is
## `has_ladder_at`, and deliberately so — one shared formula per route-up, so an action
## and the pathfinder cannot develop separate ideas of what a lift is.
static func has_mag_lift_at(grid: Grid, cell: Vector2i) -> bool:
	for surface: Surface in grid.surfaces_at(cell):
		if MAG_LIFT_TAG in surface.part.tags:
			return true
	return false


## **The other end of the lift whose pad stands at `from_cell`, or null.**
##
## A lift is a *pair*: a pad on the low cell and a pad on the raised cell it serves, both
## placed by the same generator branch that would have stood a ladder. This resolves the
## pair by looking for the other pad among `from_cell`'s neighbours, and it is the one
## place that does — `MagLiftAction` and anything scoring a lift read this rather than
## re-deriving the pairing.
##
## ## It runs both ways, and that is the supervisor's call (2026-08-09)
##
## An earlier version of this resolved **upward only**, on the reasoning that free descent
## already exists so a lift must not compete with it. **That was wrong about what the two
## are for.** The supervisor: *"Hop down's advantage is that it can happen anywhere, mag
## lift down is only in a few places but is 'cheaper'."* The distinction is **availability**,
## not direction — a hop-down works off any ledge and a lift works only where one was built,
## which is what makes the lift affording a better deal at its own two cells fair rather
## than strictly better.
##
## **Worth stating so nobody later reads "cheaper" and finds the numbers disagreeing:** a
## hop-down costs `Pathfinder.HOP_DOWN_COST` (1 MP) and a ride costs 1 AP, and 1 AP buys
## `mp_per_ap` MP, so a *short* descent is not literally cheaper by the ride. Where the ride
## is cheaper is depth — a hop-down beyond `MAX_HOP_DOWN_LEVELS` is not a legal edge at all,
## so a four-level drop costs one action by lift and is impossible without one. Flagged
## rather than tuned; the cost currencies are the design, the numbers behind them are not
## this pass's to pick.
##
## **The nearest height wins, in either direction.** Two lifts standing near each other on a
## terraced board would otherwise be able to claim each other's pads; taking the smallest
## real height difference keeps a pair together, and the cell-order tie-break keeps it
## deterministic rather than dependent on neighbour iteration order.
##
## Returns the destination CELL rather than the pad `Surface`, because that is what an
## action needs and what a caller can do anything with. The pad itself is a marker; the
## cell is the position.
static func mag_lift_destination(grid: Grid, from_cell: Vector2i) -> Variant:
	var here: Surface = _mag_lift_at(grid, from_cell)
	if here == null:
		return null
	# **taskblock-63 Pass E: read off the pad, not searched for.** This used to sweep the eight
	# neighbours for a pad at a different height and take the closest — pairing *inferred from
	# proximity*, which is what taskblock-62's cross-linked-chain failure came out of: three
	# pads near each other have several defensible answers and the tie-break returns one of
	# them with a straight face.
	#
	# **The pad now says where it goes**, in the `facing` its `Surface` has always carried and
	# `MapPlacement` has always round-tripped, so no new field and no new format. A partner
	# recorded at placement time cannot cross-link, and the honest failure — a pad pointing at
	# a cell with no pad on it — is a `null` rather than a plausible wrong answer.
	var partner: Vector2i = from_cell + _facing_step(here.facing)
	if _mag_lift_at(grid, partner) == null:
		return null
	return partner


## The pad placed at `cell`, or null. Distinct from `has_mag_lift_at`, which answers the
## boolean every precondition wants; this is for the callers that need the placement itself.
static func _mag_lift_at(grid: Grid, cell: Vector2i) -> Surface:
	for surface: Surface in grid.surfaces_at(cell):
		if MAG_LIFT_TAG in surface.part.tags:
			return surface
	return null


## The single cell step a `facing` points at, on the same 8-way adjacency `Grid.neighbors`
## uses. Rounded rather than truncated so a facing authored a hair off a cardinal still names
## the cell it obviously means.
static func _facing_step(facing: float) -> Vector2i:
	var direction: Vector2 = BodyProjector.forward_for(facing)
	return Vector2i(roundi(direction.x), roundi(direction.y))
