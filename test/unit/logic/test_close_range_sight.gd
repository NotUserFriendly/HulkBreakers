extends GutTest

## taskblock-64 Pass A1 — **can two units standing next to each other see each other?**
##
## `BR63.05`: an `ELITE` chose `roam` — whose preconditions require `enemy_unknown` — with an enemy
## **two cells away**, and two `MINDLESS` units chose `seek_extraction` at **one cell**. The path is
## `UtilityContext._nearest_known_enemy` → `WorldView.units_visible_to` → `_has_direct_sight` →
## `LoS.has_los` → `RayCaster.obstructed`, so this is a **sight** failure feeding the planner rather
## than a firing one.
##
## ## Why this file exists before any fix
##
## **The one-cell case narrows without needing a board.** `_has_direct_sight` is *only*
## `LoS.has_los` — no range, no arc, no tier gate — and `has_los` exempts every part standing at
## either endpoint cell. So between two orthogonally adjacent cells at the same floor height,
## with a horizontal ray at `SIGHT_HEIGHT` between their centres, **nothing on that line should be
## able to block it.**
##
## Four candidates remain, and this walks the matrix that separates them:
##
## 1. the cells were at **different heights**, so the ray slants and clips a neighbour's box;
## 2. **`_endpoints` is not exempting what it should**;
## 3. **`RayCaster.obstructed` reports geometry that is not on the line**;
## 4. the units were not where the log said.
##
## **Every case prints its answer**, pass or fail, because the deliverable of a measuring pass is
## the measurement — a green run that reported nothing would leave the next reader exactly where
## this started.

const WALL := &"wall"
const LADDER := &"ladder"
## The pair under test. Orthogonally adjacent, mid-board, so every neighbour exists.
const LEFT := Vector2i(2, 2)
const RIGHT := Vector2i(3, 2)


func _board(height: float = 0.0) -> Grid:
	var grid := GridFixture.flat(6, 5, height)
	return grid


func _wall_at(grid: Grid, cell: Vector2i) -> void:
	grid.place_blocker(cell, DataLibrary.get_part(WALL))


## `LoS.has_los` both ways. Sight is symmetric by construction and a one-way answer would itself be
## a finding, so both are taken and reported rather than one assumed.
func _sees(grid: Grid, a: Vector2i, b: Vector2i) -> String:
	var there: bool = LoS.has_los(grid, a, b)
	var back: bool = LoS.has_los(grid, b, a)
	if there == back:
		return "yes" if there else "NO"
	return "ASYMMETRIC(%s/%s)" % [there, back]


# --- the baseline, which everything else is read against -----------------------------


## **If this fails, nothing below matters and the defect is not about walls at all.**
func test_two_adjacent_units_on_open_flat_ground_see_each_other() -> void:
	var grid: Grid = _board()

	var answer: String = _sees(grid, LEFT, RIGHT)
	gut.p("flat, open, one cell apart: %s" % answer)

	assert_eq(answer, "yes", "two units standing next to each other on clear ground must see")


## The two-cell case the log actually recorded, on clear ground.
func test_two_units_two_cells_apart_on_open_flat_ground_see_each_other() -> void:
	var grid: Grid = _board()

	var answer: String = _sees(grid, Vector2i(1, 2), Vector2i(3, 2))
	gut.p("flat, open, two cells apart: %s" % answer)

	assert_eq(answer, "yes", "and at the distance BR63.05 recorded")


# --- candidate 3: geometry that is not on the line -----------------------------------


## **A wall in every neighbouring cell in turn, none of them between the two units.** A cell that is
## not on the segment cannot occlude it; if any of these reads `NO`, `RayCaster.obstructed` is
## considering geometry off the line and that is the whole defect.
func test_a_wall_beside_the_line_never_blocks_it() -> void:
	var offenders: Array[String] = []
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			var cell: Vector2i = LEFT + Vector2i(dx, dy)
			if cell == LEFT or cell == RIGHT:
				continue
			var grid: Grid = _board()
			_wall_at(grid, cell)
			var answer: String = _sees(grid, LEFT, RIGHT)
			gut.p("  wall at %s (off the line): %s" % [cell, answer])
			if answer != "yes":
				offenders.append("%s -> %s" % [cell, answer])
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			var cell: Vector2i = RIGHT + Vector2i(dx, dy)
			if cell == LEFT or cell == RIGHT or cell.x <= LEFT.x + 1:
				continue
			var grid: Grid = _board()
			_wall_at(grid, cell)
			var answer: String = _sees(grid, LEFT, RIGHT)
			gut.p("  wall at %s (off the line): %s" % [cell, answer])
			if answer != "yes":
				offenders.append("%s -> %s" % [cell, answer])

	assert_eq(
		offenders,
		[] as Array[String],
		"a wall not between the two cells must not blind them: %s" % ", ".join(offenders)
	)


# --- candidate 2: the endpoint exemption ---------------------------------------------


## **A blocker standing on a unit's own cell must not blind it.** That is what `_endpoints` exists
## for — a unit on a catwalk begins its own sight line inside the surface it is standing on.
func test_a_blocker_at_either_endpoint_does_not_blind_the_pair() -> void:
	for endpoint: Vector2i in [LEFT, RIGHT]:
		var grid: Grid = _board()
		_wall_at(grid, endpoint)
		var answer: String = _sees(grid, LEFT, RIGHT)
		gut.p("  wall standing on %s (an endpoint): %s" % [endpoint, answer])
		assert_eq(answer, "yes", "a part at an endpoint cell is exempt by design")


## The same for a ladder, which is a **surface** rather than a blocker and takes the other branch of
## `RayCaster.obstructed` entirely. taskblock-63 Pass D1 stamps far more of these than any earlier
## board carried, so the branch matters more than it did.
func test_a_ladder_at_either_endpoint_does_not_blind_the_pair() -> void:
	for endpoint: Vector2i in [LEFT, RIGHT]:
		var grid: Grid = _board()
		GridPlacement.place(grid, endpoint, DataLibrary.get_part(LADDER), 0.0)
		var answer: String = _sees(grid, LEFT, RIGHT)
		gut.p("  ladder standing on %s (an endpoint): %s" % [endpoint, answer])
		assert_eq(answer, "yes", "a ladder at an endpoint cell is exempt for the same reason")


## And a ladder beside the line, which is the case a repaired board produces constantly.
func test_a_ladder_beside_the_line_does_not_blind_the_pair() -> void:
	var offenders: Array[String] = []
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var cell: Vector2i = LEFT + offset
		if cell == RIGHT:
			continue
		var grid: Grid = _board()
		GridPlacement.place(grid, cell, DataLibrary.get_part(LADDER), 0.0)
		var answer: String = _sees(grid, LEFT, RIGHT)
		gut.p("  ladder at %s (off the line): %s" % [cell, answer])
		if answer != "yes":
			offenders.append("%s -> %s" % [cell, answer])

	assert_eq(
		offenders,
		[] as Array[String],
		"a ladder off the line must not blind: %s" % ", ".join(offenders)
	)


# --- candidate 1: the slanted ray ----------------------------------------------------


## **The two cells at different floor heights**, which is ordinary on a terraced board and is the
## case the log's `(rise -1.00)` moves say was live. The ray slants; the question is whether it
## clips something it should not.
func test_two_adjacent_units_at_different_floor_heights_see_each_other() -> void:
	var results: Array[String] = []
	for rise: float in [0.4, 1.0, 2.0, 4.0]:
		var grid: Grid = _board()
		GridFixture.place_floor(grid, RIGHT, rise)
		var answer: String = _sees(grid, LEFT, RIGHT)
		gut.p("  adjacent, right cell raised by %.1f: %s" % [rise, answer])
		if answer != "yes":
			results.append("rise %.1f -> %s" % [rise, answer])

	assert_eq(
		results,
		[] as Array[String],
		"a step between two adjacent units must not blind them: %s" % ", ".join(results)
	)


## The same with a wall standing on the raised cell's far side — a shape a `_stand_wall` board
## produces on every room rim, and the one the standing hypothesis is about.
func test_a_wall_on_a_raised_neighbour_does_not_blind_the_pair() -> void:
	var results: Array[String] = []
	for rise: float in [1.0, 4.0]:
		var grid: Grid = _board()
		GridFixture.place_floor(grid, RIGHT, rise)
		grid.place_blocker(Vector2i(4, 2), DataLibrary.get_part(WALL), rise)
		var answer: String = _sees(grid, LEFT, RIGHT)
		gut.p("  right cell raised %.1f, wall beyond at that height: %s" % [rise, answer])
		if answer != "yes":
			results.append("rise %.1f -> %s" % [rise, answer])

	assert_eq(
		results,
		[] as Array[String],
		"a wall past the target is not between them: %s" % ", ".join(results)
	)


# --- the whole path, not just its last step ------------------------------------------


## **`WorldView.units_visible_to`, which is what the planner actually asks.** The tests above pin
## `LoS.has_los`; this pins that nothing between it and the AI drops the answer — a restricted view,
## two real units, one cell apart.
func test_the_planner_sees_an_adjacent_enemy_through_the_real_world_view() -> void:
	var grid: Grid = _board()
	var mine: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), LEFT, 0)
	var theirs: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), RIGHT, 1)
	var state := CombatState.new(grid, [mine, theirs] as Array[Unit], 7)
	state.assign_rest_to_ai([] as Array[int])
	# The same construction `AiPlanner.plan_turn` makes — `restricted` defaults to false and
	# `WorldView.full` is what every production caller builds, so the restriction that makes sight
	# gate knowledge at all is set by the planner rather than by the view.
	var view: WorldView = WorldView.full(state)
	view.restricted = true

	var visible: Array[Unit] = view.units_visible_to(mine)
	var names: Array[String] = []
	for unit: Unit in visible:
		names.append("u%d(sq%d)" % [unit.id, unit.squad_id])
	gut.p("units_visible_to a unit with an enemy one cell away: %s" % ", ".join(names))

	assert_true(visible.has(theirs), "the enemy standing next to it must be visible to the planner")


# --- and the case that SHOULD block, so "yes" everywhere above means something ----------


## **The anti-vacuity half of this whole file.** Every case above answers `yes`; if `LoS.has_los`
## simply always said yes, that would read identically and mean nothing. A wall genuinely between
## two units must block them — and it does.
##
## **And it kills the tempting alternative reading of `BR63.05`.** The one conclusive log
## observation is an `ELITE` choosing `roam` at *two* cells, where there is a cell between them —
## so "a piece of cover was in the way, and that is legitimate" looked like an innocent
## explanation. **It is not available: cover does not block sight.** A crate's box tops out below
## `LoS.SIGHT_HEIGHT` (1.25), so an eye-level line passes straight over it. Only a wall blinds, and
## walls are the thing taskblock-63 made taller.
func test_a_wall_between_two_units_blocks_but_cover_does_not() -> void:
	var grid: Grid = _board()
	grid.place_blocker(Vector2i(2, 2), DataLibrary.get_part(WALL))
	var walled: String = _sees(grid, Vector2i(1, 2), Vector2i(3, 2))
	gut.p("  wall ON the line, two cells apart: %s" % walled)
	assert_eq(walled, "NO", "a wall between two units must block them")

	var open_board: Grid = _board()
	open_board.place_blocker(Vector2i(2, 2), DataLibrary.get_part(&"crate"))
	var covered: String = _sees(open_board, Vector2i(1, 2), Vector2i(3, 2))
	gut.p("  crate ON the line, two cells apart: %s" % covered)
	assert_eq(
		covered,
		"yes",
		(
			"cover tops out below SIGHT_HEIGHT, so it stops shots and not sight — recorded because it "
			+ "removes the innocent explanation for BR63.05's two-cell observation"
		)
	)
