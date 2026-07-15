class_name BodyProjector
extends RefCounted

## Body-space projection (docs/02). No facings, no snap: a part's local Box
## volumes are rotated by the continuous angle between the unit's orientation
## and the line of fire, then flattened onto the view plane. `view_dir` is
## always "direction of travel" — the same direction a shot moving from the
## shooter into the world would take — so depth increases the farther a
## point sits from the shooter, and per-unit Regions compose directly with
## ShotPlane's inter-unit depth offsets by simple addition.
##
## A box projects one Region PER VISIBLE FACE, not one region guessed for
## the whole box (docs/03): surface_normal belongs to the specific face that
## was hit. A face is visible when its rotated normal points at least partly
## toward the shooter; an edge-on face projects to near-zero width and is
## dropped. This lets incidence span the full 0-90 degree range — a box
## viewed corner-on shows two adjacent faces, one near head-on and one
## near-grazing, in non-overlapping screen spans.

## World-space ground direction a unit with orientation == 0.0 faces.
const WORLD_FORWARD := Vector2(0.0, 1.0)

## Below this projected width (world units), a face is edge-on enough to
## drop rather than emit a degenerate sliver region.
const _MIN_FACE_WIDTH := 0.001

## A box's four in-plane side faces (top/bottom ignored — shots travel
## horizontally in this abstraction), as parallel arrays: each face's local
## normal and the two +/-1 corner multipliers (of the box's half-extents)
## spanning it.
const _FACE_NORMALS: Array[Vector2] = [
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)
]
const _FACE_CORNERS_A: Array[Vector2] = [
	Vector2(1.0, -1.0), Vector2(-1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)
]
const _FACE_CORNERS_B: Array[Vector2] = [
	Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, -1.0)
]


## Projects every living part of `unit`'s frame into view-plane Regions.
static func project(unit: Unit, view_dir: Vector2) -> Array[Region]:
	var regions: Array[Region] = []
	for part: Part in unit.frame.living_parts():
		regions.append_array(project_part(part, view_dir, unit.orientation))
	return regions


## Projects a single part's own boxes, rotated by `orientation` (a unit's
## facing, or 0.0 for a static, world-aligned cover/obstacle part) relative
## to `view_dir`. Shared by `project()` and ShotPlane's cover placement so
## both go through identical math.
static func project_part(part: Part, view_dir: Vector2, orientation: float = 0.0) -> Array[Region]:
	if part.hp <= 0:
		return []
	var dir: Vector2 = view_dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var regions: Array[Region] = []
	for box: Box in part.volume:
		regions.append_array(_project_box(box, dir, perp, orientation, part))
	return regions


static func _project_box(
	box: Box, dir: Vector2, perp: Vector2, orientation: float, part: Part
) -> Array[Region]:
	var half := box.size * 0.5
	var toward_shooter: Vector2 = -dir
	var regions: Array[Region] = []

	for i in range(_FACE_NORMALS.size()):
		var world_normal: Vector2 = _FACE_NORMALS[i].rotated(orientation)
		if world_normal.dot(toward_shooter) <= 0.0:
			continue  # facing away from the shooter

		var corner_a := Vector2(
			box.center.x + _FACE_CORNERS_A[i].x * half.x,
			box.center.z + _FACE_CORNERS_A[i].y * half.z
		)
		var corner_b := Vector2(
			box.center.x + _FACE_CORNERS_B[i].x * half.x,
			box.center.z + _FACE_CORNERS_B[i].y * half.z
		)
		var screen_a: float = corner_a.rotated(orientation).dot(perp)
		var screen_b: float = corner_b.rotated(orientation).dot(perp)
		var min_x: float = minf(screen_a, screen_b)
		var max_x: float = maxf(screen_a, screen_b)
		if max_x - min_x < _MIN_FACE_WIDTH:
			continue  # edge-on: a vanishing sliver, not a real target

		var face_center_local: Vector2 = (corner_a + corner_b) * 0.5
		var depth: float = face_center_local.rotated(orientation).dot(dir)
		var rect := Rect2(min_x, box.center.y - half.y, max_x - min_x, box.size.y)
		var normal3 := Vector3(world_normal.x, 0.0, world_normal.y)
		regions.append(Region.new(rect, depth, part, normal3))

	return regions
