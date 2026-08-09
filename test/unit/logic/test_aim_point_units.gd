extends GutTest

## tb61 (`BR51.01`): **a plane point and a cell address are different things, and one function
## used to return the second where the first was expected.**
##
## `ShotPlane.center_of`/`center_of_part` answered a lookup miss with `Vector2(cell.x, cell.y)`.
## A plane point is `(lateral offset from the ray axis, world height)` — under a cell in each
## component for any real body. A cell address is wherever the target happens to sit on the
## board, and on a 24-cell map that is two orders of magnitude larger.
##
## **What it cost.** `TacticsController.aim_reticle_at_screen` computes
## `reticle_offset = hit - centre`. With `centre` returning cell `(7, 15)` the offset came out at
## `(-14.74, -19.73)` — the shot aimed fourteen cells sideways and nineteen below the deck.
## Nothing clamps it. Measured in a real session: **290 of 290 reticle events on inanimate
## targets took this path**, and every shot at a pillar or wall flew off at roughly 90 degrees.
##
## **Two defects stacked, and both are fixed.** The lookup missed because a Part target was never
## re-resolved into the preview `CombatState` (the unit branch did; the part branch did not
## exist), and the miss then returned the wrong units instead of complaining.


func _wall_at(grid: Grid, cell: Vector2i) -> Part:
	var wall: Part = DataLibrary.get_part(&"wall")
	if wall == null:
		return null
	var placed: Part = wall.duplicate(true) as Part
	grid.blockers[cell] = placed
	return placed


## **A miss returns a plane point, not a cell address — and says so out loud.**
##
## `Vector2.ZERO` is dead centre on the ray axis at the target's own depth: the honest degraded
## answer in the caller's own units, and the one value that cannot be mistaken for a real
## off-centre aim. The `push_error` is the supervisor's call — *"misses loud"* — and
## `EngineErrorTap` puts it on the same combat log the shot is logged to.
func test_a_missed_lookup_returns_plane_centre_and_pushes_an_error() -> void:
	var stray: Part = DataLibrary.get_part(&"wall")
	assert_not_null(stray, "sanity: the wall part loads")
	if stray == null:
		return

	var centre: Variant = ShotPlane.center_of([], stray)
	# The miss is loud on purpose, so the test claims the error rather than tripping over it.
	assert_push_error("ShotPlane: no region for")
	gut.p("miss returned %s" % str(centre))
	assert_null(
		centre,
		(
			"a miss must not invent an aim point — returning the cell (7, 15) is what produced a "
			+ "-14.74,-19.73 reticle offset in the reported session"
		)
	)
	assert_ne(
		centre, Vector2(7, 15), "and specifically must not hand back the cell address it was given"
	)


## **The whole point, stated as the property the old code violated.** Whatever a lookup returns
## on a miss, it must be small — a plane point's components are bounded by the size of a body,
## not by the size of the map. This fails against the old `Vector2(cell.x, cell.y)` for any
## target that is not at the origin, which is every target.
func test_a_miss_is_bounded_like_a_plane_point_not_like_a_map_coordinate() -> void:
	var stray: Part = DataLibrary.get_part(&"wall")
	if stray == null:
		return
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(7, 15), Vector2i(31, 23)]:
		var centre: Variant = ShotPlane.center_of([], stray)
		assert_push_error("ShotPlane: no region for")
		assert_null(
			centre, "a miss at %s must be null rather than a map-scaled coordinate" % str(cell)
		)


## **The identity half: a real region IS found when the part is the one the plane was built
## from.** Without this the test above would pass against a function that always missed.
func test_a_part_the_plane_knows_about_resolves_to_a_real_region() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var wall: Part = _wall_at(grid, Vector2i(6, 4))
	if wall == null:
		return
	var state := CombatState.new(grid, [] as Array[Unit])
	var plane: Array[Region] = ShotPlane.build(
		Vector3(6.0, 1.5, 8.0), Vector3(0.0, 0.0, -1.0), state
	)

	var centre: Vector2 = ShotPlane.center_of(plane, wall)
	gut.p("wall centre in plane units: %s" % str(centre))
	assert_lt(absf(centre.x), 2.0, "a found region gives a real, small lateral")
	assert_ne(centre, Vector2(6, 4), "and it is emphatically not the cell address")


## **A duplicated Part does not match by identity, which is why the preview branch was needed.**
## This is the mechanism rather than the symptom: `CombatState.dup()` clones blockers, so a
## caller holding the original finds nothing in a plane built from the copy.
func test_a_duplicated_part_does_not_match_the_original_by_identity() -> void:
	var grid: Grid = GridFixture.flat(12, 12)
	var original: Part = _wall_at(grid, Vector2i(6, 4))
	if original == null:
		return
	var state := CombatState.new(grid, [] as Array[Unit])
	var copy: CombatState = state.dup()
	var duplicated: Variant = copy.grid.blockers.get(Vector2i(6, 4))

	assert_not_null(duplicated, "sanity: the clone still has a blocker there")
	assert_false(
		duplicated == original,
		(
			"the clone's blocker is a DIFFERENT object — so a lookup keyed on identity misses, "
			+ "which is exactly what BR51.01 was"
		)
	)
