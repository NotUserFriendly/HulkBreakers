extends GutTest

## taskblock-58 Pass C: **every one of these used to be authored by writing a float into
## `Grid.opacity`.** The array is retired, so a test that wants a wall now places a wall — which
## is the point of the pass, and also the reason the fixtures below read as boards rather than as
## flag pokes.
##
## The behavioural rules under test are the ones `LoS` has always kept: symmetry, the endpoint
## exemption, corner blocking on an exact diagonal, and a destroyed wall no longer blocking. What
## changed underneath is who answers.


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## An open floored board. Not a bare `Grid.new` any more: sight is geometry, so a board with no
## floor in it is a board that is not there, and every cell's sight height would read off a
## surface that does not exist.
func _open_grid(size: int) -> Grid:
	return GridFixture.flat(size, size)


func test_los_symmetric_on_open_ground() -> void:
	var grid := _open_grid(7)
	var pairs := [
		[Vector2i(0, 0), Vector2i(6, 6)],
		[Vector2i(0, 0), Vector2i(6, 0)],
		[Vector2i(1, 5), Vector2i(5, 1)],
		[Vector2i(2, 2), Vector2i(2, 2)],
	]
	for pair: Array in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		assert_true(LoS.has_los(grid, a, b), "a->b should see on open ground: %s -> %s" % [a, b])
		assert_true(LoS.has_los(grid, b, a), "b->a should see on open ground: %s -> %s" % [b, a])


func test_wall_blocks_los_both_directions() -> void:
	var grid := _open_grid(7)
	GridFixture.place_wall(grid, Vector2i(3, 3))

	var a := Vector2i(0, 3)
	var b := Vector2i(6, 3)
	assert_false(LoS.has_los(grid, a, b), "wall between a and b should block a->b")
	assert_false(LoS.has_los(grid, b, a), "wall between a and b should block b->a")


func test_los_clear_when_no_wall_in_path() -> void:
	var grid := _open_grid(7)
	GridFixture.place_wall(grid, Vector2i(3, 3))

	# A path that never crosses (3,3): straight along row 0.
	assert_true(LoS.has_los(grid, Vector2i(0, 0), Vector2i(6, 0)))


## The endpoint exemption. It used to mean "skip the first and last cell of the supercover walk";
## it now means the two cells' own parts are excluded from the query. Same rule, stated where a
## line is no longer a list of cells.
func test_los_ignores_geometry_on_the_endpoint_cells() -> void:
	var grid := _open_grid(5)
	var a := Vector2i(0, 0)
	var b := Vector2i(4, 0)
	GridFixture.place_wall(grid, a)
	GridFixture.place_wall(grid, b)
	assert_true(
		LoS.has_los(grid, a, b), "a wall on the shooter's/target's own cell must not self-block"
	)


## The corner-blocking rule used to be a property of `Grid.line`'s supercover walk. It is now a
## property of the boxes: two wall cells meeting at a lattice corner share a face plane, so a ray
## threading that corner meets one of them because it is actually there.
func test_corner_blocking_rule_on_exact_diagonal() -> void:
	var grid := _open_grid(5)
	GridFixture.place_wall(grid, Vector2i(1, 0))
	assert_false(
		LoS.has_los(grid, Vector2i(0, 0), Vector2i(2, 2)),
		"wall at one corner-bordering cell blocks the diagonal"
	)
	assert_false(
		LoS.has_los(grid, Vector2i(2, 2), Vector2i(0, 0)), "must block symmetrically in reverse"
	)


func test_corner_blocking_rule_other_bordering_cell() -> void:
	var grid := _open_grid(5)
	GridFixture.place_wall(grid, Vector2i(0, 1))
	assert_false(LoS.has_los(grid, Vector2i(0, 0), Vector2i(2, 2)))


## **This test reverses.** It used to assert "a blocker must not affect vision", because vision
## was a flat opacity array and cover was never flagged in it. taskblock-58 Pass C's rule is that
## **every 3D volume blocks sight** — so a crate standing at eye height between two units does
## block, for the same reason a wall does. Recorded in `docs/SUPERSEDED.md`.
##
## A crate is only cover when it is *below* the line, which is the second half here and is the
## behaviour the old rule was reaching for without being able to express it.
func test_cover_blocks_sight_when_it_stands_in_the_line_and_not_when_it_is_below_it() -> void:
	var tall := _open_grid(7)
	tall.blockers[Vector2i(3, 3)] = _crate(2.0)
	assert_false(
		LoS.has_los(tall, Vector2i(0, 3), Vector2i(6, 3)),
		"a crate taller than eye height is in the way, because it is in the way"
	)

	var low := _open_grid(7)
	low.blockers[Vector2i(3, 3)] = _crate(0.5)
	assert_true(
		LoS.has_los(low, Vector2i(0, 3), Vector2i(6, 3)),
		"and one you can see over is cover rather than a wall"
	)


func test_visible_cells_open_ground_matches_chebyshev_disc() -> void:
	var grid := _open_grid(11)
	var origin := Vector2i(5, 5)
	var range_val := 2
	var visible: Array[Vector2i] = LoS.visible_cells(grid, origin, range_val)
	assert_eq(visible.size(), (range_val * 2 + 1) * (range_val * 2 + 1))
	assert_has(visible, origin)
	assert_has(visible, Vector2i(3, 3))
	assert_has(visible, Vector2i(7, 7))
	assert_does_not_have(visible, Vector2i(8, 5))


func test_visible_cells_excludes_cells_behind_wall() -> void:
	var grid := _open_grid(7)
	# A wall segment at x=3 spanning the whole column blocks everything beyond it.
	for y in range(7):
		GridFixture.place_wall(grid, Vector2i(3, y))
	var origin := Vector2i(0, 3)
	var visible: Array[Vector2i] = LoS.visible_cells(grid, origin, 6)
	assert_does_not_have(visible, Vector2i(6, 3))
	assert_has(visible, Vector2i(2, 3))


## tb35 Pass C found that a wall destroyed by a real shot kept blocking sight forever, because
## nothing cleared `grid.opacity` on destruction. taskblock-58 Pass C deletes the flag rather than
## the bug: **there is nothing left to clear**, and the same `BodyProjector.projects` check that
## takes a dead wall out of the shot plane takes it out of the sight line.
func test_destroying_a_wall_with_a_real_shot_clears_los_through_it() -> void:
	var grid := _open_grid(7)
	var cell := Vector2i(3, 3)
	var wall_part: Part = GridFixture.place_wall(grid, cell)
	var state := CombatState.new(grid)
	var table: MaterialTable = DataLibrary.material_table()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var a := Vector2i(0, 3)
	var b := Vector2i(6, 3)
	assert_false(LoS.has_los(grid, a, b), "sanity: the standing wall blocks LOS")

	DamageResolver.resolve_shot(
		Vector2(0, 3), Vector2(1, 0), Vector2(0.0, 1.0), 500.0, 0.0, state, table, rng
	)

	assert_lte(wall_part.hp, 0, "sanity: the shot really destroyed the wall")
	assert_true(LoS.has_los(grid, a, b), "a destroyed wall must stop blocking LOS")


## A crate `height` tall, sitting on the ground. Hand-built rather than pulled from the library so
## the height under test is stated here rather than inherited from whatever a content file happens
## to say today.
func _crate(height: float) -> Part:
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 10
	crate.max_hp = 10
	crate.volume = [Box.new(Vector3(0.0, height * 0.5, 0.0), Vector3(1.0, height, 1.0))]
	return crate
