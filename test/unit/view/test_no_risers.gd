extends GutTest

## taskblock-54 Pass B1: **no riser geometry is emitted for any height difference.**
##
## `BoardView._build_terrain` used to draw a vertical quad along every edge where two
## orthogonally-adjacent cells differ in height — a stepped terrace. That face had **no `Part`
## behind it** (`BR52.03`), so a round fired horizontally into a step passed through the visible
## geometry and travelled on under the raised floor. The fix is the deletion: a step is one part
## at the height it needs to be, and the vertical gap between two heights is genuinely open
## space. *Render is hitbox* (`docs/10`) is restored by drawing nothing there.
##
## **Counted by vertices rather than by inspecting the mesh's shape**, because the assertion that
## matters is "no geometry appeared", and a vertex count is the one thing that cannot be true
## while a face is quietly still drawn.


func _terraced_grid() -> Grid:
	# Two columns at different heights: every shared edge between them is a step, which is
	# exactly where a riser used to be emitted.
	var grid := Grid.new(4, 4)
	for y: int in range(4):
		for x: int in range(4):
			var height: float = 0.0 if x < 2 else 3.0
			grid.add_surface(
				Vector2i(x, y), Surface.new(DataLibrary.get_part(&"ship_floor"), height)
			)
	return grid


func _flat_grid() -> Grid:
	var grid := Grid.new(4, 4)
	for y: int in range(4):
		for x: int in range(4):
			grid.add_surface(Vector2i(x, y), Surface.new(DataLibrary.get_part(&"ship_floor"), 0.0))
	return grid


func _terrain_vertex_count(grid: Grid) -> int:
	var view := BoardView.new()
	add_child_autofree(view)
	var terrain: MeshInstance3D = view.call(&"_build_terrain", grid)
	var mesh: ImmediateMesh = terrain.mesh
	var total := 0
	for surface_index: int in range(mesh.get_surface_count()):
		total += mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX].size()
	terrain.queue_free()
	return total


## **The load-bearing assertion.** A terraced board and a flat board of the same size must emit
## exactly the same amount of terrain: one top quad per cell and nothing else. Any riser would
## show up here as extra vertices on the terraced one.
func test_a_terraced_board_emits_no_more_terrain_than_a_flat_one() -> void:
	var flat: int = _terrain_vertex_count(_flat_grid())
	var terraced: int = _terrain_vertex_count(_terraced_grid())
	gut.p("flat %d vertices, terraced %d" % [flat, terraced])
	assert_gt(flat, 0, "sanity: the flat board draws its cells")
	assert_eq(terraced, flat, "a height difference must add no geometry — no risers")


## The per-cell top quads are still drawn, so the deletion removed the faces and not the floor.
func test_the_flat_top_quad_per_cell_survives() -> void:
	var grid: Grid = _flat_grid()
	var vertices: int = _terrain_vertex_count(grid)
	# One quad per cell, two triangles, three vertices each.
	assert_eq(vertices, 4 * 4 * 6, "one top quad per cell, still drawn")
