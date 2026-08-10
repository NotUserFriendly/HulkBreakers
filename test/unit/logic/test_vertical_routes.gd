extends GutTest

## taskblock-63 Pass E — **the three routes up are told apart, and no cell claims two of
## them.** Both entries here came from the supervisor's first play of taskblock-62's work.
##
## - **`BR62.03`** — a ladder and a mag lift pad generated in the same cell. tb62 had already
##   fixed the neighbouring case (pads cross-linking into chains) by refusing to build a lift
##   within one cell of an existing pad, and that refusal knew about *pads* and nothing else,
##   exactly as the report guessed.
## - **`BR62.04`** — ladders drew in the floor's own green, so a route up read as more floor.
##   The ladder did not pick that colour; it **inherited** it, because the tile tint answers
##   for every placed surface and a ladder is one.
##
## **Steps are deliberately not colour-coded with the other two**, and that is stated here
## because it looks like an omission. A step is `ship_floor` at a fractional height — it *is*
## floor, and what makes it a route is geometry that is already visible. Tinting it would
## need the generator to mark which tiles are treads, and a tile that reads as not-floor
## because of how it was built is a worse lie than one that reads as floor because it is.

const SEED_COUNT := 40
const BOUT_WIDTH := BattleScene.GRID_WIDTH
const BOUT_HEIGHT := BattleScene.GRID_HEIGHT


func should_skip_script():
	return SuiteTier.skip_if_fast()


## **`BR62.03`, on generated boards rather than on a constructed case.** The defect was found
## in play, so the sweep is what has to be clean.
func test_no_generated_cell_holds_both_a_ladder_and_a_lift_pad() -> void:
	var doubled: Array[String] = []
	var ladders := 0
	var pads := 0
	for map_seed: int in range(SEED_COUNT):
		var grid: Grid = MapGen.generate(map_seed, BOUT_WIDTH, BOUT_HEIGHT)
		for y: int in range(grid.rows):
			for x: int in range(grid.width):
				var cell := Vector2i(x, y)
				var has_ladder: bool = Surface.has_ladder_at(grid, cell)
				var has_pad: bool = Surface.has_mag_lift_at(grid, cell)
				if has_ladder:
					ladders += 1
				if has_pad:
					pads += 1
				if has_ladder and has_pad:
					doubled.append("seed %d %s" % [map_seed, cell])

	gut.p("over %d seeds: %d laddered cells, %d pad cells" % [SEED_COUNT, ladders, pads])
	assert_gt(ladders, 0, "sanity: the sweep generated ladders to check")
	assert_gt(pads, 0, "sanity: and lifts")
	assert_eq(
		doubled,
		[] as Array[String],
		"a cell carries one route up, not two: %s" % ", ".join(doubled.slice(0, 8))
	)


## The direct case in both directions, because the sweep above passing could equally mean the
## generator stopped producing one of the two fixtures.
func test_neither_stamper_will_build_over_the_other() -> void:
	var grid := GridFixture.flat(6, 3)
	for y: int in range(3):
		for x: int in range(1, 6):
			GridFixture.place_floor(grid, Vector2i(x, y), 2.0)

	GridPlacement.place(grid, Vector2i(0, 1), DataLibrary.get_part(&"ladder"), 0.0)
	assert_true(Surface.has_vertical_route_at(grid, Vector2i(0, 1)), "the ladder stands")
	assert_false(
		GridPlacement.place_mag_lift_pair(grid, Vector2i(0, 1), 0.0, Vector2i(1, 1), 2.0),
		"a lift must refuse a cell that already carries a route up"
	)

	var second := GridFixture.flat(6, 3)
	for y: int in range(3):
		for x: int in range(1, 6):
			GridFixture.place_floor(second, Vector2i(x, y), 2.0)
	assert_true(
		GridPlacement.place_mag_lift_pair(second, Vector2i(0, 1), 0.0, Vector2i(1, 1), 2.0),
		"sanity: the same lift places fine on a clear cell"
	)
	assert_true(Surface.has_vertical_route_at(second, Vector2i(0, 1)), "and reads as a route")


## **A lift's two ends are a paired placement rather than two independent ones.** The pairing
## used to be *inferred* — `mag_lift_destination` swept the neighbours for a pad at a
## different height and took the closest — which is where taskblock-62's cross-linked chains
## came from: three pads near each other have several defensible answers.
func test_a_lifts_two_pads_record_each_other_rather_than_being_matched_by_proximity() -> void:
	var grid := GridFixture.flat(8, 4)
	for y: int in range(4):
		for x: int in range(2, 8):
			GridFixture.place_floor(grid, Vector2i(x, y), 2.0)

	assert_true(GridPlacement.place_mag_lift_pair(grid, Vector2i(1, 1), 0.0, Vector2i(2, 1), 2.0))

	assert_eq(
		Surface.mag_lift_destination(grid, Vector2i(1, 1)),
		Vector2i(2, 1),
		"the lower pad names its partner"
	)
	assert_eq(
		Surface.mag_lift_destination(grid, Vector2i(2, 1)),
		Vector2i(1, 1),
		"and the upper pad names it back, so either end can be boarded"
	)


## **The anti-inference half.** A third pad standing beside the pair must not become anybody's
## partner — under the old proximity rule it was a live candidate and the tie-break decided.
func test_a_third_pad_nearby_cannot_capture_an_existing_pair() -> void:
	var grid := GridFixture.flat(8, 4)
	for y: int in range(4):
		for x: int in range(2, 8):
			GridFixture.place_floor(grid, Vector2i(x, y), 2.0)

	assert_true(GridPlacement.place_mag_lift_pair(grid, Vector2i(1, 1), 0.0, Vector2i(2, 1), 2.0))
	# Placed directly rather than through the pair constructor — the point is that a stray pad
	# existing at all cannot change what the pair says, however it got there.
	GridPlacement.place(grid, Vector2i(2, 2), DataLibrary.get_part(&"mag_lift_pad"), 2.0)

	assert_eq(
		Surface.mag_lift_destination(grid, Vector2i(1, 1)),
		Vector2i(2, 1),
		"the pair is unchanged by a stranger standing next to it"
	)
	assert_null(
		Surface.mag_lift_destination(grid, Vector2i(2, 2)),
		"and the stranger has no partner, which is the honest answer rather than a guess"
	)


## **`BR62.04`: the vertical routes are distinct from the floor and from each other.** The
## colours themselves are placeholders; what is asserted is the separation, which is the
## actual requirement — *"a route up must not read as more floor"*.
func test_the_vertical_route_colours_are_distinct_from_the_floor_and_from_each_other() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var floor_color: Color = WorldPalette.surface_color(table, DataLibrary.get_part(&"ship_floor"))
	var ladder_color: Color = WorldPalette.surface_color(table, DataLibrary.get_part(&"ladder"))
	var lift_color: Color = BoardOverlays.COLOR

	var pairs: Array = [
		["ladder against floor", ladder_color, floor_color],
		["lift against floor", lift_color, floor_color],
		["ladder against lift", ladder_color, lift_color],
		["ladder against team A", ladder_color, WorldPalette.TEAM_A],
		["lift against team A", lift_color, WorldPalette.TEAM_A],
	]
	for pair: Array in pairs:
		var a: Color = pair[1]
		var b: Color = pair[2]
		var separation: float = absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		gut.p("%s: separation %.2f" % [pair[0], separation])
		# 0.4 rather than 0.3, and the bar moved because the first ladder tint cleared 0.3 by
		# 0.01 against team blue — a threshold a value can pass while still reading as the
		# same colour is a threshold that is not doing anything.
		assert_gt(separation, 0.4, "%s must be tellable apart at a glance" % pair[0])


## And that a ladder actually gets the route colour rather than the floor's, through the call
## `BoardView` makes. Asserted against the tint the floor gets from the same function, so it
## cannot pass by both being wrong.
func test_a_ladder_does_not_inherit_the_floor_tint() -> void:
	var table: MaterialTable = DataLibrary.material_table()

	assert_ne(
		WorldPalette.surface_color(table, DataLibrary.get_part(&"ladder")),
		WorldPalette.surface_color(table, DataLibrary.get_part(&"ship_floor")),
		"a ladder and the floor it climbs must not draw the same"
	)
	assert_eq(
		WorldPalette.surface_color(table, DataLibrary.get_part(&"ship_floor")),
		WorldPalette.tile_color(table, DataLibrary.get_part(&"ship_floor").material),
		"and an ordinary tile is unchanged by the split"
	)
