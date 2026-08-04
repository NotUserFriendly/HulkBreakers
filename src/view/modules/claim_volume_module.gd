class_name ClaimVolumeModule
extends ViewModule

## taskblock-56 Pass E: **a claim is invisible today, and this is the module that draws it.**
##
## `SectionClaim`'s own header describes it as "a translucent box, resizable while authoring,
## overlapping freely with anything, drawn only in the editor" — and nothing drew one. So the only
## way to know a section declares a claim is to read its `.tres`, which is the one thing an editor
## cannot work around. That is why this pass precedes the editor rather than following it.
##
## ## Never in play, and that is enforced rather than intended
##
## A claim is consumed at assembly and does not exist on an assembled board (`SectionClaim`: "once
## the board is assembled, every claim has been consumed and none of them exists"). Drawing one
## during a bout would be drawing something that is not there — the exact defect taskblock-54 and
## -55 deleted risers and the ground quad for. **No play mode declares this module**, and
## `test_claim_volumes.gd` asserts that against `ViewModes.all()` rather than trusting the table to
## stay right.
##
## ## The colours, and why the two greens are far apart
##
## | claim | colour |
## |---|---|
## | `exterior` | red |
## | `interior` | **vibrant lime** |
## | `empty` | blue |
## | `entry` | orange |
##
## The floor is dark forest green (`WorldPalette.TILE_TEMP`) and an interior claim is vibrant lime.
## **That separation is the constraint, not either value** — a claim has to read against the floor
## it sits on, and two greens a few steps apart would not. If either is retuned, retune the other.
##
## `kind` is an open `StringName`, so a claim whose kind has no colour here draws in
## `UNKNOWN_COLOR` rather than not drawing. **Visible-but-unstyled beats invisible**: an author who
## adds a fifth verb should see their claim in the wrong colour, not wonder why nothing appeared.

const EXTERIOR_COLOR := Color("#D53A3A")
const INTERIOR_COLOR := Color("#7BE02A")
const EMPTY_COLOR := Color("#3A7BD5")
const ENTRY_COLOR := Color("#E08A2A")
## A kind nobody has given a colour. Deliberately not one of the four.
const UNKNOWN_COLOR := Color("#B060D0")
## Translucent enough to read as an annotation over the board rather than as an object on it.
const ALPHA := 0.28

## The claims to draw, in section-local space. Set by whatever owns the authoring model — the editor
## sets it on every change; a preview sets it once.
var claims: Array[SectionClaim] = []
## Where the section's origin sits on the board, in cells. A preview of one section leaves this at
## zero; a stitched board offsets each section's own claims.
var origin: Vector2i = Vector2i.ZERO

## One `MeshInstance3D` per drawn claim, in the order they were drawn, so a test can read back what
## was produced instead of asserting against a render.
var boxes: Array[MeshInstance3D] = []


func module_id() -> StringName:
	return &"claim_volumes"


static func color_for(kind: StringName) -> Color:
	match kind:
		SectionClaim.KIND_EXTERIOR:
			return EXTERIOR_COLOR
		SectionClaim.KIND_INTERIOR:
			return INTERIOR_COLOR
		SectionClaim.KIND_EMPTY:
			return EMPTY_COLOR
		SectionClaim.KIND_ENTRY:
			return ENTRY_COLOR
	return UNKNOWN_COLOR


## Replaces what is drawn with `p_claims`. Idempotent and cheap to call on every authoring edit —
## the old boxes are freed and the new ones built, rather than diffed. A claim set is a handful of
## boxes; a diff would be more code than it saves and would be the thing that goes subtly wrong.
func show_claims(p_claims: Array[SectionClaim], p_origin: Vector2i = Vector2i.ZERO) -> void:
	claims = p_claims
	origin = p_origin
	_rebuild()


func clear() -> void:
	show_claims([] as Array[SectionClaim])


## The world-space box a claim occupies, so a test can assert the extent rather than the render.
##
## **`Box` is in the section's own local space** — the same units a placement's cell and height are
## in — so a claim over cell `(2,1)` from the deck to 2.0 has centre `(2, 1, 1)`. Converting is
## therefore the cell size on X and Z and nothing on Y, plus the section's own origin.
static func world_aabb(claim: SectionClaim, p_origin: Vector2i) -> AABB:
	var cell_size: float = UnitGeometry.CELL_SIZE
	var size := Vector3(
		claim.box.size.x * cell_size, claim.box.size.y, claim.box.size.z * cell_size
	)
	var centre := Vector3(
		(claim.box.center.x + float(p_origin.x)) * cell_size,
		claim.box.center.y,
		(claim.box.center.z + float(p_origin.y)) * cell_size
	)
	return AABB(centre - size * 0.5, size)


func _rebuild() -> void:
	for box: MeshInstance3D in boxes:
		box.queue_free()
	boxes.clear()
	for claim: SectionClaim in claims:
		# A claim with no box is malformed and is **reported by skipping**, never crashed on — the
		# same posture `SectionClaim`'s own header takes ("null is a malformed claim, reported
		# rather than crashed on"). It shows up as a claim the author declared and cannot see.
		if claim == null or claim.box == null:
			continue
		var volume: AABB = world_aabb(claim, origin)
		var instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = volume.size
		instance.mesh = mesh
		instance.position = volume.get_center()
		var color: Color = color_for(claim.kind)
		color.a = ALPHA
		# `translucent_material`, so it reads as "not really there" — the same unshaded,
		# alpha-blended convention every overlay uses, never `lit_material`, which is for
		# real geometry.
		instance.material_override = WorldPalette.translucent_material(color)
		add_child(instance)
		boxes.append(instance)
