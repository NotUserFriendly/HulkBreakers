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
