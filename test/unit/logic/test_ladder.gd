extends GutTest

## taskblock-53 Pass C: the ladder, and the first real use of the placement grammar.
##
## ## C1's finding, recorded as a test rather than as prose
##
## taskblock-38 built the attachment grammar and said *"build and test the rule now so the
## model is proven, otherwise the first catwalk discovers the grammar doesn't hold."* The
## first catwalk is this ladder, and **the grammar did not hold**, for a reason nothing had
## reason to notice: no shipped surface part authored a single `Socket`. `_find_attach_point`
## scans neighbours for a free matching socket, so with zero sockets anywhere on the board it
## could never succeed — every side attachment was structurally impossible and the only
## recorded behaviour of the grammar was it *refusing* things.
##
## Two changes made it hold, both small: `ship_floor` authors four directional `LEDGE`
## sockets, and the grammar searches the placed cell itself as well as its neighbours so
## segments can stack. `test_a_floor_authored_no_sockets_before_this_block` pins the first so
## it cannot silently regress to unusable.

const LADDER := &"ladder"
const FLOOR := &"ship_floor"


func _grid_with_step(lower_height: float, upper_height: float) -> Grid:
	# Two cells side by side: (0,0) low, (1,0) high. The face between them is the thing a
	# ladder spans.
	var grid := Grid.new(4, 3)
	grid.add_surface(Vector2i(0, 0), Surface.new(DataLibrary.get_part(FLOOR), lower_height))
	grid.add_surface(Vector2i(1, 0), Surface.new(DataLibrary.get_part(FLOOR), upper_height))
	return grid


# --- the grammar ---------------------------------------------------------------------


## The C1 finding, pinned. If this ever reads zero again, every side attachment on the board
## is impossible again and the failure is silent — placements just stop happening.
func test_a_floor_authors_ledge_sockets_for_anything_to_attach_to() -> void:
	var floor_part: Part = DataLibrary.get_part(FLOOR)
	var ledges := 0
	for socket: Socket in floor_part.sockets:
		if socket.socket_type == &"LEDGE":
			ledges += 1
	gut.p("ship_floor authors %d LEDGE sockets" % ledges)
	assert_eq(ledges, 4, "one per edge, so a platform cell can host a ladder on any side")


func test_a_ladder_side_attaches_to_a_raised_surface() -> void:
	var grid: Grid = _grid_with_step(0.0, 1.0)
	var placed: Surface = GridPlacement.place(
		grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0
	)
	assert_not_null(placed, "the grammar accepts a ladder against a raised neighbour")
	if placed == null:
		return
	assert_eq(placed.part.id, LADDER)
	assert_true(Surface.has_ladder_at(grid, Vector2i(0, 0)), "and the cell reports a ladder")


## **A ladder with nothing to attach to is rejected**, which is the half of the grammar that
## makes it a grammar rather than free placement.
func test_a_ladder_with_no_surface_to_attach_to_is_rejected() -> void:
	var grid := Grid.new(4, 3)
	assert_null(
		GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0),
		"a ladder in open space attaches to nothing"
	)
	assert_false(Surface.has_ladder_at(grid, Vector2i(0, 0)))


## **Tileable to arbitrary height**, and the whole rule is that the same cell is searched.
func test_three_stacked_segments_span_three_levels() -> void:
	# tb64 Pass F: **the numbers and the name agree now.** `LEVEL_HEIGHT` is 1.0, so this asserted
	# a reach of 6.0 while calling it "three levels" — it was counting in 2.0 segments. With
	# `LADDER_SEGMENT_RISE` at 1.0 the three segments span three levels literally.
	var grid: Grid = _grid_with_step(0.0, 3.0)
	var heights: Array[float] = [0.0, 1.0, 2.0]
	for height: float in heights:
		var segment: Surface = GridPlacement.place(
			grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), height
		)
		assert_not_null(segment, "segment at %.1f attaches" % height)
	var ladders := 0
	for surface: Surface in grid.surfaces_at(Vector2i(0, 0)):
		if Surface.LADDER_TAG in surface.part.tags:
			ladders += 1
	assert_eq(ladders, 3, "three segments stand at one cell, above the floor already there")
	assert_almost_eq(
		Surface.ladder_reach_at(grid, Vector2i(0, 0)),
		3.0,
		0.001,
		"three segments reach three levels"
	)


## **The socket taken is the one physically faced.** Four `LEDGE` sockets exist so a platform
## can be laddered on any side; taking an arbitrary one would make the transforms decorative.
func test_the_socket_taken_is_the_one_on_the_side_the_ladder_stands() -> void:
	var grid: Grid = _grid_with_step(0.0, 1.0)
	var host: Part = grid.surfaces_at(Vector2i(1, 0))[0].part
	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)

	var occupied: Array[StringName] = []
	for socket: Socket in host.sockets:
		if socket.occupant != null:
			occupied.append(socket.id)
	gut.p("occupied host sockets: %s" % str(occupied))
	assert_eq(occupied.size(), 1, "exactly one socket is taken")
	# The ladder sits at x=0 and the host at x=1, so the ladder is on the host's WEST side.
	assert_eq(occupied[0], &"LEDGE_W", "and it is the west edge, the one the ladder is against")


# --- climbing ------------------------------------------------------------------------


func _climber(cell: Vector2i, grid: Grid) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.8, 1.0, 0.6))]
	var unit := Unit.new(Matrix.new(), Shell.new(torso), cell, 0)
	unit.height = UnitGeometry.true_height_for_cell(cell, grid)
	return unit


## **The block's governing decision, tested directly:** a map must be navigable by a unit with
## no climbing capability, so a ladder is what a plain shell uses.
func test_a_unit_with_no_climbing_capability_climbs_a_ladder() -> void:
	var grid: Grid = _grid_with_step(0.0, 1.0)
	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	var unit: Unit = _climber(Vector2i(0, 0), grid)
	assert_false(unit.shell.can_climb(), "sanity: this shell cannot climb a bare face")

	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)
	assert_true(
		MoveAction.new(unit, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i]).is_legal(state),
		"a ladder makes the climb legal for a shell that could not otherwise"
	)


func test_the_same_unit_cannot_climb_a_bare_face() -> void:
	var grid: Grid = _grid_with_step(0.0, 1.0)
	var unit: Unit = _climber(Vector2i(0, 0), grid)
	var state := CombatState.new(grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)
	assert_false(
		MoveAction.new(unit, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i]).is_legal(state),
		"without a ladder the same climb is illegal — the ladder is what changed"
	)


## **A ladder replaces the rise cap with its own reach.** A two-level rise is beyond
## `MAX_CLIMB_LEVELS` for any shell; a two-segment ladder serves it, and one segment does not.
func test_a_ladders_reach_is_what_bounds_the_climb_not_the_bare_face_cap() -> void:
	var short_grid: Grid = _grid_with_step(0.0, 3.0)
	GridPlacement.place(short_grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	assert_false(
		Surface.ladder_serves_climb(short_grid, Vector2i(0, 0), Vector2i(1, 0)),
		"one segment does not reach a two-level ledge"
	)

	var tall_grid: Grid = _grid_with_step(0.0, 3.0)
	GridPlacement.place(tall_grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	GridPlacement.place(tall_grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 2.0)
	assert_true(
		Surface.ladder_serves_climb(tall_grid, Vector2i(0, 0), Vector2i(1, 0)), "two segments do"
	)

	var unit: Unit = _climber(Vector2i(0, 0), tall_grid)
	var state := CombatState.new(tall_grid, [unit])
	state.assign_all_to_human()
	state.force_current_unit(unit.id)
	assert_true(
		MoveAction.new(unit, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i]).is_legal(state),
		"and the step agrees with the reach, not with MAX_CLIMB_LEVELS"
	)


# --- pathing -------------------------------------------------------------------------


## **One term in `move_cost`**, and the planner's idea of a legal edge must match the action's.
func test_move_cost_opens_a_ladder_edge_for_a_non_climber() -> void:
	var grid: Grid = _grid_with_step(0.0, 1.0)
	var bare := Pathfinder.new(grid)
	assert_lt(
		bare.move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		0.0,
		"sanity: a non-climber cannot cross a bare 2-high face"
	)

	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	var laddered := Pathfinder.new(grid)
	var cost: float = laddered.move_cost(Vector2i(0, 0), Vector2i(1, 0))
	gut.p("ladder edge costs %.1f" % cost)
	assert_gt(cost, 0.0, "with a ladder the edge exists")


## **A stair step is cheaper than a ladder**, which is the taskblock's own stated ordering
## and the reason the ladder carries a cost scale at all.
##
## tb60 Pass A: this used to compare a *ramp* edge against a ladder edge, and a ramp edge no
## longer exists as a thing with its own cost — the comparison had to move to what actually
## replaced it. The ordering being asserted is unchanged and is the same design claim:
## **a ladder is direct but exposed; the graded route is indirect but cheap.** What changed is
## that the graded route is now ordinary geometry rather than a tagged cell, so the "cheap"
## half is `DEFAULT_COST` on a short rise instead of `DEFAULT_COST` on a labelled one.
func test_move_cost_prefers_a_stair_step_over_a_ladder() -> void:
	var stair_grid: Grid = _grid_with_step(0.0, Unit.BASE_STEP_HEIGHT)
	var stair_cost: float = Pathfinder.new(stair_grid).move_cost(Vector2i(0, 0), Vector2i(1, 0))

	var ladder_grid: Grid = _grid_with_step(0.0, 1.0)
	GridPlacement.place(ladder_grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	var ladder_cost: float = Pathfinder.new(ladder_grid).move_cost(Vector2i(0, 0), Vector2i(1, 0))

	gut.p("stair step %.1f against ladder %.1f" % [stair_cost, ladder_cost])
	assert_gt(stair_cost, 0.0, "sanity: the stair edge exists")
	assert_lt(stair_cost, ladder_cost, "a stair step is the cheaper way up")


# --- it is a part, therefore shootable ------------------------------------------------


## C3: "Destructible on purpose. `is_destructible` became real in taskblock-52; a ladder does
## not use it. Cutting a ladder to cut a route is exactly the tactical texture
## stranding-as-outcome is meant to enable."
func test_a_ladder_is_destructible_unlike_the_floor_it_hangs_from() -> void:
	var ladder: Part = DataLibrary.get_part(LADDER)
	var floor_part: Part = DataLibrary.get_part(FLOOR)
	assert_true(ladder.is_destructible, "a ladder can be cut")
	assert_false(floor_part.is_destructible, "the deck it hangs from cannot")
	assert_gt(ladder.hp, 0, "and it has hit points to lose")
	assert_gt(ladder.volume.size(), 0, "and real geometry to be shot at")


## **Cutting the ladder cuts the route** — the whole point of it being a part. Asserted
## through `move_cost` rather than by inspecting the grid, because the route is what matters.
func test_removing_a_ladder_closes_the_route_again() -> void:
	var grid: Grid = _grid_with_step(0.0, 1.0)
	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	assert_gt(Pathfinder.new(grid).move_cost(Vector2i(0, 0), Vector2i(1, 0)), 0.0)

	var kept: Array[Surface] = []
	for surface: Surface in grid.surfaces_at(Vector2i(0, 0)):
		if not (Surface.LADDER_TAG in surface.part.tags):
			kept.append(surface)
	grid.clear_surfaces(Vector2i(0, 0))
	for surface: Surface in kept:
		grid.add_surface(Vector2i(0, 0), surface)

	assert_lt(
		Pathfinder.new(grid).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		0.0,
		"with the ladder gone the ledge is unreachable again"
	)


# --- tb64 Pass F: BR63.01 and BR63.02 -----------------------------------------


## **`BR63.01`: a one-level rise gets one piece that reaches exactly its destination.**
##
## `_stamp_ladder` computes `ceil(rise / Surface.LADDER_SEGMENT_RISE)`, so the segment size is
## what decides both how many pieces stand and how far the top one overshoots. At 2.0 a 1.0 rise
## got a single piece standing a full level proud of the floor it served — one ladder, twice as
## tall as the thing it climbed.
func test_a_one_level_rise_gets_one_segment_that_does_not_overshoot() -> void:
	var grid: Grid = GridFixture.flat(6, 6, 0.0)
	GridFixture.place_floor(grid, Vector2i(3, 2), 1.0)

	assert_true(MapGen._open_a_route_out(grid, Vector2i(2, 2)), "a 1.0 rise gets a route")

	var segments: Array[Surface] = []
	var top: float = -INF
	for surface: Surface in grid.surfaces_at(Vector2i(2, 2)):
		if Surface.LADDER_TAG not in surface.part.tags:
			continue
		segments.append(surface)
		for placement: BoxPlacement in UnitGeometry.surface_placements(surface):
			var centre: Vector3 = placement.transform * placement.box.center
			top = maxf(top, centre.y + placement.box.size.y * 0.5)

	gut.p("  %d segment(s), topping out at %.2f for a 1.0 rise" % [segments.size(), top])
	assert_eq(segments.size(), 1, "one level is one piece")
	assert_almost_eq(top, 1.0, 0.001, "and it stops at the floor it serves, not a level above it")
	assert_true(
		Surface.ladder_serves_climb(grid, Vector2i(2, 2), Vector2i(3, 2)),
		"and it still opens the climb it was stood for"
	)


## A rise that genuinely needs several pieces gets them, stacked with no gap.
func test_a_four_level_rise_stacks_four_flush_segments() -> void:
	var grid: Grid = GridFixture.flat(6, 6, 0.0)
	GridFixture.place_floor(grid, Vector2i(3, 2), 4.0)
	assert_true(MapGen._open_a_route_out(grid, Vector2i(2, 2)))

	var heights: Array[float] = []
	for surface: Surface in grid.surfaces_at(Vector2i(2, 2)):
		if Surface.LADDER_TAG in surface.part.tags:
			heights.append(surface.height)
	heights.sort()

	gut.p("  segment heights: %s" % str(heights))
	assert_eq(heights.size(), 4, "four levels, four pieces")
	for i in range(heights.size()):
		assert_almost_eq(
			heights[i],
			float(i) * Surface.LADDER_SEGMENT_RISE,
			0.001,
			"segment %d sits flush on the one below it — a gap is a ladder with a missing rung" % i
		)
	assert_true(Surface.ladder_serves_climb(grid, Vector2i(2, 2), Vector2i(3, 2)))


## **`BR63.02`: one ladder, one set of boxes.**
##
## `GridPlacement.place` gives a side-attaching part two homes — its own `Surface` and a host's
## socket — and both used to be drawn, from different transforms, so a single ladder rendered as
## two panels 0.5 apart in z. Asserted by counting the boxes the whole cell emits rather than by
## inspecting the socket, because "how many pieces are there" is the question that was wrong.
func test_a_socketed_ladder_is_emitted_once_not_twice() -> void:
	var grid: Grid = GridFixture.flat(6, 6, 0.0)
	GridFixture.place_floor(grid, Vector2i(3, 2), 1.0)
	assert_true(MapGen._open_a_route_out(grid, Vector2i(2, 2)))

	var host: Surface = Surface.first_walkable(grid.surfaces_at(Vector2i(2, 2)))
	assert_not_null(host, "the cell still has its floor")
	var occupied := 0
	for socket: Socket in host.part.sockets:
		if socket.occupant != null:
			occupied += 1

	var ladder_boxes: Array[Vector3] = []
	for surface: Surface in grid.surfaces_at(Vector2i(2, 2)):
		for placement: BoxPlacement in UnitGeometry.surface_placements(surface):
			if Surface.LADDER_TAG in placement.part.tags:
				ladder_boxes.append(placement.transform * placement.box.center)

	gut.p("  host floor sockets occupied: %d" % occupied)
	gut.p("  ladder boxes emitted by the whole cell: %d" % ladder_boxes.size())
	for centre: Vector3 in ladder_boxes:
		gut.p("    (%.2f, %.2f, %.2f)" % [centre.x, centre.y, centre.z])

	assert_eq(
		ladder_boxes.size(),
		1,
		(
			"one segment is one box — the socket chain and the Surface record both emitting it is "
			+ "what BR63.02 saw as 'a strange offset' on one of two identical pieces"
		)
	)


## **The claim that halving the segment held climb cost steady, asserted rather than argued.**
##
## `Pathfinder.move_cost` prices a ladder edge by **rise** (`CLIMB_COST * level_delta *
## LADDER_COST_SCALE`), never by how many segments span it — which is why `BR63.01` needed no
## compensating change to `LADDER_COST_SCALE`. If that ever becomes segment-count-based, this is
## the test that says so.
func test_a_climbs_price_follows_its_rise_not_its_segment_count() -> void:
	var grid: Grid = _grid_with_step(0.0, 2.0)
	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 0.0)
	GridPlacement.place(grid, Vector2i(0, 0), DataLibrary.get_part(LADDER), 1.0)
	var unit: Unit = _climber(Vector2i(0, 0), grid)
	var pathfinder := Pathfinder.for_unit(grid, unit)

	var cost: float = pathfinder.move_cost(Vector2i(0, 0), Vector2i(1, 0))
	var expected: float = ceil(Pathfinder.CLIMB_COST * 2.0 * Pathfinder.LADDER_COST_SCALE)

	gut.p("  a 2.0 rise over %d segments costs %.1f MP" % [2, cost])
	assert_almost_eq(
		cost,
		expected,
		0.001,
		"the price is CLIMB_COST * rise * LADDER_COST_SCALE, whatever the segment size is"
	)
