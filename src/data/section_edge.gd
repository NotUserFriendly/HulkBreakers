class_name SectionEdge
extends Resource

## taskblock-54 Pass C: **one side of a section, and what may attach to it.**
##
## A `MapFile` is a complete board and is defined by its interior. A **section** is a fragment
## and is defined by its **edges** — where a neighbour may attach, which sides are exterior,
## and what a join requires. A map format has nowhere to put any of that, which is the whole
## reason this is a separate format rather than a smaller `MapFile`.
##
## ## The attachment grammar is the precedent, not the implementation
##
## Sections joining at compatible edges is `attaches_to` semantics one scale up, and
## taskblock-53 proved that grammar holds against real content for the first time. **The
## reasoning is reused; the code is not**, because an edge is not a socket:
##
## - A socket is a **point** with a transform. An edge is a **span** — a whole side, with
##   specific cells along it that a unit can actually walk through.
## - A socket is occupied by exactly one part. An edge is matched against another *edge*, and
##   both sides must agree; neither is the host.
## - `PartGraph.attach` mutates the socket to record the occupant. Two joined sections are
##   still two files — the join is a fact about a layout, not about either section.
##
## ## `side` and `kind` are open vocabularies
##
## Both are `StringName`, per CLAUDE.md: content a designer might extend must be addable as
## data. `side` is the four orthogonals today; `kind` is `exterior` or `open` today, and a third
## — a one-way drop, a sealed hatch that content can unseal — is a `.tres` edit rather than a
## code one.

const SIDE_NORTH: StringName = &"north"
const SIDE_SOUTH: StringName = &"south"
const SIDE_EAST: StringName = &"east"
const SIDE_WEST: StringName = &"west"

## taskblock-55 Pass D: **a section must be able to sit above or below another** — an observation
## room on top of a staircase, a barracks at the bottom.
##
## These are **data, not code**, which is why adding them costs two constants and a row in
## `opposite`. `edge_for(side)` already took an open `StringName`, and the note that "sides are a
## closed set of four in practice" was a statement about the shipped content rather than about the
## format. It stopped being true here and nothing had to be restructured for it.
const SIDE_UP: StringName = &"up"
const SIDE_DOWN: StringName = &"down"

## Nothing may attach here — the outside of the hulk, or a wall the author means to be final.
const KIND_EXTERIOR: StringName = &"exterior"
## A neighbour may attach, if it offers a matching `join_tag`.
const KIND_OPEN: StringName = &"open"

@export var side: StringName = SIDE_NORTH
@export var kind: StringName = KIND_EXTERIOR

## **What a neighbour must offer for a join to be legal.** Two `open` edges join when their tags
## match — an open `StringName` vocabulary, so `corridor_2w` and `hangar_mouth` are content.
## Meaningless on an `exterior` edge and ignored there.
@export var join_tag: StringName = &""

## **Which cells along this side a unit can actually walk through**, as offsets from the side's
## own start — west/east sides run north to south, north/south sides run west to east.
##
## Empty means the whole side is the opening. That is the common case for a section that is one
## room's worth of floor, and spelling out every index would be noise; a corridor mouth in an
## otherwise solid wall is what the explicit list is for.
@export var openings: Array[int] = []

## taskblock-55 Pass D: **the height this edge's openings sit at.**
##
## A door at ground level and a door at the top of a staircase are **different joins**, and
## nothing else on this resource could tell them apart — `openings` indexes along the side, which
## says where along a wall an opening is and nothing about how far up it is. Once sections can
## stack, two edges can agree on tag, span and openings and still be at different storeys.
##
## Continuous, like every other height in this project (taskblock-37). A staircase landing at 2.4
## is a legal join height; nothing quantizes it to a storey index.
@export var opening_height: float = 0.0


func _init(
	p_side: StringName = SIDE_NORTH,
	p_kind: StringName = KIND_EXTERIOR,
	p_join_tag: StringName = &"",
	p_openings: Array[int] = [],
	p_opening_height: float = 0.0
) -> void:
	side = p_side
	kind = p_kind
	join_tag = p_join_tag
	openings = p_openings
	opening_height = p_opening_height


## The side that would face this one across a join. A section's east edge meets its neighbour's
## west edge; there is no such thing as an east edge meeting an east edge. taskblock-55 Pass D
## added the vertical pair on exactly the same footing — `up` meets `down`, and a section's own
## `up` edge is the ceiling a neighbour stands on.
static func opposite(p_side: StringName) -> StringName:
	match p_side:
		SIDE_NORTH:
			return SIDE_SOUTH
		SIDE_SOUTH:
			return SIDE_NORTH
		SIDE_EAST:
			return SIDE_WEST
		SIDE_WEST:
			return SIDE_EAST
		SIDE_UP:
			return SIDE_DOWN
		SIDE_DOWN:
			return SIDE_UP
		_:
			return &""
