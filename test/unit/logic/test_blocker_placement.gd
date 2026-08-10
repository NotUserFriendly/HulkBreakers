extends GutTest

## taskblock-63 Pass D3, `BR62.05` — **a blocker's placement survives being saved.**
##
## `MapPlacement` has carried `height`, `size`, `offset` and `facing` since taskblock-59.
## `MapSerializer` dropped all four for blockers: load did `grid.blockers[cell] = part` — the
## part and nothing else — and save reconstructed a placement from the cell and the part id
## alone. **It round-tripped because both ends discarded the same fields**, so an author could
## place a wall at height 4.0, save, load, and get a wall at 0, silently.
##
## **Each field is asserted separately and on purpose.** The old round trip passed by dropping
## both ways, so any test comparing "the map before" to "the map after" agreed with itself and
## with nothing else — which is exactly the failure mode CLAUDE.md names for re-derived view
## maths, one layer over. A field that survives has to be checked against **what was authored**,
## not against what came back.

const WALL := &"wall"


func _map_with_blocker(placement: MapPlacement) -> Grid:
	var map := MapFile.new()
	map.width = 6
	map.rows = 6
	for y: int in range(6):
		for x: int in range(6):
			map.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor")
			)
	map.placements.append(placement)
	var loaded: Dictionary = MapSerializer.to_grid(map)
	assert_eq(loaded.get("error", ""), "", "the authored map must load")
	return loaded.get("grid")


## **The four fields, one at a time.** Authored, saved, reloaded, and each compared against the
## number that went in.
func test_an_authored_blockers_height_size_offset_and_facing_all_survive_a_round_trip() -> void:
	var authored := MapPlacement.new(
		Vector2i(3, 3),
		MapPlacement.KIND_BLOCKER,
		WALL,
		4.0,  # height — the field a +4 generation shelf needs and nothing authored before
		PI / 2.0,  # facing
		Vector3(3.0, 1.0, 0.5),  # size
		Vector3(0.25, 0.0, -0.25)  # offset
	)
	var grid: Grid = _map_with_blocker(authored)

	var round_tripped: Dictionary = MapSerializer.to_grid(
		MapSerializer.to_map_file(grid, "blocker round trip")
	)
	assert_eq(round_tripped.get("error", ""), "", "and must reload without complaint")
	var record: Blocker = (round_tripped["grid"] as Grid).blocker_at(Vector2i(3, 3))

	assert_not_null(record, "a blocker must still be there at all")
	if record == null:
		return
	assert_eq(record.part.id, WALL, "the part")
	assert_almost_eq(record.height, 4.0, 0.0001, "the height — BR62.05's own worked example")
	assert_almost_eq(record.facing, PI / 2.0, 0.0001, "the facing")
	assert_almost_eq(record.size.x, 3.0, 0.0001, "the size, x")
	assert_almost_eq(record.size.y, 1.0, 0.0001, "the size, y")
	assert_almost_eq(record.size.z, 0.5, 0.0001, "the size, z")
	assert_almost_eq(record.offset.x, 0.25, 0.0001, "the offset, x")
	assert_almost_eq(record.offset.z, -0.25, 0.0001, "the offset, z")


## **The anti-vacuity half, and the one that would have caught the original defect.** A test
## that only compared before against after passed while both ends dropped the same fields — so
## this asserts against the *authored* placement, on the first load, before any save is
## involved.
func test_the_first_load_already_carries_what_was_authored() -> void:
	var grid: Grid = _map_with_blocker(
		MapPlacement.new(
			Vector2i(2, 2), MapPlacement.KIND_BLOCKER, WALL, 4.0, 0.0, Vector3(2.0, 1.0, 1.0)
		)
	)

	var record: Blocker = grid.blocker_at(Vector2i(2, 2))
	assert_almost_eq(record.height, 4.0, 0.0001, "load must not discard the height")
	assert_almost_eq(record.size.x, 2.0, 0.0001, "nor the size")


## The default, which is every blocker on every board authored before the record existed. `0.0`
## has to keep meaning "resting on the tile" or this change moves the entire existing library.
func test_a_blocker_with_no_authored_height_still_rests_on_its_tile() -> void:
	var grid: Grid = _map_with_blocker(
		MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_BLOCKER, WALL)
	)

	assert_eq(grid.blocker_at(Vector2i(1, 1)).height, 0.0, "no authored height means the floor")
	assert_almost_eq(
		UnitGeometry.blocker_height_for_cell(Vector2i(1, 1), grid),
		UnitGeometry.true_height_for_cell(Vector2i(1, 1), grid),
		0.0001,
		"so the geometry answer is the tile's own, exactly as it was"
	)


## **The picture and the shot must agree about where a raised blocker is**, which is the whole
## reason the height reaches `UnitGeometry` rather than only `BoardView`. Asserted against the
## real placed boxes rather than against a second copy of the sum.
func test_a_raised_blockers_geometry_and_the_shot_plane_read_the_same_height() -> void:
	var grid: Grid = _map_with_blocker(
		MapPlacement.new(Vector2i(4, 2), MapPlacement.KIND_BLOCKER, WALL, 4.0)
	)
	var state := CombatState.new(grid)

	var resolved: float = UnitGeometry.blocker_height_for_cell(Vector2i(4, 2), grid)
	assert_almost_eq(resolved, 4.0, 0.0001, "a wall authored at +4 resolves at +4")

	var plane: Array[Region] = ShotPlane.build(Vector3(0.0, 4.5, 2.0), Vector3.RIGHT, state, false)
	var lowest := INF
	for region: Region in plane:
		if region.body == grid.blocker_part_at(Vector2i(4, 2)):
			lowest = minf(lowest, region.rect.position.y)
	assert_ne(lowest, INF, "the plane must hold the raised wall")

	var boxes: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		grid.blocker_part_at(Vector2i(4, 2)), Vector2i(4, 2), 0.0, null, resolved
	)
	var drawn := INF
	for placement: BoxPlacement in boxes:
		drawn = minf(
			drawn, (placement.transform * placement.box.center).y - placement.box.size.y * 0.5
		)
	assert_almost_eq(lowest, drawn, 0.0001, "and it sits where the drawn geometry sits")


## A blocker moved by a debug verb keeps its placement facts and its damage. Worth its own case
## because the tempting implementation — rebuild the record at the new cell — silently drops
## whatever the old one carried, and nothing about the part would show it.
func test_moving_a_blocker_carries_its_placement_and_its_damage() -> void:
	var grid: Grid = _map_with_blocker(
		MapPlacement.new(Vector2i(2, 3), MapPlacement.KIND_BLOCKER, WALL, 4.0)
	)
	grid.blocker_part_at(Vector2i(2, 3)).hp = 7

	grid.move_blocker(Vector2i(2, 3), Vector2i(5, 5))

	assert_false(grid.blockers.has(Vector2i(2, 3)), "it left the cell it was on")
	var moved: Blocker = grid.blocker_at(Vector2i(5, 5))
	assert_almost_eq(moved.height, 4.0, 0.0001, "and arrived still four units up")
	assert_eq(moved.part.hp, 7, "with its damage, which is what a move means")


## `Grid.dup()` is the speculative-preview clone, so a preview attack that destroys cover must
## not touch the real part — and must not lose where the cover was standing either.
func test_a_previewed_clone_copies_the_placement_and_not_the_part() -> void:
	var grid: Grid = _map_with_blocker(
		MapPlacement.new(Vector2i(2, 2), MapPlacement.KIND_BLOCKER, WALL, 4.0)
	)

	var clone: Grid = grid.dup()
	clone.blocker_part_at(Vector2i(2, 2)).hp = 1

	assert_almost_eq(clone.blocker_at(Vector2i(2, 2)).height, 4.0, 0.0001, "the height came along")
	assert_ne(grid.blocker_part_at(Vector2i(2, 2)).hp, 1, "and the real part was left alone")
