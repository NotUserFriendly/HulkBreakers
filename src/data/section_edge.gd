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


func _init(
	p_side: StringName = SIDE_NORTH,
	p_kind: StringName = KIND_EXTERIOR,
	p_join_tag: StringName = &"",
	p_openings: Array[int] = []
) -> void:
	side = p_side
	kind = p_kind
	join_tag = p_join_tag
	openings = p_openings


## The side that would face this one across a join. A section's east edge meets its neighbour's
## west edge; there is no such thing as an east edge meeting an east edge.
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
		_:
			return &""
