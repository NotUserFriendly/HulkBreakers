extends GutTest

## taskblock-69 Pass C — **the deriving half: a click picks a sensible facing.**
##
## Reported as a veneer defect: *"veneers don't respect the facing of the clicked side of a thing.
## They also always place on one edge of a top face, and should align their facing to the edge.
## They're already getting the 'grow to' height from a piece, so they should face it as well.
## Ladders may need this behavior as well."* The supervisor's answer to the last sentence is **every
## blocker that has a facing**, so a ladder is a case here rather than an afterthought.
##
## **It was built once and backed out**, because the drawing half did not exist and a placement
## carrying a facing nothing renders is the visual/logic disagreement taskblock-59 spent a block
## removing. Passes A and B are that objection gone.
##
## ## The direction assertions are made against `BodyProjector.forward_for`, on purpose
##
## `facing_for` returns radians, and asserting a number (`-PI / 2.0`, say) would pin the arithmetic
## rather than the behaviour — and would pass just as well against the mirrored rotation convention
## `BodyProjector.rotate_by_orientation`'s own header describes deleting. So each case asks where
## the derived facing actually **points**, through the one authoritative forward, and compares that
## against a direction stated as a fact about the click.

## How close two directions must be to count as the same one.
const _NEAR := 0.001
## The cell every click in this file is against.
const _CELL := Vector2i(3, 3)
## The panel value a derivation is allowed to leave alone. Deliberately not a quarter turn and not
## zero, so a test cannot pass by accidentally agreeing with a derived axis.
const _AUTHORED := 0.37


## Where a derived facing points, on the ground plane. `BodyProjector.forward_for` is the single
## rotation convention in this codebase — never a second `atan2` written here.
func _points(facing: float) -> Vector2:
	return BodyProjector.forward_for(facing)


func _assert_points(facing: float, want: Vector2, what: String) -> void:
	var got: Vector2 = _points(facing)
	gut.p(
		(
			"  %s: facing %+.3f rad -> forward (%+.2f, %+.2f), want %s"
			% [what, facing, got.x, got.y, want]
		)
	)
	assert_almost_eq(got.x, want.x, _NEAR, "%s: x" % what)
	assert_almost_eq(got.y, want.y, _NEAR, "%s: y" % what)


## **A side click faces the placement back at the piece it hangs from.** The placement lands one
## step along the struck normal, so the thing it was hung off is one step against it — and a veneer
## authored against its own `+Z` then has that face against the ledge.
func test_a_side_click_faces_back_at_the_struck_piece() -> void:
	var cases: Array = [
		[Vector3.RIGHT, Vector2(-1.0, 0.0), "struck the east face"],
		[Vector3.LEFT, Vector2(1.0, 0.0), "struck the west face"],
		[Vector3.BACK, Vector2(0.0, -1.0), "struck the +Z face"],
		[Vector3.FORWARD, Vector2(0.0, 1.0), "struck the -Z face"],
	]
	for case: Array in cases:
		_assert_points(FacePlacement.facing_for(_CELL, case[0], null, _AUTHORED), case[1], case[2])


## **The landing cell and the derived facing are the same click read twice**, which is the property
## that makes "faces back at it" true rather than merely stated. The placement steps one way and
## points the other.
func test_a_side_clicks_facing_points_from_the_landing_cell_at_the_struck_one() -> void:
	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var landed: Dictionary = FacePlacement.target_for(_CELL, normal, 0.0, 0.0)
		var step: Vector2i = (landed["cell"] as Vector2i) - _CELL
		_assert_points(
			FacePlacement.facing_for(_CELL, normal, null, _AUTHORED),
			Vector2(float(-step.x), float(-step.y)),
			"normal %s landed at %s" % [normal, landed["cell"]]
		)


## **A top click reads the struck point and picks the nearest cell edge**, *"rather than always the
## edge the author happened to mean."* Four clicks in one cell, four edges.
func test_a_top_click_faces_the_cell_edge_nearest_the_struck_point() -> void:
	var cases: Array = [
		[Vector3(3.4, 1.0, 3.0), Vector2(1.0, 0.0), "clicked toward +X"],
		[Vector3(2.6, 1.0, 3.0), Vector2(-1.0, 0.0), "clicked toward -X"],
		[Vector3(3.0, 1.0, 3.4), Vector2(0.0, 1.0), "clicked toward +Z"],
		[Vector3(3.0, 1.0, 2.6), Vector2(0.0, -1.0), "clicked toward -Z"],
	]
	for case: Array in cases:
		_assert_points(
			FacePlacement.facing_for(_CELL, Vector3.UP, case[0], _AUTHORED), case[1], case[2]
		)


## **A near-diagonal click still resolves to an edge**, the same either-or `_side_step` applies to a
## normal. A cell has four edges and no corners to face.
func test_a_diagonal_top_click_resolves_to_the_edge_it_leans_further_toward() -> void:
	_assert_points(
		FacePlacement.facing_for(_CELL, Vector3.UP, Vector3(3.4, 1.0, 3.3), _AUTHORED),
		Vector2(1.0, 0.0),
		"leaning further along X"
	)
	_assert_points(
		FacePlacement.facing_for(_CELL, Vector3.UP, Vector3(3.3, 1.0, 3.4), _AUTHORED),
		Vector2(0.0, 1.0),
		"leaning further along Z"
	)


## **A click that implies no direction leaves the author's own value alone**, rather than snapping
## it to whichever axis the arithmetic happens to reach. Three cases, each a real one: a pick that
## resolved off the ground plane with no face at all, a top click whose pick reported no point, and
## the underside of something — nothing hangs off that at an edge.
func test_a_click_with_no_direction_in_it_keeps_the_authored_facing() -> void:
	assert_almost_eq(
		FacePlacement.facing_for(_CELL, null, null, _AUTHORED),
		_AUTHORED,
		_NEAR,
		"no struck face at all"
	)
	assert_almost_eq(
		FacePlacement.facing_for(_CELL, Vector3.UP, null, _AUTHORED),
		_AUTHORED,
		_NEAR,
		"a top face whose pick reported no point"
	)
	assert_almost_eq(
		FacePlacement.facing_for(_CELL, Vector3.DOWN, Vector3(3.4, 1.0, 3.0), _AUTHORED),
		_AUTHORED,
		_NEAR,
		"the underside of a thing"
	)


## **A ladder on the north face of a cell — the case that proves the derivation is not
## veneer-specific.** `ladder` authors its own box against `+Z` exactly as `ledge_veneer` does, is a
## `KIND_BLOCKER` by `EditorTools.kind_for` (it attaches at `LEDGE`, never `GROUND`), and nothing in
## the derivation knows either part exists.
##
## Asserted through the real placed boxes rather than through the angle: a click near the cell's
## `-Z` edge has to put the ladder's rungs against that edge.
func test_a_ladder_derives_a_facing_onto_the_north_face_of_a_cell() -> void:
	var facing: float = FacePlacement.facing_for(_CELL, Vector3.UP, Vector3(3.0, 1.0, 2.6), 0.0)
	var grid := GridFixture.flat(7, 7)
	grid.place_blocker(
		_CELL, DataLibrary.get_part(&"ladder"), 0.0, Vector3.ZERO, Vector3.ZERO, facing
	)

	var placed: AABB = UnitGeometry.placements_aabb(UnitGeometry.blocker_placements(_CELL, grid))
	var panel: Vector3 = placed.get_center()
	gut.p("  ladder panel centre %s for cell %s" % [panel, _CELL])

	assert_lt(panel.z, float(_CELL.y) - 0.3, "the rungs must sit against the cell's own -Z edge")
	assert_almost_eq(panel.x, float(_CELL.x), 0.001, "and stay centred on the other axis")


## **The derivation is a default written once, not a rule re-applied on read** — which is the whole
## reason it is stored. An adjustment made after placement has to survive being saved, reloaded,
## and drawn again, or every later edit is undone by the next thing that asks for geometry.
##
## **Flagged, and this is the honest state of it:** the manipulation gizmo has no rotate handle
## today. `Gizmo.Handles` is `TRANSLATE, RESIZE` and nothing else, so *"the gizmo overrides it"*
## cannot be driven through the gizmo. What is asserted here is the property that makes such an
## override possible — the record is the authority, and nothing recomputes over the top of it. See
## `PLAN`'s own rotate-handle item.
func test_an_adjusted_facing_survives_a_save_load_and_a_redraw() -> void:
	var derived: float = FacePlacement.facing_for(_CELL, Vector3.RIGHT, null, 0.0)
	var adjusted: float = derived + PI / 2.0

	var map := MapFile.new()
	map.width = 7
	map.rows = 7
	for y: int in range(7):
		for x: int in range(7):
			map.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor")
			)
	map.placements.append(
		MapPlacement.new(_CELL, MapPlacement.KIND_BLOCKER, &"ledge_veneer", 0.0, derived)
	)
	var first: Dictionary = MapSerializer.to_grid(map)
	assert_eq(first.get("error", ""), "", "the derived placement must load")
	var grid: Grid = first["grid"]
	assert_almost_eq(
		grid.blocker_at(_CELL).facing, derived, _NEAR, "the record carries what the click derived"
	)

	# The override — the write a rotate handle would make, applied to the same record.
	grid.blocker_at(_CELL).facing = adjusted

	var reloaded: Dictionary = MapSerializer.to_grid(
		MapSerializer.to_map_file(grid, "an adjusted facing")
	)
	assert_eq(reloaded.get("error", ""), "", "and must round trip")
	var back: Grid = reloaded["grid"]
	assert_almost_eq(
		back.blocker_at(_CELL).facing, adjusted, _NEAR, "the override survived the round trip"
	)

	# And the redraw — read off the real node, never re-derived. See `test_blocker_facing_render.gd`.
	var view := BoardView.new()
	add_child_autofree(view)
	view.build(back, DataLibrary.material_table())
	var drawn: MeshInstance3D = null
	for child: Node in view._static.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			drawn = child as MeshInstance3D
	assert_not_null(drawn, "the reloaded veneer must be drawn at all")
	if drawn == null:
		return
	var expected: Array[BoxPlacement] = UnitGeometry.blocker_placements(_CELL, back)
	assert_almost_eq(
		drawn.global_transform.origin.distance_to(
			expected[0].transform.translated_local(expected[0].box.center).origin
		),
		0.0,
		_NEAR,
		"the redraw used the overridden facing, not a re-derived one"
	)
	# And the half that a redraw ignoring the override would still pass: it is **not** where the
	# derived facing would have put it.
	var pre_override: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		back.blocker_part_at(_CELL), _CELL, derived, null, 0.0
	)
	assert_gt(
		drawn.global_transform.origin.distance_to(
			pre_override[0].transform.translated_local(pre_override[0].box.center).origin
		),
		0.3,
		"the redraw would have looked identical if the override had been recomputed away"
	)
