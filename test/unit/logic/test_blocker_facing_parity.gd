extends GutTest

## taskblock-69 Pass A — **one blocker, one facing, and every consumer agrees.**
##
## `Blocker.facing` landed at taskblock-63 Pass D3 and was written, saved, loaded and then
## discarded by every consumer: nine call sites turned a blocker into boxes and every one of them
## passed a literal `0.0` as the orientation. So a placement's facing survived being saved and did
## not survive being looked at.
##
## **This file is the property, not the plumbing.** Fixing only the view would have drawn a veneer
## rotated while it blocked, occluded and took hits unrotated — *render is hitbox* broken from the
## other side, which is the exact class taskblock-59 spent a block removing. So each consumer is
## asked the same question about the same board and has to give the same answer.
##
## ## Why a probe point rather than a box comparison
##
## Comparing each consumer's boxes against `UnitGeometry.blocker_placements`' boxes would prove
## only that they call the same function, which is what the diff already shows. The question worth
## asking is behavioural: **is there a place in the world that is solid only because the blocker is
## turned?** `_ROTATED_PROBE` is such a place — inside the rotated wall, empty when the same wall
## sits at facing `0.0` — so a consumer that ignored the facing answers "empty" there and fails.
## The unrotated control (`_UNROTATED_PROBE`) is the other half: a consumer that rotated *twice*,
## or the wrong way, would pass the first half and fail this one.
##
## ## The blocker is long on purpose, and exactly one cell thick
##
## `wall` is a 1x1 cube, and a cube rotated about Y is the same cube — a facing-blind consumer
## would pass every assertion here. `_SIZE` resizes it to three cells long, which `MapPlacement.
## size` already expresses and `PlacedVolume.placed_part` already bakes into the part's real
## `volume` (taskblock-58 Pass F). Turned a quarter turn it occupies an entirely different set of
## cells, which is what makes disagreement visible at all.
##
## **A *thinner* wall would have been a better shape and does not work, for a documented reason.**
## `SightSpans` registers only the cells a box **fully** covers on X and Z — its own header calls
## that the safe direction and says a sub-cell-thick wall blocks the real march without appearing
## in the spans at all. So a 0.2-thick wall would have made one of the consumers under test
## answer "clear" for reasons that have nothing to do with facing. One cell thick keeps every
## consumer answering the same question.

## Three cells long on X, one cell on Y and Z. See the header.
const _SIZE := Vector3(3.0, 1.0, 1.0)
## Where the wall stands. Middle of a 7x7 board so the long axis fits either way round.
const _CELL := Vector3i(3, 0, 3)
## A quarter turn — the convention `Surface.facing` and `Unit.orientation` use.
const _QUARTER := PI / 2.0
## The board's own extent. Big enough that a three-cell wall turned either way stays on it.
const _WIDTH := 7

## **Solid only when the wall is turned.** Two cells north of the wall's own cell, on the long
## axis the quarter turn swings into place. At facing `0.0` the wall runs along X and this point
## is a metre of empty air.
const _ROTATED_PROBE := Vector3(3.0, 0.5, 4.0)
## **Solid only when the wall is not turned.** The mirror of the above, on the X axis the wall
## occupies at facing `0.0`. A consumer that turned the wall when it should not have, or turned it
## the wrong way and back, fails here rather than passing by symmetry.
const _UNROTATED_PROBE := Vector3(4.0, 0.5, 3.0)


func _cell() -> Vector2i:
	return Vector2i(_CELL.x, _CELL.z)


## A flat board with one resized `wall` blocker at `_cell()`, authored through `MapSerializer` so
## the facing under test is one that really survived a load rather than one poked into the grid.
func _board(facing: float) -> Grid:
	var map := MapFile.new()
	map.width = _WIDTH
	map.rows = _WIDTH
	for y: int in range(_WIDTH):
		for x: int in range(_WIDTH):
			map.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor")
			)
	map.placements.append(
		MapPlacement.new(_cell(), MapPlacement.KIND_BLOCKER, &"wall", 0.0, facing, _SIZE)
	)
	var loaded: Dictionary = MapSerializer.to_grid(map)
	assert_eq(loaded.get("error", ""), "", "the authored board must load")
	return loaded.get("grid")


## True when `point` sits inside any box the accessor places for the blocker at `_cell()`. The
## reference answer every consumer below is measured against.
func _accessor_covers(grid: Grid, point: Vector3) -> bool:
	for placement: BoxPlacement in UnitGeometry.blocker_placements(_cell(), grid):
		var local: Vector3 = placement.transform.affine_inverse() * point
		var half: Vector3 = placement.box.size * 0.5
		var delta: Vector3 = local - placement.box.center
		if absf(delta.x) <= half.x and absf(delta.y) <= half.y and absf(delta.z) <= half.z:
			return true
	return false


## A short ray ending at `point`, aimed straight down from a metre above it. Every ray-shaped
## consumer gets the same one, so "they agree" is about the geometry rather than about the probe.
func _probe_from(point: Vector3) -> Vector3:
	return point + Vector3(0.0, 1.0, 0.0)


## An ASCII plan of which cells the blocker's boxes cover, at the probe height. **The dump
## CLAUDE.md requires for anything spatial** — a facing that comes out wrong is a picture here, not
## an assertion message.
func _plan(grid: Grid, label: String) -> String:
	var out: String = "\n%s\n" % label
	for z: int in range(_WIDTH):
		var row: String = ""
		for x: int in range(_WIDTH):
			var here := Vector3(float(x), 0.5, float(z))
			row += "#" if _accessor_covers(grid, here) else "."
		out += row + "\n"
	return out


## **The accessor itself.** A non-zero facing has to move the boxes at all before anything
## downstream can be asked whether it agrees.
func test_a_non_zero_facing_produces_rotated_boxes_from_the_accessor() -> void:
	var straight: Grid = _board(0.0)
	var turned: Grid = _board(_QUARTER)
	gut.p(_plan(straight, "facing 0.0 — the wall runs along X"))
	gut.p(_plan(turned, "facing PI/2 — the wall runs along Z"))

	assert_true(
		_accessor_covers(straight, _UNROTATED_PROBE), "unturned, the wall runs along X and is solid"
	)
	assert_false(
		_accessor_covers(straight, _ROTATED_PROBE), "and the Z probe is a metre of empty air"
	)
	assert_true(_accessor_covers(turned, _ROTATED_PROBE), "a quarter turn swings it onto Z")
	assert_false(
		_accessor_covers(turned, _UNROTATED_PROBE), "and off X — it moved, it did not grow"
	)


## **The parity property, and the reason this block exists.** Every consumer that turns a blocker
## into geometry is asked whether the rotated probe is solid, and every one of them must say yes —
## on the same board, about the same wall.
##
## The consumers are named individually rather than looped, because a failure that says *which*
## one disagreed is the whole diagnostic value. A tenth consumer added later that builds its own
## boxes is exactly what this is here to catch.
##
## **`CameraFramingModule` is the one consumer not asked here**, and it gets its own test below.
## Its answer is a single AABB merged over the whole board, so on a floored board it already
## contains both probe points whatever the wall does — a probe would pass either way, which is a
## test that agrees with itself.
func test_every_blocker_consumer_agrees_about_a_rotated_wall() -> void:
	var grid: Grid = _board(_QUARTER)
	var part: Part = grid.blocker_part_at(_cell())
	var from: Vector3 = _probe_from(_ROTATED_PROBE)
	var down := Vector3.DOWN
	gut.p(_plan(grid, "facing PI/2 — every consumer below is asked about (3, 4)"))

	assert_true(_accessor_covers(grid, _ROTATED_PROBE), "the accessor: solid")

	var marched: RayHit = RayCaster.cast_geometry(grid, from, down)
	assert_not_null(marched, "RayCaster.cast_geometry: the round meets something")
	if marched != null:
		assert_eq(marched.body, part, "RayCaster.cast_geometry: and it is the wall")

	assert_true(
		RayCaster.obstructed(grid, from, _ROTATED_PROBE + Vector3(0.0, -0.4, 0.0)),
		"RayCaster.obstructed: the sight predicate agrees"
	)
	assert_eq(
		RayCaster.blocker_obstructed_among(grid, [_cell()], from, [_ROTATED_PROBE]),
		_cell(),
		"RayCaster.blocker_obstructed_among: the wall-cutout gate agrees"
	)

	assert_true(
		SightSpans.of(grid).blocks(Vector2i(3, 4), 0.5), "SightSpans: the cell occludes at 0.5"
	)

	var clicked: Dictionary = PartPicker.hit([], grid, from, down)
	assert_false(clicked.is_empty(), "PartPicker: a click there strikes something")
	if not clicked.is_empty():
		assert_eq(clicked["part"], part, "PartPicker: and it is the wall")

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	assert_true(_view_covers(view, _ROTATED_PROBE), "BoardView: a drawn mesh occupies the point")


## **The other half, and the one a double rotation fails.** The same consumers, the same board,
## asked about the point the wall occupies *only* when it is not turned. Every one must say empty.
func test_every_blocker_consumer_agrees_a_rotated_wall_left_the_x_axis() -> void:
	var grid: Grid = _board(_QUARTER)
	var from: Vector3 = _probe_from(_UNROTATED_PROBE)
	var down := Vector3.DOWN

	assert_false(_accessor_covers(grid, _UNROTATED_PROBE), "the accessor: empty")

	var marched: RayHit = RayCaster.cast_geometry(grid, from, down)
	assert_true(
		marched == null or marched.body != grid.blocker_part_at(_cell()),
		"RayCaster.cast_geometry: the wall is not there any more"
	)
	assert_null(
		RayCaster.blocker_obstructed_among(grid, [_cell()], from, [_UNROTATED_PROBE]),
		"RayCaster.blocker_obstructed_among: nothing in the way"
	)
	assert_false(SightSpans.of(grid).blocks(Vector2i(4, 3), 0.5), "SightSpans: the cell is clear")

	var clicked: Dictionary = PartPicker.hit([], grid, from, down)
	assert_true(
		clicked.is_empty() or clicked["part"] != grid.blocker_part_at(_cell()),
		"PartPicker: a click there does not select the wall"
	)

	var view := BoardView.new()
	add_child_autofree(view)
	view.build(grid, DataLibrary.material_table())
	assert_false(_view_covers(view, _UNROTATED_PROBE), "BoardView: nothing is drawn there")


## **A field item carries no record and must not have moved.** Pass A leaves the four field-item
## call sites on the raw `assembly_placements` call deliberately; this is what says so in a test
## rather than only in a comment. A loose part is placed at the same cell on a board whose blocker
## is turned, and its own boxes stay exactly where they were.
func test_a_loose_field_item_is_unaffected_by_the_blocker_accessor() -> void:
	var grid: Grid = _board(_QUARTER)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 5
	crate.max_hp = 5
	crate.volume = [Box.new(Vector3(0.0, 0.5, 0.0), _SIZE)]
	grid.field_items[Vector2i(1, 1)] = [crate]

	var expected: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		crate, Vector2i(1, 1), 0.0, null, UnitGeometry.true_height_for_cell(Vector2i(1, 1), grid)
	)
	assert_eq(expected.size(), 1, "the crate is one box")

	# The same long-thin shape as the wall, so a facing leaking into the field-item path would
	# swing it onto Z exactly as it swings the wall — and this asserts it stayed on X.
	var probe: Vector3 = Vector3(2.0, 0.5, 1.0)
	var from: Vector3 = _probe_from(probe)
	var marched: RayHit = RayCaster.cast_geometry(grid, from, Vector3.DOWN)
	assert_not_null(marched, "the loose crate still lies along X")
	if marched != null:
		assert_eq(marched.body, crate, "and it is the crate the ray meets")

	var clicked: Dictionary = PartPicker.hit([], grid, from, Vector3.DOWN)
	assert_false(clicked.is_empty(), "the picker still finds it")
	if not clicked.is_empty():
		assert_eq(clicked["part"], crate, "at the unrotated position")
	assert_true(SightSpans.of(grid).blocks(Vector2i(2, 1), 0.5), "and it still occludes there")


## True when any mesh the board drew has `point` inside it. **The real node read back**, per
## CLAUDE.md — `global_transform` off the built `MeshInstance3D` and the `BoxMesh`'s own size,
## never a second copy of the placement formula.
func _view_covers(view: BoardView, point: Vector3) -> bool:
	for child: Node in view._static.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance := child as MeshInstance3D
		if not (mesh_instance.mesh is BoxMesh):
			continue
		var half: Vector3 = (mesh_instance.mesh as BoxMesh).size * 0.5
		var local: Vector3 = mesh_instance.global_transform.affine_inverse() * point
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false


## **The tenth consumer**, and one the taskblock's own table of nine did not list:
## `CameraFramingModule.content_bounds` builds a blocker's boxes to work out what the camera has
## to fit on screen, and passed a literal `0.0` orientation exactly as the other nine did. It is
## here because the property is *every* blocker consumer agrees, not *the nine that were named*.
##
## Measured on a grid holding nothing but the wall, so the bounds **are** the wall. On a floored
## board the floor's own extent dominates the merge and a rotated wall changes nothing about the
## answer — which is why this is a separate board rather than an assertion in the parity test.
func test_the_camera_framing_bounds_follow_a_blockers_facing() -> void:
	var straight := Grid.new(_WIDTH, _WIDTH)
	var turned := Grid.new(_WIDTH, _WIDTH)
	var part: Part = PlacedVolume.placed_part(DataLibrary.get_part(&"wall"), _SIZE)
	straight.place_blocker(_cell(), part, 0.0, _SIZE, Vector3.ZERO, 0.0)
	turned.place_blocker(_cell(), part, 0.0, _SIZE, Vector3.ZERO, _QUARTER)

	var flat: AABB = CameraFramingModule.content_bounds(straight)
	var swung: AABB = CameraFramingModule.content_bounds(turned)

	assert_almost_eq(flat.size.x, 3.0, 0.001, "unturned, the framing is three cells wide on X")
	assert_almost_eq(flat.size.z, 1.0, 0.001, "and one deep on Z")
	assert_almost_eq(swung.size.x, 1.0, 0.001, "a quarter turn makes it one wide on X")
	assert_almost_eq(swung.size.z, 3.0, 0.001, "and three deep on Z")


## **Claims, the sixth consumer the acceptance names — and the one that never had the defect.**
##
## `ClaimResolver.placement_aabb` works from a `MapPlacement` rather than from `Grid.blockers`, so
## it read `placement.facing` all along. What it did not do was *measure* the rotated boxes
## correctly: it built each box's AABB as `centre ± size / 2`, which a rotation does not move. So
## the two halves of the same authored placement disagreed across the serializer, and this is the
## assertion that says they no longer do.
##
## **`ledge_veneer` rather than the resized `wall` the rest of this file uses**, and the reason is
## `BR69.01`: `placement_aabb` never applies `PlacedVolume.placed_part`, so a claim measures the
## library part's own boxes and ignores `MapPlacement.size` outright. A resized wall could not be
## compared here without asserting that open defect away. The veneer needs no size — it authors an
## asymmetric box hard against its own `+Z` face, which is the content that motivated this whole
## block, and a quarter turn swings it onto `-X`.
func test_a_section_claim_measures_the_same_footprint_the_board_places() -> void:
	var authored := MapPlacement.new(
		_cell(), MapPlacement.KIND_BLOCKER, &"ledge_veneer", 0.0, _QUARTER
	)
	var grid := Grid.new(_WIDTH, _WIDTH)
	grid.place_blocker(
		_cell(), DataLibrary.get_part(&"ledge_veneer"), 0.0, Vector3.ZERO, Vector3.ZERO, _QUARTER
	)
	var claimed: AABB = ClaimResolver.placement_aabb(authored, Vector2i.ZERO)
	var placed: AABB = UnitGeometry.placements_aabb(UnitGeometry.blocker_placements(_cell(), grid))

	assert_almost_eq(claimed.position.x, placed.position.x, 0.001, "the claim starts where it sits")
	assert_almost_eq(claimed.position.z, placed.position.z, 0.001, "on both axes")
	assert_almost_eq(claimed.size.x, placed.size.x, 0.001, "and is as wide as the real boxes")
	assert_almost_eq(claimed.size.z, placed.size.z, 0.001, "and as deep")

	var flat: AABB = ClaimResolver.placement_aabb(
		MapPlacement.new(_cell(), MapPlacement.KIND_BLOCKER, &"ledge_veneer"), Vector2i.ZERO
	)
	assert_almost_eq(flat.size.x, 1.0, 0.001, "unturned, the veneer is a cell wide on X")
	assert_almost_eq(claimed.size.x, 0.1, 0.001, "turned, it is its own thickness on X instead")


## **Detonation, the fifth consumer the acceptance names — and the one a facing cannot move.**
##
## `Detonation._origin`'s blocker branch builds no boxes at all: it answers the blocker's own cell
## centre, and `Detonation.resolve` measures reach in whole cells with `Grid.distance_chebyshev`.
## A rotation about the cell's own vertical axis leaves that centre exactly where it was, so there
## is nothing here for a facing to change — which is a fact worth pinning rather than a gap worth
## routing through the accessor. Turning a barrel does not move the barrel.
##
## The limit that *is* real, and is not this block's: `MapPlacement.offset` genuinely does displace
## a blocker from its cell centre, and this branch does not read it. That is `PLAN`'s *a cell holds
## one blocker* territory, where the same one-blocker-per-cell assumption lives.
func test_a_rotated_blocker_detonates_from_the_same_place_it_always_did() -> void:
	var straight := CombatState.new(_board(0.0))
	var turned := CombatState.new(_board(_QUARTER))
	var flat: Vector3 = Detonation._origin(straight.grid.blocker_part_at(_cell()), straight)
	var swung: Vector3 = Detonation._origin(turned.grid.blocker_part_at(_cell()), turned)

	assert_eq(flat, swung, "a blast starts at the cell the blocker stands on, turned or not")
	assert_almost_eq(swung.x, float(_cell().x), 0.001, "which is that cell")
	assert_almost_eq(swung.z, float(_cell().y), 0.001, "on both axes")
