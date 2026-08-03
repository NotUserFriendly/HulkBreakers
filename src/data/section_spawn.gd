class_name SectionSpawn
extends Resource

## taskblock-55 Pass C1: **clutter and spawners stay per cell, with a per-cell chance.**
##
## The companion to `SectionClaim`, and deliberately not one of its verbs. A claim is a rule about
## a *volume of space* — what may co-occupy it. This names **a place something may appear**, which
## is a different kind of statement and wants a different shape: a cell, a tag, and a probability.
##
## Giving these box extents would have been a false economy. "A barrel may appear here" does not
## want an interval — a barrel sits on the floor of a cell, and the only genuine question is
## *which cell* and *how likely*. The volume question a claim answers does not arise.
##
## Like every claim, this is **consumed at assembly and never present in an assembled map**. The
## roll happens once, against a seeded RNG, and what lands is an ordinary `MapPlacement`. A
## previewed board has a barrel or it does not.

## A loose object that dresses a room — a barrel, a pallet, a scrap pile. Drawn from the tag,
## capped by `SectionFile.maximum_clutter`, and refused by `SectionFile.banned_clutter`.
const KIND_CLUTTER: StringName = &"clutter"
## A unit may start here. Counted against `minimum_garrison`/`maximum_garrison`, which are
## whole-section declarations because the question "is this room garrisoned at all" is not a
## question about any one cell.
const KIND_SPAWNER: StringName = &"spawner"

@export var cell: Vector2i = Vector2i.ZERO
@export var kind: StringName = KIND_CLUTTER
## Open `StringName`, per CLAUDE.md: `barrel`, `logistic`, `machine` today, and a fourth is a
## `.tres` edit. What a tag *resolves to* is the content library's business, not this format's.
@export var tag: StringName = &""
## 0.0 never, 1.0 always. Rolled once per assembly against the seeded RNG, in a stable iteration
## order — see `SectionRoller`, where getting that order wrong is the live hazard.
@export var chance: float = 1.0


func _init(
	p_cell: Vector2i = Vector2i.ZERO,
	p_kind: StringName = KIND_CLUTTER,
	p_tag: StringName = &"",
	p_chance: float = 1.0
) -> void:
	cell = p_cell
	kind = p_kind
	tag = p_tag
	chance = p_chance
