class_name BoardView
extends Node3D

## docs/10 Phase 12.1/12.2: the board's own geometry — a flat ground plane
## sized to the grid, plus a box mesh for every blocker (docs/02: cover is
## just a region in the shot plane; here it's just a box sitting on the
## board) — and, separately, the TACTICS overlay (reachable highlight,
## queued-move ghost paths, each its own container so one never rebuilds
## the other, and both can be visible at once). Pure presentation: BoardView
## never mutates Grid, only reads it.

## Overlay markers sit slightly above the ground to avoid z-fighting with it;
## ghosts sit a touch higher still so they never fight the reachable tint.
const REACHABLE_HEIGHT := 0.02
const GHOST_HEIGHT := 0.03
const OVERLAY_SIZE := 0.8

var grid: Grid

var _static: Node3D
var _reachable_overlay: Node3D
var _ghost_overlay: Node3D


func _init() -> void:
	_static = Node3D.new()
	add_child(_static)
	_reachable_overlay = Node3D.new()
	add_child(_reachable_overlay)
	_ghost_overlay = Node3D.new()
	add_child(_ghost_overlay)


func build(p_grid: Grid, material_table: MaterialTable) -> void:
	grid = p_grid
	_clear(_static)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(
		grid.width * UnitGeometry.CELL_SIZE, grid.height * UnitGeometry.CELL_SIZE
	)
	plane.material = HulkTheme.flat_material(HulkTheme.BACKGROUND)
	ground.mesh = plane
	ground.position = Vector3(
		(grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
		0.0,
		(grid.height - 1) * UnitGeometry.CELL_SIZE * 0.5
	)
	_static.add_child(ground)

	for cell: Vector2i in grid.blockers:
		_spawn_blocker(grid.blockers[cell], cell, material_table)


func _spawn_blocker(part: Part, cell: Vector2i, material_table: MaterialTable) -> void:
	if part.hp <= 0:
		return
	var color: Color = HulkTheme.color_for_material(part.material, material_table)
	var cell_origin: Vector3 = Vector3(cell.x, 0.0, cell.y) * UnitGeometry.CELL_SIZE
	for box: Box in part.volume:
		var instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = box.size
		box_mesh.material = HulkTheme.flat_material(color)
		instance.mesh = box_mesh
		instance.position = cell_origin + box.center
		_static.add_child(instance)


## The reachable-cell highlight (docs/10 Phase 12.2) — one flat marker per
## cell, replacing whatever reachable highlight was shown before. Never
## touches the ghost-path overlay.
func show_reachable(cells: Array[Vector2i]) -> void:
	_clear(_reachable_overlay)
	for cell: Vector2i in cells:
		_reachable_overlay.add_child(_marker(cell, HulkTheme.DIM, REACHABLE_HEIGHT))


## One queued MoveAction's path per entry — multiple queued moves must stack
## visibly, so this never collapses them into a single overlay. Never
## touches the reachable-highlight overlay.
func show_ghost_paths(paths: Array) -> void:
	_clear(_ghost_overlay)
	for path: Array in paths:
		for cell: Vector2i in path:
			_ghost_overlay.add_child(_marker(cell, HulkTheme.HIGHLIGHT, GHOST_HEIGHT))


func clear_overlays() -> void:
	_clear(_reachable_overlay)
	_clear(_ghost_overlay)


func _marker(cell: Vector2i, color: Color, height: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(OVERLAY_SIZE, 0.02, OVERLAY_SIZE)
	box_mesh.material = HulkTheme.flat_material(color)
	instance.mesh = box_mesh
	instance.position = Vector3(cell.x, height, cell.y) * UnitGeometry.CELL_SIZE
	return instance


func _clear(container: Node3D) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
