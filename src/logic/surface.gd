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
