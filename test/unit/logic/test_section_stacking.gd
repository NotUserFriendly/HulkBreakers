extends GutTest

## taskblock-55 Pass D: **sections stack — intervals, and `up`/`down` edges.**
##
## An observation room on top of a staircase, a barracks at the bottom, and a second tall room
## refused because it needs space the staircase occupies.
##
## ## Intervals, and specifically not voxels
##
## taskblock-37 made height continuous on purpose and the collapse case reaffirmed it. A voxel
## grid quantizes to its resolution: 0.5 voxels cannot express a 0.3 step, and 0.1 voxels are
## twenty mostly-empty layers per cell. **An interval expresses any height exactly and costs one
## comparison**, which is why the awkward-height test below matters as much as the stacking ones.


func _floored(name: String, width: int, rows: int, height: float = 0.0) -> SectionFile:
	var section := SectionFile.new()
	section.section_name = name
	section.width = width
	section.rows = rows
	for y: int in range(rows):
		for x: int in range(width):
			section.placements.append(
				MapPlacement.new(Vector2i(x, y), MapPlacement.KIND_SURFACE, &"ship_floor", height)
			)
	return section


## A section with a wall reaching from its deck to `top` — something with real vertical extent,
## so an interval means something.
func _tall(name: String, height: float, top_of_wall: float) -> SectionFile:
	var section: SectionFile = _floored(name, 2, 2, height)
	section.claims = [
		SectionClaim.new(
			SectionClaim.KIND_INTERIOR,
			Box.new(
				Vector3(0.5, height + (top_of_wall - height) * 0.5, 0.5),
				Vector3(2.0, top_of_wall - height, 2.0)
			)
		)
	]
	return section


func _stackable(section: SectionFile, side: StringName, tag: StringName, at: float) -> SectionFile:
	section.edges = [SectionEdge.new(side, SectionEdge.KIND_OPEN, tag, [] as Array[int], at)]
	return section


# --- intervals -----------------------------------------------------------------------------


## **Two sections with disjoint intervals share a cell.** The whole point: a staircase occupying
## 0..3 and an observation room occupying 3..6 are both over the same footprint and neither is in
## the other's way.
func test_two_sections_with_disjoint_intervals_share_a_cell() -> void:
	var lower: SectionFile = _tall("Stairwell", 0.0, 3.0)
	# **Placed at 3.2, not 3.0**, because a deck is a real part with real thickness: `ship_floor`
	# is a 0.2 slab hung *below* the height it is placed at, so a deck whose walkable top is 3.2
	# has its underside resting exactly on the stairwell's 3.0 ceiling. Placing it at 3.0 would
	# push that underside down to 2.8 and genuinely overlap the room below.
	#
	# That the thickness participates at all is the interval model paying for itself: a voxel grid
	# at any usable resolution could not express a 0.2 deck, let alone tell these two cases apart.
	var upper: SectionFile = _tall("Observation Deck", 3.2, 6.0)

	var problems: Array[String] = ClaimResolver.describe_interval_overlap(lower, 0.0, upper, 0.0)
	gut.p(
		"lower %s, upper %s" % [ClaimResolver.interval_of(lower), ClaimResolver.interval_of(upper)]
	)
	assert_eq(problems, [] as Array[String], "disjoint intervals may share every cell they like")


## **Overlapping intervals are refused, and both intervals are named.** A second tall room needs
## space the staircase occupies, and the refusal has to say which space or nobody can fix it.
func test_overlapping_intervals_are_refused_with_both_named() -> void:
	var lower: SectionFile = _tall("Stairwell", 0.0, 3.0)
	var overlapping: SectionFile = _tall("Second Tall Room", 2.0, 5.0)

	var problems: Array[String] = ClaimResolver.describe_interval_overlap(
		lower, 0.0, overlapping, 0.0
	)
	gut.p("\n".join(problems))
	assert_gt(problems.size(), 0, "a room needing occupied space is refused")
	if problems.is_empty():
		return
	assert_true(problems[0].contains("Stairwell"), "the reason names the first section")
	assert_true(problems[0].contains("Second Tall Room"), "and the second")
	# The intervals are read back off the sections rather than written as literals, so the
	# assertion cannot quietly stop describing what the code actually computed.
	var lower_interval: Vector2 = ClaimResolver.interval_of(lower)
	var upper_interval: Vector2 = ClaimResolver.interval_of(overlapping)
	assert_true(
		problems[0].contains("%.2f..%.2f" % [lower_interval.x, lower_interval.y]),
		"and the first interval, exactly as measured"
	)
	assert_true(
		problems[0].contains("%.2f..%.2f" % [upper_interval.x, upper_interval.y]), "and the second"
	)


## **A merge volume is exactly where vertical overlap is legal**, and the stacking check has to
## know it. Without this exception **every adjacent pair of rooms is refused**, because two rooms
## sharing a wall overlap by precisely that wall — so this is not a corner case, it is the common
## one.
func test_a_merge_volume_permits_the_overlap_that_would_otherwise_refuse() -> void:
	var lower: SectionFile = _tall("Barracks", 0.0, 3.0)
	var overlapping: SectionFile = _tall("Armoury", 2.0, 5.0)
	assert_gt(
		ClaimResolver.describe_interval_overlap(lower, 0.0, overlapping, 0.0).size(),
		0,
		"sanity: without a merge volume these refuse"
	)

	overlapping.claims.append(
		SectionClaim.new(
			SectionClaim.KIND_MERGE, Box.new(Vector3(0.5, 2.5, 0.5), Vector3(2.0, 1.0, 2.0))
		)
	)
	assert_eq(
		ClaimResolver.describe_interval_overlap(lower, 0.0, overlapping, 0.0),
		[] as Array[String],
		"a merge volume over the shared band is what makes the shared band legal"
	)


## **Intervals keep height continuous.** The pass that could quietly introduce quantization is
## this one — a stacking rule is exactly where somebody reaches for a storey index — so a spread
## of awkward heights is pinned rather than assumed.
func test_an_interval_is_never_quantized() -> void:
	for height: float in [0.3, 1.25, 2.4, 3.33]:
		var section: SectionFile = _tall("Odd", height, height + 0.7)
		var interval: Vector2 = ClaimResolver.interval_of(section)
		gut.p("placed at %.2f, interval reads %.2f..%.2f" % [height, interval.x, interval.y])
		assert_almost_eq(interval.y, height + 0.7, 0.0001, "the top survives exactly as authored")


# --- up/down are data ----------------------------------------------------------------------


## `up` and `down` are ordinary sides. Their opposites resolve like any other pair, which is what
## lets every existing rule read them without a special case.
func test_up_and_down_are_opposites_like_any_other_pair() -> void:
	assert_eq(SectionEdge.opposite(SectionEdge.SIDE_UP), SectionEdge.SIDE_DOWN)
	assert_eq(SectionEdge.opposite(SectionEdge.SIDE_DOWN), SectionEdge.SIDE_UP)


## **A section joins another through its `up` edge**, and the board that comes out holds both.
func test_a_section_joins_another_through_its_up_edge() -> void:
	var lower: SectionFile = _stackable(
		_tall("Stairwell", 0.0, 3.0), SectionEdge.SIDE_UP, &"shaft", 0.0
	)
	var upper: SectionFile = _stackable(
		_tall("Observation Deck", 0.0, 2.0), SectionEdge.SIDE_DOWN, &"shaft", 0.0
	)

	var verdict: Dictionary = SectionSerializer.can_join(lower, SectionEdge.SIDE_UP, upper)
	gut.p("verdict: %s" % str(verdict))
	assert_true(verdict.ok, "the two stack: %s" % verdict.reason)

	var result: Dictionary = SectionSerializer.stitch(lower, SectionEdge.SIDE_UP, upper)
	assert_eq(result.get("error", ""), "", "and the stacked board builds")
	var grid: Grid = result.get("grid")
	assert_not_null(grid, "there is a board")
	if grid == null:
		return

	# **The upper section's deck is lifted onto the lower one's ceiling**, which is the only
	# arithmetic stacking needs — the format already carried both vertical extents.
	var heights: Array[float] = []
	for surface: Surface in grid.surfaces_at(Vector2i(0, 0)):
		heights.append(surface.height)
	heights.sort()
	gut.p("cell (0,0) holds decks at %s" % str(heights))
	assert_eq(heights.size(), 2, "one cell, two decks -- the sections share it")
	assert_almost_eq(heights[0], 0.0, 0.0001, "the lower deck stays where it was")

	# **3.2, not 3.0 — and that is the whole point of an interval.** The lower section's ceiling is
	# at 3.0. `ship_floor` is a 0.2-thick slab hung *below* its placed height, so a deck resting
	# its underside on that ceiling has its walkable top at 3.2. The lift is computed from the two
	# sections' real extents, so the deck's own thickness is accounted for rather than assumed
	# away — which is precisely what a quantized model could not do.
	var deck: float = DataLibrary.get_part(&"ship_floor").volume[0].size.y
	assert_almost_eq(
		heights[1], 3.0 + deck, 0.0001, "the upper deck rests its underside on the lower's ceiling"
	)


## **A footprint mismatch refuses a stack.** Two sections meeting vertically meet over their whole
## footprint, so a 6x4 must not stack on a 2x4 merely because both are four rows deep.
func test_a_footprint_mismatch_refuses_a_vertical_join() -> void:
	var lower: SectionFile = _stackable(
		_floored("Wide Deck", 6, 4), SectionEdge.SIDE_UP, &"shaft", 0.0
	)
	var upper: SectionFile = _stackable(
		_floored("Narrow Deck", 2, 4), SectionEdge.SIDE_DOWN, &"shaft", 0.0
	)

	var verdict: Dictionary = SectionSerializer.can_join(lower, SectionEdge.SIDE_UP, upper)
	gut.p("verdict: %s" % str(verdict))
	assert_false(verdict.ok, "four rows deep is not the same as the same footprint")


# --- an entry has a height -----------------------------------------------------------------


## **An entry at height 3 does not match an entry at height 0.** A door at ground level and a door
## at the top of a staircase are different joins, and every other field on an edge would call them
## the same one.
func test_an_entry_at_height_3_does_not_match_one_at_height_0() -> void:
	var ground: SectionFile = _stackable(
		_floored("Ground Hall", 4, 4), SectionEdge.SIDE_EAST, &"door", 0.0
	)
	var landing: SectionFile = _stackable(
		_floored("Stair Landing", 4, 4), SectionEdge.SIDE_WEST, &"door", 3.0
	)

	var verdict: Dictionary = SectionSerializer.can_join(ground, SectionEdge.SIDE_EAST, landing)
	gut.p("verdict: %s" % str(verdict))
	assert_false(verdict.ok, "same tag, same span, different storey -- not a join")
	assert_true(verdict.reason.contains("0.00"), "the reason names the first height")
	assert_true(verdict.reason.contains("3.00"), "and the second")


## The foil: the same two edges at the same height do join. Without it the test above would also
## pass against code that had simply started refusing everything.
func test_two_entries_at_the_same_height_still_join() -> void:
	var ground: SectionFile = _stackable(
		_floored("Ground Hall", 4, 4), SectionEdge.SIDE_EAST, &"door", 3.0
	)
	var landing: SectionFile = _stackable(
		_floored("Stair Landing", 4, 4), SectionEdge.SIDE_WEST, &"door", 3.0
	)

	var verdict: Dictionary = SectionSerializer.can_join(ground, SectionEdge.SIDE_EAST, landing)
	assert_true(verdict.ok, "matching heights join: %s" % verdict.reason)


## **`can_join` still reads both edges with neither as host** — taskblock-54's finding, and it
## holds vertically too. `a` willing and `b` not is a refusal, exactly as `b` willing and `a` not
## is; a part attaches *to* a host, but two sections are peers.
func test_can_join_reads_both_edges_vertically_with_neither_as_host() -> void:
	var willing: SectionFile = _stackable(
		_floored("Willing", 2, 2), SectionEdge.SIDE_UP, &"shaft", 0.0
	)
	var sealed: SectionFile = _floored("Sealed Underside", 2, 2)
	sealed.edges = [SectionEdge.new(SectionEdge.SIDE_DOWN, SectionEdge.KIND_EXTERIOR)]

	var upward: Dictionary = SectionSerializer.can_join(willing, SectionEdge.SIDE_UP, sealed)
	assert_false(upward.ok, "the willing section cannot force a join on a sealed underside")
	assert_true(upward.reason.contains("Sealed Underside"), "and the refusal names the refuser")

	# And the mirror: the refusal does not depend on which section was asked first.
	var downward: Dictionary = SectionSerializer.can_join(sealed, SectionEdge.SIDE_DOWN, willing)
	assert_false(downward.ok, "neither is the host, so the answer is the same either way")
