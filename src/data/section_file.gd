class_name SectionFile
extends Resource

## taskblock-54 Pass C: **an authored fragment the generator will stitch.**
##
## A second format, not the map format used smaller. A `MapFile` is a complete playable board.
## A **section** is a *fragment*, defined by its **edges** rather than its interior — and
## `SectionEdge` is the thing a `MapFile` has nowhere to put.
##
## ## What it deliberately reuses
##
## Every decision `MapSerializer` settled and that still holds, rather than a second set of
## answers: **parts by `DataLibrary` id** (never embedded, so a `.tres` balance edit keeps
## applying), **no runtime state**, **one `MapPlacement` class with an open `kind`** rather than
## a class per placement, and **a Resource per placement** rather than parallel arrays so the
## `.tres` stays hand-authorable. `SectionSerializer` applies placements by delegating to
## `MapSerializer`, so there is one path that turns a placement into a board and not two.
##
## ## What makes it a section rather than a small map
##
## **A section with no walkable surface at all is valid.** The taskblock's own worked example is
## *a square of empty cells with one exterior wall and no interior walls* — an edge piece of a
## very large room, meaningless alone and only whole once its neighbours exist. `MapFile`'s
## authoring checks reject exactly that (a map with nothing to stand on is a broken map), and a
## format that could not express it would be a map format wearing a different name.
##
## So the validity rules are about **edges**, not about contents: an open edge must name what
## can join it and must have something to walk through. What is inside is the author's business.

## Human-facing, and how a section is picked out of the debug dropdown.
@export var section_name: String = ""
@export var width: int = 0
@export var rows: int = 0

## Surfaces, blockers and field items, in authored order — the same `MapPlacement` a map uses,
## with cells local to this section's own origin.
@export var placements: Array[MapPlacement] = []

## **The part a map has nowhere to put.** At most one edge per side; a side with no edge
## declared is treated as exterior, because "nothing said about it" and "nothing may attach"
## are the same thing for a fragment nobody has joined yet.
@export var edges: Array[SectionEdge] = []

# --- taskblock-55 Pass C: declarations, consumed at assembly and never present in a board -----
#
# **This is where a section stops being a small map.** Everything above describes things that
# are there; everything below describes what *may* be there, what *must not*, and how a
# neighbour's content is allowed to meet this one's. A placed board has a barrel or it does not;
# it has no "40% chance of a barrel."
#
# `SectionSerializer` delegates placement application to `MapSerializer` on the reasoning that a
# previewed section genuinely is a tiny map. **That reasoning holds for placements and stops
# holding here** — the delegation is now partial, and this vocabulary is owned by the section
# format alone.

## Volumes, each carrying one of the four co-occupancy verbs. See `SectionClaim`.
@export var claims: Array[SectionClaim] = []

## Per-cell "something may appear here" declarations — clutter and spawners. See `SectionSpawn`.
@export var spawns: Array[SectionSpawn] = []

## The cap on how many clutter items this section may actually spawn, however many of its
## clutter cells roll true. A cavernous hold with forty candidate cells is not forty barrels.
## Negative means uncapped.
@export var maximum_clutter: int = -1

## Clutter tags that must never appear here, whatever the cells say. The refusal a room needs
## when its dressing would be wrong rather than merely unlikely — no goo barrels in the medbay.
@export var banned_clutter: Array[StringName] = []

## **All-or-nothing, not a minimum topped up.** If the garrison roll produces fewer than this,
## the section spawns **none**. A cavernous room never contains one lonely guard: either it is
## held or it is empty, and "held by one" reads as a bug in the room rather than a light patrol.
@export var minimum_garrison: int = 0

## `minimum_garrison`'s foil. Negative means uncapped.
@export var maximum_garrison: int = -1

## A whitelist of encounter types this section may host.
##
## **The encounter system does not exist.** The field is recorded now, authored and validated,
## and consumed nowhere — so that sections authored today need not all be revisited when it
## does. Open `StringName`, like every other content vocabulary here.
@export var encounter_types: Array[StringName] = []

## **Is this section a room on its own, or part of a larger one?** The load-bearing declaration
## of the three, and the reason it cannot be inferred.
##
## Encounters roll **per room**, and a room may be several sections — so crossing an invisible
## seam inside one large hold must not trigger anything. Nothing about a section's contents can
## answer this: a square of empty cells with one exterior wall is a legitimate section (it is an
## edge piece of a very large room) and is explicitly **not** a room, while a section of exactly
## the same shape may be a cell block that is. Only the author knows which.
@export var is_room: bool = true


## This section's edge for `side`, or null. Sides are a closed set of four in practice but an
## open vocabulary in the format, so this is a lookup rather than four fields.
func edge_for(side: StringName) -> SectionEdge:
	for edge: SectionEdge in edges:
		if edge != null and edge.side == side:
			return edge
	return null


## How many cells run along `side` — the length an `openings` index is measured against.
func span_of(side: StringName) -> int:
	if side == SectionEdge.SIDE_NORTH or side == SectionEdge.SIDE_SOUTH:
		return width
	return rows


## The cells that lie on `side`, in the order `SectionEdge.openings` indexes them: west/east run
## north to south, north/south run west to east.
func cells_along(side: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match side:
		SectionEdge.SIDE_NORTH:
			for x: int in range(width):
				cells.append(Vector2i(x, 0))
		SectionEdge.SIDE_SOUTH:
			for x: int in range(width):
				cells.append(Vector2i(x, rows - 1))
		SectionEdge.SIDE_WEST:
			for y: int in range(rows):
				cells.append(Vector2i(0, y))
		SectionEdge.SIDE_EAST:
			for y: int in range(rows):
				cells.append(Vector2i(width - 1, y))
	return cells
