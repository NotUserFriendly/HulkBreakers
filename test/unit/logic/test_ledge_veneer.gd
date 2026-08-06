extends GutTest

## taskblock-58 Pass F: **the ledge veneer** — a flat wall hung off a tile's edge, sized by what it
## reaches rather than by an authored height.
##
## The three cases the taskblock names are one rule: take whichever ends exist, default the ones
## that do not.


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## **THE PASS'S OWN LINE**: a veneer between two floors snaps to both.
func test_a_veneer_between_two_floors_snaps_to_both() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	GridFixture.place_floor(grid, Vector2i(2, 2), 0.0)
	grid.add_surface(Vector2i(2, 2), Surface.new(DataLibrary.get_part(&"ship_floor"), 3.0))

	var span: Dictionary = LedgeVeneer.span_at(grid, Vector2i(2, 2), 0.0, true)
	gut.p(
		(
			"  between 0.0 and 3.0 -> %.2f to %.2f (%.2f tall)"
			% [span["bottom"], span["top"], span["height"]]
		)
	)

	assert_almost_eq(float(span["bottom"]), 0.0, 0.0001, "it reaches down to the lower deck")
	assert_almost_eq(float(span["top"]), 3.0, 0.0001, "and up to the one above")
	assert_almost_eq(float(span["height"]), 3.0, 0.0001, "so it is exactly the gap — no seam")


## **THE PASS'S OWN LINE**: a veneer with nothing above it is 0.8.
##
## Deliberately odd, so it reads as a default rather than as intent — a veneer that came up at 1.0
## would be indistinguishable from one an author sized to a level.
func test_a_veneer_with_nothing_above_it_takes_the_odd_default() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	GridFixture.place_floor(grid, Vector2i(1, 1), 2.0)

	var span: Dictionary = LedgeVeneer.span_at(grid, Vector2i(1, 1), 2.0, true)

	assert_almost_eq(float(span["height"]), LedgeVeneer.UNANCHORED_RISE, 0.0001)
	assert_almost_eq(float(span["height"]), 0.8, 0.0001, "and the number is the stated one")
	assert_ne(
		LedgeVeneer.UNANCHORED_RISE,
		UnitGeometry.LEVEL_HEIGHT,
		"a whole level would pass for a decision rather than reading as a default"
	)


## **THE PASS'S OWN LINE**: a veneer on a tile with nothing under it matches that tile's height.
func test_a_veneer_with_nothing_under_it_matches_the_tile_it_hangs_from() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	grid.clear_surfaces(Vector2i(4, 4))
	grid.add_surface(Vector2i(4, 4), Surface.new(DataLibrary.get_part(&"ship_floor"), 2.5))

	# Clicking the side of that tile: it grows DOWN, and there is nothing below to stop at.
	var span: Dictionary = LedgeVeneer.span_at(grid, Vector2i(4, 4), 2.5, false)

	assert_almost_eq(
		float(span["height"]), 2.5, 0.0001, "it falls to the deck, matching the tile's own height"
	)
	assert_almost_eq(float(span["bottom"]), 0.0, 0.0001)


## Both ends absent is the ordinary case — an author clicking a lone platform's edge.
func test_an_unanchored_veneer_grows_up_by_the_default() -> void:
	var span: Dictionary = LedgeVeneer.span_up(1.0, null)

	assert_almost_eq(float(span["bottom"]), 1.0, 0.0001, "it starts at the tile it hangs from")
	assert_almost_eq(float(span["top"]), 1.0 + LedgeVeneer.UNANCHORED_RISE, 0.0001)


## **"Snaps to both" is not a third case.** A veneer grown up from the lower deck and one grown down
## from the upper one describe the same wall, because each direction snapped to what it found.
func test_snapping_is_the_same_wall_whichever_direction_it_was_grown() -> void:
	var upward: Dictionary = LedgeVeneer.span_up(0.0, 3.0)
	var downward: Dictionary = LedgeVeneer.span_down(3.0, 0.0)

	assert_almost_eq(float(upward["height"]), float(downward["height"]), 0.0001)
	assert_almost_eq(float(upward["bottom"]), float(downward["bottom"]), 0.0001)
	assert_almost_eq(float(upward["top"]), float(downward["top"]), 0.0001)


## The board answers both ends, so the nearest surface each way is what it snaps to — not the
## furthest, which would have a veneer reach past a deck it should have stopped at.
func test_it_snaps_to_the_nearest_surface_each_way() -> void:
	var grid: Grid = GridFixture.flat(6, 6)
	GridFixture.place_floor(grid, Vector2i(3, 3), 0.0)
	for height: float in [2.0, 5.0]:
		grid.add_surface(Vector2i(3, 3), Surface.new(DataLibrary.get_part(&"ship_floor"), height))

	assert_almost_eq(
		float(LedgeVeneer.surface_above(grid, Vector2i(3, 3), 0.0)),
		2.0,
		0.0001,
		"the nearest above, not the highest"
	)
	assert_almost_eq(
		float(LedgeVeneer.surface_below(grid, Vector2i(3, 3), 5.0)),
		2.0,
		0.0001,
		"and the nearest below, not the lowest"
	)


## **HP by volume, like everything else in this pass.** A tall deck face is genuinely tougher than a
## low kerb without either being authored — which is the whole reason the veneer's height is a
## derived number rather than a field.
func test_a_taller_veneer_is_tougher_in_proportion() -> void:
	var part: Part = DataLibrary.get_part(&"ledge_veneer")
	assert_not_null(part, "the veneer part is authored")
	assert_gt(part.hp_per_volume, 0.0, "and opted into volume-scaled hp")

	var short: Vector3 = LedgeVeneer.size_for(part, LedgeVeneer.span_up(0.0, null))
	var tall: Vector3 = LedgeVeneer.size_for(part, LedgeVeneer.span_up(0.0, 3.2))

	var short_hp: int = PlacedVolume.hp_for(part, short)
	var tall_hp: int = PlacedVolume.hp_for(part, tall)
	gut.p("  %.1f tall -> %d hp; %.1f tall -> %d hp" % [short.y, short_hp, tall.y, tall_hp])

	assert_almost_eq(short.y, LedgeVeneer.UNANCHORED_RISE, 0.0001)
	assert_almost_eq(tall.y, 3.2, 0.0001)
	assert_eq(tall_hp, short_hp * 4, "3.2 is four times 0.8, and hp is linear in volume")


## Only the rise is a question about the board. A veneer is as wide and as thick as its part says.
func test_only_the_rise_is_derived() -> void:
	var part: Part = DataLibrary.get_part(&"ledge_veneer")
	var natural: Vector3 = PlacedVolume.natural_size(part)

	var sized: Vector3 = LedgeVeneer.size_for(part, LedgeVeneer.span_up(0.0, 2.0))

	assert_almost_eq(sized.x, natural.x, 0.0001, "its width is the part's")
	assert_almost_eq(sized.z, natural.z, 0.0001, "and so is its thickness")
	assert_almost_eq(sized.y, 2.0, 0.0001, "only the rise came from the board")
