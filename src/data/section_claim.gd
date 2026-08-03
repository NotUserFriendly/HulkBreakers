class_name SectionClaim
extends Resource

## taskblock-55 Pass C1: **a declaration consumed at assembly and never present in an assembled
## map.**
##
## This is the second class of section data, and the thing that stops a section being a small map.
## A placed board has a barrel or it does not; it has no "40% chance of a barrel." A `MapPlacement`
## says *this is here*; a claim says *this may, must, or must not be here* — and once the board is
## assembled, every claim has been consumed and none of them exists.
##
## ## A claim is a volume, and its extent **is** its declaration
##
## Not a per-cell flag. A translucent box, resizable while authoring, overlapping freely with
## anything, drawn only in the editor. That dissolves the whole-column-versus-interval question
## outright: **the shape is the interval.** A claim over the bottom 0.4 of a cell and a claim over
## the whole column are the same kind of thing said about different extents, not two features.
##
## ## Same geometry, deliberately not the same resource type
##
## It carries a `Box`, exactly as a `Part` does, because the geometry question is identical and
## two box types would be two answers to it. It is **not a `Part`**, and that is the load-bearing
## decision: a `Part` has hp, a material, sockets, `attaches_to`, destructibility. A claim has
## none of those and must never reach a part picker, a loot roll, or a shot plane. Subclassing
## `Part` would inherit every one of the things this must not have, and each would then need
## suppressing somewhere — the kind of exclusion list nobody can justify two blocks later.
##
## ## The four verbs are all rules about co-occupancy
##
## | kind | says |
## |---|---|
## | `empty` | nothing may co-occupy — **forbid** |
## | `interior` / `exterior` | co-occupants must be inside / outside the hulk — **require** |
## | `entry` | an opening may exist here; overlapping entries intersect — **negotiate** |
## | `merge` | identical content may co-occupy and collapses to one — **permit and unify** |
##
## `kind` is an open `StringName` per CLAUDE.md — a fifth verb is a `.tres` edit and a rule in
## `ClaimResolver`, not a new class.

## Nothing may co-occupy this volume. Conflicts with **any** neighbour placement inside it.
const KIND_EMPTY: StringName = &"empty"
## Whatever co-occupies must be inside the hulk. Conflicts specifically with a neighbour
## asserting `exterior` over the same space.
const KIND_INTERIOR: StringName = &"interior"
## The foil of `interior`, and its only conflict partner.
const KIND_EXTERIOR: StringName = &"exterior"
## An opening **may** exist here. Two sections' entries resolve by intersection — see
## `ClaimResolver.entry_intersection`.
const KIND_ENTRY: StringName = &"entry"
## Identical content may co-occupy and collapses to **one** part. The deliberate exception to the
## stacking rule (Pass D): a merge volume is exactly where vertical overlap is legal.
const KIND_MERGE: StringName = &"merge"

@export var kind: StringName = KIND_EMPTY
## The extent, in the section's own local space — the same units a placement's cell and
## `height` are in, so a claim over cell `(2,1)` from the deck to 2.0 has center `(2, 1, 1)` and
## size `(1, 2, 1)`. `null` is a malformed claim, reported rather than crashed on.
@export var box: Box = null
## `merge` only: what may unify here. Two placements collapse to one when their part ids match;
## this names which part the author *expects*, so a merge volume that never fires is visible as
## an authoring mistake rather than silently doing nothing. Empty means "any matching pair".
@export var expects: StringName = &""


func _init(p_kind: StringName = KIND_EMPTY, p_box: Box = null, p_expects: StringName = &"") -> void:
	kind = p_kind
	box = p_box
	expects = p_expects


## This claim's extent as an `AABB`, moved by `offset` — the form every co-occupancy test wants.
## `offset` is how a section placed at a non-zero origin carries its claims with it.
func aabb(offset: Vector3 = Vector3.ZERO) -> AABB:
	if box == null:
		return AABB()
	return AABB(box.center + offset - box.size * 0.5, box.size)


## The four sides' worth of face area, for the one case where two entries must still be *ranked*
## rather than intersected: **rank by face area, because thickness is meaningless for an opening.**
## A 5-tall by 1-wide opening beats a 2x2 one, and how deep the wall is says nothing about either.
##
## The face is the box's two largest dimensions — an opening is a hole in something, so its
## smallest axis is the thickness of the thing it is a hole in.
func face_area() -> float:
	if box == null:
		return 0.0
	var dims: Array[float] = [absf(box.size.x), absf(box.size.y), absf(box.size.z)]
	dims.sort()
	return dims[1] * dims[2]
