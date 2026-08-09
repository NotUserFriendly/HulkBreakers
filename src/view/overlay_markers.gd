class_name OverlayMarkers
extends RefCounted

## **Ground-overlay marker geometry, built without a `BoardView` to hang it on.** taskblock-61
## Pass D.
##
## Extracted because `board_view.gd` has now hit `gdlint`'s 1000-line file cap twice in one
## taskblock — once for the cutout logger (`src/debug/cutout_log.gd`), once for this. Marker
## construction is a self-contained "make me a mesh at a cell" concern with no board state in it,
## which makes it the honest thing to lift out rather than a comment to shorten.

## How thick each bar of a hollow marker's outline is, in world units. Flagged and tunable — thick
## enough to read at the tactical camera's own distance, thin enough that what is underneath is
## what makes it read as hollow.
const RING_THICKNESS := 0.09


## **A hollow square outline**, four thin bars, centred on a cell.
##
## `BR30.04`: the supervisor asked for *"a hollow box drawn on the walkable terrain underneath"*.
## `BoardView._build_empty_indicators`' own border-square-under-fill-square pattern cannot do this
## — it paints over whatever is beneath it, which is exactly what must show through here.
##
## `world_y` is the caller's already-resolved height for the cell (the ground-overlay ladder rung
## plus that cell's own terrain height); this class deliberately knows nothing about grids.
static func hollow_box(
	cell: Vector2i, color: Color, world_y: float, size: float, thickness: float = RING_THICKNESS
) -> Node3D:
	var holder := Node3D.new()
	var inset: float = size * 0.5 - thickness * 0.5
	var bars: Array = [
		[Vector3(0.0, 0.0, -inset), Vector3(size, 0.02, thickness)],
		[Vector3(0.0, 0.0, inset), Vector3(size, 0.02, thickness)],
		[Vector3(-inset, 0.0, 0.0), Vector3(thickness, 0.02, size)],
		[Vector3(inset, 0.0, 0.0), Vector3(thickness, 0.02, size)],
	]
	for bar: Array in bars:
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = bar[1]
		box_mesh.material = WorldPalette.overlay_material(color)
		instance.mesh = box_mesh
		instance.position = bar[0]
		holder.add_child(instance)
	holder.position = Vector3(
		cell.x * UnitGeometry.CELL_SIZE, world_y, cell.y * UnitGeometry.CELL_SIZE
	)
	return holder


## **One flat marker box** on the ground-overlay ladder, centred on `cell` at `world_y`.
##
## taskblock-37 Pass E: the caller resolves `world_y` from `UnitGeometry.true_height_for_cell` —
## every marker (extraction cells, wall/empty-cell indicators, reachable/ghost overlays, the
## field-item marker) used to assume ground was always at world Y 0, and a marker over a raised
## cell must sit on ITS OWN real ground rather than float below it or get buried inside it.
##
## taskblock-55 Pass B: unchanged, and deliberately so, though the ground it reads is now the
## **tile's** height rather than the cell's — `true_height_for_cell` reads the walkable `Surface`
## placed there, so this was already asking the part where it is. An overlay marker is also not
## "a thing at that elevation" in the sense that pass forbids: it is a transient annotation about a
## cell, drawn above the tile on the ground-overlay height ladder, never geometry claiming to be
## solid.
static func flat_box(cell: Vector2i, color: Color, world_y: float, size: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(size, 0.02, size)
	box_mesh.material = WorldPalette.overlay_material(color)
	instance.mesh = box_mesh
	instance.position = Vector3(
		cell.x * UnitGeometry.CELL_SIZE, world_y, cell.y * UnitGeometry.CELL_SIZE
	)
	return instance


## **A queued waypoint marker.** `BR30.04`: solid for the most recent waypoint, a hollow outline for
## every earlier one, one colour for both — the supervisor's own spec, *"All queued waypoints are
## one color and a hollow box drawn on the walkable terrain underneath. The most recent waypoint is
## a filled in box."*
static func waypoint_box(
	cell: Vector2i, color: Color, world_y: float, size: float, filled: bool
) -> Node3D:
	if filled:
		return flat_box(cell, color, world_y, size)
	return hollow_box(cell, color, world_y, size)
