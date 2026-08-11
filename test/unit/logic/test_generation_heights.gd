extends GutTest

## taskblock-63 Pass D — **the third fixed generation height, and what it exposed.**
##
## Generation offered 0 and +1. One level is a rise a stair crosses in three cells and a unit
## crosses in one turn, so ladders, lifts, partial climbs and one-way awareness had all shipped
## without ever being put against a rise that genuinely needs several turns. **+4 is that
## rise**, and adding it surfaced three things nothing had asked before:
##
## - **A ladder served ascent only.** A +4 shelf is too tall to climb bare and too tall to
##   drop, so the ground beside one was impassable in *both* directions — measured at 40x30 as
##   five seeds carrying regions of 65 to 286 cells, every one of them low ground ringed by a
##   rise of exactly 4.0.
## - **A wall stood from world zero whatever the ground did.** A floor at +4 sits above every
##   wall on the board, so a tall room's exterior read as a floor hanging over open space.
## - **`BR60.01`'s repair had nothing to repair with.** The detection landed at taskblock-61
##   and the repair did not; the route-standing half is Pass D1.
##
## The reachability invariant itself lives in `test_map_gen_reachability.gd`, which sweeps
## fifty seeds at the played board size. This file asserts the *content* — that the height
## exists, that it is reachable, and that the geometry around it is honest.

const SEED_COUNT := 30
const BOUT_WIDTH := BattleScene.GRID_WIDTH
const BOUT_HEIGHT := BattleScene.GRID_HEIGHT
## `wall.tres`'s own box, read rather than quoted in the assertions below.
const WALL_ID := &"wall"


func should_skip_script():
	return SuiteTier.skip_if_fast()


func _heights(grid: Grid) -> Dictionary:
	var seen: Dictionary = {}
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			var cell := Vector2i(x, y)
			if Surface.first_walkable(grid.surfaces_at(cell)) == null:
				continue
			seen[snappedf(UnitGeometry.true_height_for_cell(cell, grid), 0.01)] = true
	return seen


## **The height exists at all**, across a sweep rather than at a hand-picked seed — the share
## is a flagged placeholder, so pinning a seed would pin the placeholder rather than the
## feature.
func test_a_tall_shelf_is_generated_somewhere_in_a_seed_sweep() -> void:
	var tall_seeds: Array[int] = []
	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		if _heights(grid).has(float(MapGen.TALL_ROOM_LEVEL) * UnitGeometry.LEVEL_HEIGHT):
			tall_seeds.append(map_seed)

	gut.p(
		(
			"seeds carrying a +%d shelf: %d of %d — %s"
			% [MapGen.TALL_ROOM_LEVEL, tall_seeds.size(), SEED_COUNT, tall_seeds]
		)
	)
	assert_gt(tall_seeds.size(), 0, "the third height must actually appear on generated boards")


## And that it is **standable ground a unit can get to**, not scenery. The reachability sweep
## asserts the whole board; this asserts the interesting part of it by name, so a repair that
## satisfied the invariant by flattening every tall shelf would be caught here rather than
## reading as a clean sweep.
func test_every_generated_tall_shelf_is_reachable() -> void:
	var checked := 0
	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		var tall: float = float(MapGen.TALL_ROOM_LEVEL) * UnitGeometry.LEVEL_HEIGHT
		var reached: Dictionary = MapNavigability.reachable_from_spawns(grid)
		if reached.is_empty():
			continue
		for y: int in range(grid.rows):
			for x: int in range(grid.width):
				var cell := Vector2i(x, y)
				if Surface.first_walkable(grid.surfaces_at(cell)) == null:
					continue
				if not is_equal_approx(UnitGeometry.true_height_for_cell(cell, grid), tall):
					continue
				if grid.blockers.has(cell):
					continue
				checked += 1
				assert_true(
					reached.has(cell),
					"seed %d: tall shelf cell %s must be reachable from a spawn" % [map_seed, cell]
				)
	gut.p("tall-shelf cells checked across %d seeds: %d" % [SEED_COUNT, checked])
	assert_gt(checked, 0, "sanity: the sweep found tall ground to check at all")


## **`no wall is shorter than the floor beside it` — asserted on the geometry, not on the
## generator's intent.** The boxes are read back through the same `blocker_height_for_cell`
## the resolvers use, so this cannot pass because the generator meant well.
func test_no_generated_wall_is_shorter_than_the_floor_beside_it() -> void:
	var worst := 0.0
	var worst_at := Vector2i.ZERO
	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		for cell: Vector2i in grid.blockers:
			var record: Blocker = grid.blocker_at(cell)
			if record.part.id != WALL_ID:
				continue
			var top: float = (
				UnitGeometry.blocker_height_for_cell(cell, grid)
				+ PlacedVolume.natural_bounds(record.part).end.y
			)
			for offset: Vector2i in Grid.NEIGHBOR_OFFSETS:
				var neighbour: Vector2i = cell + offset
				if Surface.first_walkable(grid.surfaces_at(neighbour)) == null:
					continue
				var floor_height: float = UnitGeometry.true_height_for_cell(neighbour, grid)
				var shortfall: float = floor_height - top
				if shortfall > worst:
					worst = shortfall
					worst_at = cell
	gut.p("worst wall shortfall across %d seeds: %.3f at %s" % [SEED_COUNT, worst, worst_at])
	assert_lt(worst, 0.001, "a wall must reach at least as high as any floor it stands beside")


## **Both halves of the wall rule, measured over a sweep rather than sampled at a seed.**
##
## A wall spanning a level change must be rare — it is duplicated and rescaled, and every board
## before the third height had none, so a change that started sizing every wall would be a real
## cost paid for nothing. It must also **happen**, or the spanning branch is dead code that
## nobody would notice breaking. The first version of this test read one seed, which happened
## to carry no spanning wall at all and asserted "rare" against zero.
func test_spanning_a_level_change_is_the_exception_and_still_happens() -> void:
	var natural := 0
	var sized := 0
	var raised := 0
	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapCorpus.read(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		for cell: Vector2i in grid.blockers:
			var record: Blocker = grid.blocker_at(cell)
			if record.part.id != WALL_ID:
				continue
			if record.size.is_zero_approx():
				natural += 1
			else:
				sized += 1
			if record.height > 0.001:
				raised += 1

	(
		gut
		. p(
			(
				"walls over %d seeds: %d at their natural size, %d sized to span, %d standing above zero"
				% [SEED_COUNT, natural, sized, raised]
			)
		)
	)
	assert_gt(sized, 0, "the spanning branch must actually be reached by generated content")
	assert_gt(natural, sized * 5, "and it must stay the exception rather than the rule")
	assert_gt(raised, 0, "a wall standing on raised ground is the ordinary case of the record")


## **A ladder is a route in both directions.** The up branch has consulted
## `ladder_serves_climb` since taskblock-53; the down branch capped at `MAX_HOP_DOWN_LEVELS`
## and consulted nothing, which made a tall shelf impassable rather than merely hard to leave.
func test_a_ladder_carries_a_drop_too_tall_to_hop() -> void:
	var grid := GridFixture.flat(6, 3)
	for y: int in range(3):
		for x: int in range(1, 6):
			GridFixture.place_floor(grid, Vector2i(x, y), 4.0)
	var pathfinder := Pathfinder.new(grid)

	assert_almost_eq(
		pathfinder.move_cost(Vector2i(1, 1), Vector2i(0, 1)),
		-1.0,
		0.0001,
		"a four-level drop is not a hop, and with no ladder it is not an edge"
	)

	# tb64 Pass F: enough segments to span the four-level drop, sized from the constant rather
	# than hard-coded — `Surface.LADDER_SEGMENT_RISE` went 2.0 -> 1.0 and this fixture had the
	# old spacing baked in, which left the ladder reaching 3.0 of a 4.0 face.
	for step: int in range(int(4.0 / Surface.LADDER_SEGMENT_RISE)):
		GridPlacement.place(
			grid,
			Vector2i(0, 1),
			DataLibrary.get_part(&"ladder"),
			float(step) * Surface.LADDER_SEGMENT_RISE
		)

	gut.p(
		(
			"with a ladder at the foot: down %.1f, up %.1f"
			% [
				pathfinder.move_cost(Vector2i(1, 1), Vector2i(0, 1)),
				pathfinder.move_cost(Vector2i(0, 1), Vector2i(1, 1))
			]
		)
	)
	assert_gt(
		pathfinder.move_cost(Vector2i(1, 1), Vector2i(0, 1)),
		0.0,
		"the ladder you would climb down is at the destination, and it makes the drop a route"
	)


## An ordinary hop is untouched, which is every drop on every board before +4 existed.
func test_a_short_drop_still_costs_a_hop_and_needs_no_ladder() -> void:
	var grid := GridFixture.flat(6, 3)
	for y: int in range(3):
		for x: int in range(1, 6):
			GridFixture.place_floor(grid, Vector2i(x, y), 1.0)
	var pathfinder := Pathfinder.new(grid)

	assert_almost_eq(
		pathfinder.move_cost(Vector2i(1, 1), Vector2i(0, 1)),
		Pathfinder.HOP_DOWN_COST,
		0.0001,
		"a one-level drop is a hop and always was"
	)
