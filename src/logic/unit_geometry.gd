class_name UnitGeometry
extends RefCounted

## docs/10 "render is hitbox": full, unfiltered 3D placement of every living
## part's boxes for a unit, in world space — distinct from BodyProjector's
## 2D view-plane projection (which culls to visible faces for one line of
## fire). Both compose the same socket-chain transform the same way
## (Phase 12.0: `parent ∘ socket.transform ∘ ...`), so what a UnitView
## renders and what the shot plane can hit are always the same boxes.

## World units per grid cell — the ground plane's scale for both the board
## mesh and unit placement.
const CELL_SIZE := 1.0


## Every living part's boxes, each as a BoxPlacement carrying that part's
## full world transform (unit facing + board position + socket chain).
static func placements(unit: Unit) -> Array[BoxPlacement]:
	var result: Array[BoxPlacement] = []
	if unit.shell.root == null:
		return result
	var unit_transform := Transform3D(
		Basis(Vector3.UP, unit.orientation), Vector3(unit.cell.x, 0.0, unit.cell.y) * CELL_SIZE
	)
	_walk(unit.shell.root, Transform3D.IDENTITY, unit_transform, result)
	return result


static func _walk(
	part: Part,
	part_transform: Transform3D,
	unit_transform: Transform3D,
	result: Array[BoxPlacement]
) -> void:
	if part.hp > 0:
		for box: Box in part.volume:
			result.append(BoxPlacement.new(part, box, unit_transform * part_transform))
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		_walk(socket.occupant, part_transform * socket.transform, unit_transform, result)
