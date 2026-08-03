extends GutTest

## taskblock-54 Pass B1 and taskblock-55 Pass B: **the board draws parts, and only parts.**
##
## Two deletions, one rule, and this file guards both because the second is the first repeated
## one primitive down.
##
## **taskblock-54 deleted the risers.** `BoardView` used to draw a vertical quad along every edge
## where two orthogonally-adjacent cells differed in height — a stepped terrace. That face had no
## `Part` behind it (`BR52.03`), so a round fired horizontally into a step passed through the
## visible geometry and travelled on under the raised floor.
##
## **taskblock-55 deleted the per-cell ground quad**, which had the same defect and survived only
## because it was older: over a floored cell it was a second thing co-planar with the real
## `Surface` part's top face, and over an unfloored cell it was ground with nothing behind it at
## all. A **cell** is a grid square and is empty; a **tile** is a walkable part and carries all the
## height there is.
##
## **Counted by vertices rather than by inspecting the mesh's shape**, because the assertion that
## matters is "no geometry appeared for a thing that is not there", and a vertex count is the one
## thing that cannot be true while a face is quietly still drawn.


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


func _vertex_count(mesh: ImmediateMesh) -> int:
	var total := 0
	for surface_index: int in range(mesh.get_surface_count()):
		total += mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX].size()
	return total


func _tile_vertex_count(grid: Grid) -> int:
	var view := BoardView.new()
	add_child_autofree(view)
	var tiles: MeshInstance3D = view.call(&"_build_tiles", grid, DataLibrary.material_table())
	var total: int = _vertex_count(tiles.mesh)
	tiles.queue_free()
	return total


## **The load-bearing assertion, unchanged in intent since taskblock-54.** A terraced board and a
## flat board holding the same number of tiles must emit exactly the same amount of geometry: the
## tiles themselves, moved in Y, and nothing else. A riser — or any other face invented to fill
## the gap between two heights — shows up here as extra vertices on the terraced one.
func test_a_terraced_board_emits_no_more_geometry_than_a_flat_one() -> void:
	var flat: int = _tile_vertex_count(_flat_grid())
	var terraced: int = _tile_vertex_count(_terraced_grid())
	gut.p("flat %d vertices, terraced %d" % [flat, terraced])
	assert_gt(flat, 0, "sanity: the flat board draws its tiles")
	assert_eq(terraced, flat, "a height difference must add no geometry -- no risers")


## **What is drawn is one box per tile, six faces of it.** taskblock-55's replacement for the
## per-cell quad, pinned by count so that "drew only the top face" — which would put the old
## defect back at a smaller scale, a visible slab whose sides a round passes through — fails here
## rather than in a playtest.
func test_every_tile_is_drawn_as_a_whole_box() -> void:
	var vertices: int = _tile_vertex_count(_flat_grid())
	# 16 tiles, six faces each, two triangles per face, three vertices per triangle.
	assert_eq(vertices, 16 * 6 * 2 * 3, "one whole box per tile")


## **An unfloored cell draws nothing.** The per-cell quad's second defect, and the one a vertex
## count states most plainly: the board's geometry scales with the tiles placed on it, not with
## the size of the grid. A board half of whose cells are unfloored draws half as much.
func test_an_unfloored_cell_contributes_no_geometry() -> void:
	var full: Grid = _flat_grid()
	var half: Grid = _flat_grid()
	for y: int in range(4):
		for x: int in range(2):
			half.clear_surfaces(Vector2i(x, y))

	var full_vertices: int = _tile_vertex_count(full)
	var half_vertices: int = _tile_vertex_count(half)
	gut.p("16 tiles: %d vertices; 8 tiles: %d" % [full_vertices, half_vertices])
	assert_eq(half_vertices, full_vertices / 2, "eight unfloored cells draw exactly nothing")


## **The tiles are drawn where the ray caster marches them**, which is the whole reason
## `_build_tiles` calls `UnitGeometry.assembly_placements` rather than emitting a quad of its own.
## Read back off the built mesh and compared against that call directly (docs/10 rule 2), so the
## two cannot drift into agreeing only on paper.
func test_the_drawn_tile_occupies_the_boxes_the_ray_caster_marches() -> void:
	var grid := Grid.new(1, 1)
	grid.add_surface(Vector2i(0, 0), Surface.new(DataLibrary.get_part(&"ship_floor"), 0.3))

	var view := BoardView.new()
	add_child_autofree(view)
	var tiles: MeshInstance3D = view.call(&"_build_tiles", grid, DataLibrary.material_table())
	var drawn: AABB = tiles.mesh.get_aabb()

	var placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		DataLibrary.get_part(&"ship_floor"), Vector2i(0, 0), 0.0, null, 0.3
	)
	assert_eq(placements.size(), 1, "sanity: the floor part is one box")
	var box: Box = placements[0].box
	var center: Vector3 = placements[0].transform * box.center
	var marched := AABB(center - box.size * 0.5, box.size)

	gut.p("drawn   %s" % str(drawn))
	gut.p("marched %s" % str(marched))
	assert_almost_eq(drawn.position.x, marched.position.x, 0.0001, "x")
	assert_almost_eq(drawn.position.y, marched.position.y, 0.0001, "y -- the 0.3 placement")
	assert_almost_eq(drawn.position.z, marched.position.z, 0.0001, "z")
	assert_almost_eq(drawn.size.x, marched.size.x, 0.0001, "width")
	assert_almost_eq(drawn.size.y, marched.size.y, 0.0001, "thickness")
	assert_almost_eq(drawn.size.z, marched.size.z, 0.0001, "depth")
	tiles.queue_free()
