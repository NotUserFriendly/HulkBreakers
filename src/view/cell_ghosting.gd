class_name CellGhosting
extends RefCounted

## **Which drawn meshes belong to which cell, and how to make one cell see-through.**
## taskblock-59 Pass B.
##
## The taskblock: *"the select gizmo sits inside items. Acceptable, but then it must be clickable
## and draggable there, and the selected part should render as a **ghost** so the handles are
## readable through it."*
##
## **The handles were always clickable.** `Gizmo.hit` is a ray/box test against the handle boxes
## with nothing in front of it, and `GizmoModule` takes the input walk ahead of
## `BoardInspectModule`, so a press on a buried handle already reached the gizmo and never reached
## the board. What was missing is that you cannot aim at what you cannot see — so this is a
## visibility fix, not an input one.
##
## ## Why it is its own class
##
## `BoardView` went over the repo's 1000-line gate when this landed in it — the fourth time a lint
## gate has picked the seam here (`EditorTools`, `FacePlacement`, `EditorPanel`, and now this).
## **The seam is a real one even so**: "which mesh is at which cell" is a fact `BoardView` produces
## and never consumes, and the ghosting is the only thing that has ever wanted it. Nothing here
## builds geometry, and nothing in `BoardView` reads the map back.
##
## ## Blockers and loose items only, stated rather than worked around
##
## `BoardView._build_tiles` merges every walkable tile into **one** `MeshInstance3D`, so a per-cell
## tile has no instance of its own and cannot be ghosted separately. That is the honest limit and it
## falls the right way round: a gizmo gets buried inside a wall or a crate, never inside a floor.

## How much of the selected part you can still see through it. Flagged and tunable, not designed —
## transparent enough that the handles inside read, opaque enough that the author knows what they
## grabbed.
const ALPHA := 0.35

## The colour used when a mesh's own material cannot be read for one — a wall, whose material is the
## cutout shader rather than a `StandardMaterial3D`.
const FALLBACK_COLOR := Color(0.75, 0.78, 0.82)

## `Vector2i` -> `Array[MeshInstance3D]`, recorded as the meshes are built rather than re-derived
## from their transforms afterwards, which would be a second answer to "what is at this cell".
var _meshes: Dictionary = {}

## Which cell is currently drawn see-through, or null. One at a time — the gizmo focuses one thing.
var _ghosted: Variant = null


## Forgets every mesh. Called from `BoardView.build`: the instances it holds are about to be freed,
## and a map pointing at freed nodes is worse than an empty one.
func reset() -> void:
	_meshes.clear()
	_ghosted = null


## Records that `mesh` stands at `cell`.
func record(cell: Vector2i, mesh: MeshInstance3D) -> void:
	if not _meshes.has(cell):
		_meshes[cell] = [] as Array[MeshInstance3D]
	(_meshes[cell] as Array[MeshInstance3D]).append(mesh)


func meshes_at(cell: Vector2i) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	found.assign(_meshes.get(cell, []))
	return found


func ghosted() -> Variant:
	return _ghosted


## Draws `cell`'s geometry see-through, restoring whatever was ghosted before. Null clears.
##
## **A `material_override` rather than `GeometryInstance3D.transparency`**, and that is a
## verifiability choice as much as a rendering one: the override is the path
## `PlacementGhostModule` already proves renders as a ghost in this project, and a test can read
## the override and its alpha back off the real node. The part keeps its own colour at reduced
## alpha, because an author has to still recognise what they selected.
func ghost(cell: Variant) -> void:
	for mesh: MeshInstance3D in meshes_at(_ghosted) if _ghosted != null else []:
		if is_instance_valid(mesh):
			mesh.material_override = null
	_ghosted = cell
	if cell == null:
		return
	for mesh: MeshInstance3D in meshes_at(cell as Vector2i):
		if is_instance_valid(mesh):
			mesh.material_override = material_for(mesh)


## A translucent copy of whatever colour `mesh` already draws in.
static func material_for(mesh: MeshInstance3D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var color: Color = FALLBACK_COLOR
	var own: Material = mesh.mesh.surface_get_material(0) if mesh.mesh != null else null
	if own is StandardMaterial3D:
		color = (own as StandardMaterial3D).albedo_color
	color.a = ALPHA
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
