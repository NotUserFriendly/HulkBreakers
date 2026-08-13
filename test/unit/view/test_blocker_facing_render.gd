extends GutTest

## taskblock-69 Pass B — **the drawing half: what the board renders is the record's facing.**
##
## Pass A routed every blocker consumer through `UnitGeometry.blocker_placements`, so a rotated
## blocker already blocks, occludes and takes hits rotated. This file asserts the other half — that
## the picture agrees — and it asserts it **off the real `MeshInstance3D`**, not off a second copy
## of the placement expression.
##
## ## The readback rule, and why a basis comparison would not have satisfied it
##
## CLAUDE.md: *"a formula and a test that re-derives it agree with each other and with nothing
## else."* Asserting `mesh.global_transform.basis == Basis(Vector3.UP, facing)` is exactly that
## re-derivation — it would pass against a board that composed the rotation the mirrored way round,
## which is a real bug this codebase has had before (`BodyProjector.rotate_by_orientation`'s own
## header, and the asymmetric-part mirror test that pins it).
##
## **So the expectation is stated as a fact about the board instead of as an expression**: a ledge
## veneer hangs against one edge of its cell, and turning it a quarter turn at a time walks that
## edge around the cell in a named order. The test reads where the drawn box actually ended up.
##
## ## `ledge_veneer` is the part, and it is the content that motivated the block
##
## Its authored box is `center (0, 0.4, 0.45)`, `size (1.0, 0.8, 0.1)` — a thin panel hard against
## its own `+Z` face. `wall` is a centred cube, and a cube rotated about its own vertical axis is
## the same cube in the same place, so it could not tell a working rotation from a discarded one.

const _CELL := Vector2i(3, 3)
## The four quarter turns and the cell edge each one hangs the veneer's panel against, as a
## direction from the cell's own centre. **Authored here as the intended behaviour**, so a board
## that composed its rotation the mirrored way round fails rather than agreeing with itself.
const _QUARTER_TURNS: Array = [
	[0.0, Vector3(0.0, 0.0, 1.0)],
	[PI / 2.0, Vector3(1.0, 0.0, 0.0)],
	[PI, Vector3(0.0, 0.0, -1.0)],
	[3.0 * PI / 2.0, Vector3(-1.0, 0.0, 0.0)],
]
## How far the veneer's panel sits from its cell centre — its authored box centre's own `z`. Read
## off the part rather than restated, so a re-authored veneer does not silently pass.
const _PANEL_OFFSET := 0.45


func _board_with_veneer(facing: float) -> BoardView:
	var grid := GridFixture.flat(7, 7)
	grid.place_blocker(
		_CELL, DataLibrary.get_part(&"ledge_veneer"), 0.0, Vector3.ZERO, Vector3.ZERO, facing
	)
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	return view


## The one `BoxMesh` the veneer contributed, read off the built scene. The board also draws tiles
## and grid lines, and those are `ImmediateMesh` — a blocker's box is the only `BoxMesh` here.
func _drawn_box(view: BoardView) -> MeshInstance3D:
	var found: Array[MeshInstance3D] = []
	for child: Node in view._static.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			found.append(child as MeshInstance3D)
	assert_eq(found.size(), 1, "exactly one blocker box should have been drawn")
	return found[0] if found.size() == 1 else null


## **A blocker placed at each quarter turn renders where its record says.** Four turns, four cell
## edges, read back off the node.
func test_a_blocker_renders_at_each_quarter_turn_of_its_record() -> void:
	var authored: float = DataLibrary.get_part(&"ledge_veneer").volume[0].center.z
	assert_almost_eq(
		authored, _PANEL_OFFSET, 0.0001, "the veneer must still author its panel against +Z"
	)

	for turn: Array in _QUARTER_TURNS:
		var facing: float = turn[0]
		var edge: Vector3 = turn[1]
		var mesh: MeshInstance3D = _drawn_box(_board_with_veneer(facing))
		if mesh == null:
			continue
		var centre: Vector3 = mesh.global_transform.origin
		var from_cell: Vector3 = centre - Vector3(float(_CELL.x), centre.y, float(_CELL.y))
		gut.p(
			(
				"  facing %.2f rad -> panel at %+.2f, %+.2f from cell centre (want %s)"
				% [facing, from_cell.x, from_cell.z, edge]
			)
		)
		assert_almost_eq(
			from_cell.x, edge.x * _PANEL_OFFSET, 0.001, "facing %.2f: the panel's x" % facing
		)
		assert_almost_eq(
			from_cell.z, edge.z * _PANEL_OFFSET, 0.001, "facing %.2f: the panel's z" % facing
		)


## **The thin axis turns with it**, which is the half a translation-only bug would still pass. A
## panel that moved to the east edge while staying thin on Z would be drawn edge-on to its own
## ledge. Read off the real `BoxMesh` size composed through the real node's own basis.
func test_a_turned_blockers_thin_axis_turns_with_it() -> void:
	var flat: MeshInstance3D = _drawn_box(_board_with_veneer(0.0))
	var turned: MeshInstance3D = _drawn_box(_board_with_veneer(PI / 2.0))
	if flat == null or turned == null:
		return

	var flat_extent: Vector3 = _world_extent(flat)
	var turned_extent: Vector3 = _world_extent(turned)
	gut.p("  facing 0.00 world extent %s" % flat_extent)
	gut.p("  facing 1.57 world extent %s" % turned_extent)

	assert_almost_eq(flat_extent.x, 1.0, 0.001, "unturned, the panel spans the cell on X")
	assert_almost_eq(flat_extent.z, 0.1, 0.001, "and is its own thickness on Z")
	assert_almost_eq(turned_extent.x, 0.1, 0.001, "turned, the thickness is on X")
	assert_almost_eq(turned_extent.z, 1.0, 0.001, "and the span is on Z")


## **The regression guard for the whole block.** Every board authored before this has
## `facing = 0.0`, so nothing on disk may move. Asserted against the expression the board used
## before Pass A — `assembly_placements(part, cell, 0.0, null, height)` — rather than against a
## remembered number, so it is the old answer and the new one being compared directly.
##
## `proving_ground.tres` is the authored corpus and carries no facing at all; this is the same
## claim made about arbitrary geometry, at the tolerance the assertion can actually hold.
func test_a_facing_of_zero_draws_exactly_what_it_drew_before() -> void:
	var grid := GridFixture.flat(7, 7)
	GridFixture.place_floor(grid, Vector2i(4, 2), 2)
	for cell: Vector2i in [_CELL, Vector2i(4, 2), Vector2i(1, 5)]:
		grid.place_blocker(cell, DataLibrary.get_part(&"ledge_veneer").duplicate(true))

	for cell: Vector2i in [_CELL, Vector2i(4, 2), Vector2i(1, 5)]:
		var old: Array[BoxPlacement] = UnitGeometry.assembly_placements(
			grid.blocker_part_at(cell),
			cell,
			0.0,
			null,
			UnitGeometry.blocker_height_for_cell(cell, grid)
		)
		var accessor: Array[BoxPlacement] = UnitGeometry.blocker_placements(cell, grid)
		assert_eq(accessor.size(), old.size(), "%s: the same number of boxes" % cell)
		for i in range(mini(old.size(), accessor.size())):
			assert_eq(
				accessor[i].transform,
				old[i].transform,
				"%s box %d: an unturned blocker's transform is unchanged" % [cell, i]
			)
			assert_eq(accessor[i].box, old[i].box, "%s box %d: and its box" % [cell, i])


## The world-space extent of a drawn box — its own `BoxMesh` size taken through its own node's
## basis, corner by corner. **Not `mesh.size` directly**: that is the local size, and the whole
## question here is what the rotation did to it.
func _world_extent(mesh_instance: MeshInstance3D) -> Vector3:
	var half: Vector3 = (mesh_instance.mesh as BoxMesh).size * 0.5
	var basis: Basis = mesh_instance.global_transform.basis
	var low := Vector3.INF
	var high := -Vector3.INF
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner: Vector3 = basis * Vector3(sx * half.x, sy * half.y, sz * half.z)
				low = low.min(corner)
				high = high.max(corner)
	return high - low
