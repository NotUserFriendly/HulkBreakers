extends GutTest

## taskblock-56 Pass A, `BR55.02`: **the tiles are wound the same way every other box is.**
##
## `BoardView._add_box` is the only hand-wound geometry the project has — every other box on the
## board is a Godot `BoxMesh`. It was emitted inside out, so back-face culling kept the interior
## faces and discarded the ones facing the camera. Nothing caught it: `test_no_risers.gd` counts
## vertices and `test_board_view.gd` asserts an AABB, and geometry in exactly the right place
## facing exactly the wrong way satisfies both.
##
## **The convention is read back from the engine, never restated here.** A comment in this file
## claiming "Godot winds front faces clockwise" would be the same class of thing that caused the
## bug: an assumption written down as fact. So `_winding_sign` measures the sign of
## `(b - a).cross(c - a)` against a known outward direction, `test_the_reference_convention_*`
## pins what a real `BoxMesh` produces, and the tile assertions require the tile mesh to agree
## with *that* rather than with a number typed in by hand. If a future Godot flipped the rule,
## the reference test would move and the tile tests would follow it for free.
##
## **Assertions are on vertex order, not on a render.** CC cannot see the screen, and a headless
## run has no rasteriser to cull anything — so "is this face visible" is not a question available
## here. "Does this triangle's emitted order point the same way the engine's own box does" is, and
## it is the same fact.

const EPSILON := 0.0001


## The sign of the emitted triangle's cross product projected onto a known outward direction.
## `-1` = the cross points into the solid; `+1` = out of it; `0` = degenerate or edge-on, which
## is a failure in itself and reported as one by the callers.
func _winding_sign(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> int:
	var dot: float = (b - a).cross(c - a).dot(outward)
	if absf(dot) < EPSILON:
		return 0
	return -1 if dot < 0.0 else 1


func _triangles(mesh: Mesh, surface_index: int) -> Array[PackedVector3Array]:
	var arrays: Array = mesh.surface_get_arrays(surface_index)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# An ImmediateMesh surface carries no index buffer at all — the slot is `null`, not an empty
	# array — while a BoxMesh's is populated. Both are read the same way once the indices are
	# filled in, so neither caller needs to know which it has.
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i: int in range(verts.size()):
			indices.append(i)
	var out: Array[PackedVector3Array] = []
	for i: int in range(0, indices.size(), 3):
		out.append(
			PackedVector3Array([verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]]])
		)
	return out


## THE REFERENCE. Every non-tile box on the board is one of these, so whatever it does is the
## convention the tiles have to match — this test exists to state it in measured form, and to be
## the single place that changes if the engine ever does.
func test_the_reference_convention_a_real_box_mesh_winds_its_faces() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	var arrays: Array = box.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var triangles: Array[PackedVector3Array] = _triangles(box, 0)
	assert_eq(triangles.size(), 12, "sanity: a box is twelve triangles")
	for i: int in range(triangles.size()):
		var tri: PackedVector3Array = triangles[i]
		# The mesh's own stored normal is the outward direction, straight from the engine —
		# not one this test derives from the vertices it is about to judge.
		var outward: Vector3 = normals[indices[i * 3]]
		assert_eq(
			_winding_sign(tri[0], tri[1], tri[2], outward),
			_reference_sign(),
			"BoxMesh triangle %d winds against the reference" % i
		)


## The one number the file asserts against, kept in a function so the reference test above and
## the tile tests below cannot drift apart: a front face's emitted cross product points INTO the
## solid, i.e. its vertices run clockwise seen from outside.
func _reference_sign() -> int:
	return -1


func _one_tile_grid() -> Grid:
	var grid := Grid.new(1, 1)
	grid.add_surface(Vector2i(0, 0), Surface.new(DataLibrary.get_part(&"ship_floor"), 0.0))
	return grid


func _tile_mesh(grid: Grid) -> ImmediateMesh:
	var view := BoardView.new()
	add_child_autofree(view)
	var tiles: MeshInstance3D = view.call(&"_build_tiles", grid, DataLibrary.material_table())
	var mesh: ImmediateMesh = tiles.mesh
	tiles.queue_free()
	return mesh


## **The `BR55.02` assertion.** One tile, so the whole mesh is one box and its centre is simply
## the mean of its vertices — no second copy of the placement formula to agree with itself.
## Outward for a face is "away from that centre", which is true of any convex solid and needs no
## knowledge of which face is which.
func test_every_tile_face_is_wound_outward() -> void:
	var mesh: ImmediateMesh = _tile_mesh(_one_tile_grid())
	assert_eq(mesh.get_surface_count(), 1, "sanity: one material, one surface")
	var triangles: Array[PackedVector3Array] = _triangles(mesh, 0)
	assert_eq(triangles.size(), 12, "sanity: one tile is twelve triangles")

	var centre := Vector3.ZERO
	for tri: PackedVector3Array in triangles:
		centre += tri[0] + tri[1] + tri[2]
	centre /= float(triangles.size() * 3)

	var lines: PackedStringArray = []
	var wrong := 0
	for i: int in range(triangles.size()):
		var tri: PackedVector3Array = triangles[i]
		var centroid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		var outward: Vector3 = (centroid - centre).normalized()
		var sign_here: int = _winding_sign(tri[0], tri[1], tri[2], outward)
		if sign_here != _reference_sign():
			wrong += 1
		lines.append(
			(
				"tri %2d  centroid %+.2f,%+.2f,%+.2f  outward %+.2f,%+.2f,%+.2f  sign %+d"
				% [
					i,
					centroid.x,
					centroid.y,
					centroid.z,
					outward.x,
					outward.y,
					outward.z,
					sign_here
				]
			)
		)
	gut.p("tile box, centre %+.2f,%+.2f,%+.2f" % [centre.x, centre.y, centre.z])
	for line: String in lines:
		gut.p(line)
	assert_eq(wrong, 0, "%d of 12 tile faces wound inside out" % wrong)


## The face that actually matters to a player: a unit stands on it and it must be the one you can
## see. Called out separately from the all-faces sweep because "the top of the floor is visible"
## is the symptom `BR55.02` was reported as, and a regression should name it rather than say
## "3 of 12".
func test_the_top_face_of_a_tile_faces_up() -> void:
	var mesh: ImmediateMesh = _tile_mesh(_one_tile_grid())
	var triangles: Array[PackedVector3Array] = _triangles(mesh, 0)
	var top_y: float = -INF
	for tri: PackedVector3Array in triangles:
		top_y = maxf(top_y, maxf(tri[0].y, maxf(tri[1].y, tri[2].y)))

	var checked := 0
	for tri: PackedVector3Array in triangles:
		# A triangle all three of whose corners sit at the box's highest Y is a top-face one.
		if not (
			is_equal_approx(tri[0].y, top_y)
			and is_equal_approx(tri[1].y, top_y)
			and is_equal_approx(tri[2].y, top_y)
		):
			continue
		checked += 1
		assert_eq(
			_winding_sign(tri[0], tri[1], tri[2], Vector3.UP),
			_reference_sign(),
			"the top face is wound away from the camera looking down at it"
		)
	assert_eq(checked, 2, "sanity: the top face is two triangles")


## `_add_quad` is shared with `_build_grid_lines`, so a "fix" applied there instead of inside
## `_add_box` would have flipped the grid into the ground. It was already correct and this pass
## did not touch it; this pins that, so the next person tempted to reverse the shared helper
## fails a test instead of trading one invisible surface for another.
func test_the_grid_lines_still_face_up() -> void:
	var view := BoardView.new()
	add_child_autofree(view)
	var lines: MeshInstance3D = view.call(&"_build_grid_lines", Grid.new(2, 2))
	var triangles: Array[PackedVector3Array] = _triangles(lines.mesh, 0)
	assert_gt(triangles.size(), 0, "sanity: a 2x2 grid draws lines")
	var wrong := 0
	for tri: PackedVector3Array in triangles:
		if _winding_sign(tri[0], tri[1], tri[2], Vector3.UP) != _reference_sign():
			wrong += 1
	assert_eq(wrong, 0, "%d grid-line triangles face down" % wrong)
	lines.queue_free()
