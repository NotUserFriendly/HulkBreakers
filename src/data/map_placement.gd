class_name MapPlacement
extends Resource

## taskblock-53 Pass B: **one placed thing in a saved map** — a surface, a blocker, or a
## loose field item — identified by the cell it sits at and the `DataLibrary` id of the
## part that sits there.
##
## ## Why one class with an open `kind` rather than three classes
##
## `kind` is an **open `StringName` vocabulary**, not an enum, exactly as CLAUDE.md
## requires of content: a designer adding a fourth thing a cell can hold authors it as data.
## The three shipped kinds differ only in which `Grid` container they land in, so three
## near-identical Resources would be three places to remember to update.
##
## ## Why a part **id**, never an embedded part
##
## A map references `&"ship_floor"`; it does not carry a copy of it. `Grid.dup()` deep-copies
## parts because a live board's parts carry mutable state (hp, `is_mangled`), but a **map is
## the pristine authored thing** — every part starts intact, and its stats come from
## `data/parts/*.tres` at load time. Embedding copies would freeze a balance number into
## every map file ever saved, and the first `.tres` edit would silently stop applying.
##
## ## Why it is a `Resource` and not a row in a parallel array
##
## Pass B requires the first map to be **hand-authored**. Parallel arrays
## (`cells[]`/`part_ids[]`/`heights[]`) serialize just as well and are miserable to write by
## hand and easy to desynchronise by one row. A named block per placement is what makes a
## `.tres` reviewable.

## Where a surface lands in `Grid.surfaces`. Order within a cell is preserved by the order
## placements appear in `MapFile.placements` — a catwalk over a floor is two entries at one
## cell, and which is first is meaningful (`Surface.first_walkable`).
const KIND_SURFACE: StringName = &"surface"
## `Grid.blockers` — one part per cell (walls, cover). A second blocker at one cell is a
## malformed map, and `MapSerializer` says so rather than silently keeping the last.
const KIND_BLOCKER: StringName = &"blocker"
## `Grid.field_items` — loose parts lying on the ground, an ordered array per cell.
const KIND_FIELD_ITEM: StringName = &"field_item"

@export var cell: Vector2i = Vector2i.ZERO
@export var kind: StringName = KIND_SURFACE
## A `DataLibrary` part id. Unknown ids are a load error, never a silently skipped row —
## a map that quietly lost its floors would look like a generation bug for hours.
@export var part_id: StringName = &""
## Surfaces only: this placement's own real world elevation, the continuous height
## `Surface.height` carries. Ignored for blockers and field items, which sit on whatever
## surface the cell already has.
@export var height: float = 0.0
## Surfaces only: radians, the same convention `Surface.facing` and `Unit.orientation` use.
## What makes a ramp directional.
@export var facing: float = 0.0


func _init(
	p_cell: Vector2i = Vector2i.ZERO,
	p_kind: StringName = KIND_SURFACE,
	p_part_id: StringName = &"",
	p_height: float = 0.0,
	p_facing: float = 0.0
) -> void:
	cell = p_cell
	kind = p_kind
	part_id = p_part_id
	height = p_height
	facing = p_facing
