class_name BoardView
extends Node3D

## docs/10 Phase 12.1: the board's own geometry — a flat ground plane sized
## to the grid, plus a box mesh for every blocker (docs/02: cover is just a
## region in the shot plane; here it's just a box sitting on the board).
## Pure presentation: BoardView never mutates Grid, only reads it.

var grid: Grid


func build(p_grid: Grid, material_table: MaterialTable) -> void:
	grid = p_grid
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

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
	add_child(ground)

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
		add_child(instance)
