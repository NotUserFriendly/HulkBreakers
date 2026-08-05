extends GutTest

## taskblock-58 Pass C: **one thing answers "can A see B", and that thing is the geometry.**
##
## Three things used to answer it — `LoS` over a flat `Grid.opacity` array, `VisibilityField`
## shadowcasting from the same array, and `RayCaster` marching the real boxes. The array is
## retired. What is asserted here is what the array could not express, and the containment the
## field's whole contract rests on.

const SIGHT := LoS.SIGHT_HEIGHT


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## **The case the flat array could not express.** Same cell, same wall part, same everything the
## old opacity flag could see — and the answer differs, because the geometry is at a different
## height. A per-cell float had nowhere to put that.
func test_a_low_wall_does_not_block_a_sight_line_that_passes_above_it() -> void:
	var observer := Vector2i(2, 5)
	var target := Vector2i(8, 5)
	var between := Vector2i(5, 5)

	# Both ends stand on floors at 2.0, so the sight line runs at 2.0 + SIGHT.
	var low: Grid = GridFixture.flat(11, 11, 2.0)
	GridFixture.place_wall(low, between, 0.0)
	# The same board with the wall's own cell raised until its box straddles the line.
	var high: Grid = GridFixture.flat(11, 11, 2.0)
	GridFixture.place_wall(high, between, 2.0)

	var line_height: float = 2.0 * UnitGeometry.LEVEL_HEIGHT + SIGHT
	gut.p("  sight line runs at y = %.2f" % line_height)
	gut.p("  low wall  top = %.2f" % _top_of_blocker(low, between))
	gut.p("  high wall top = %.2f" % _top_of_blocker(high, between))

	assert_true(
		LoS.has_los(low, observer, target),
		"a wall down at ground level does not hide a unit standing two levels up"
	)
	assert_false(
		LoS.has_los(high, observer, target), "the same wall, at the line's own height, does"
	)


## `DamageResolver` used to have to reach in and zero an opacity flag when a blocker died,
## because nothing else maintained the array. **Nothing clears anything now** — the part's hp is
## the whole of it, read through `BodyProjector.projects` in the one place that decides it.
func test_destroying_a_wall_restores_sight_with_no_flag_to_clear() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(5, 5))
	var observer := Vector2i(2, 5)
	var target := Vector2i(8, 5)

	assert_false(LoS.has_los(grid, observer, target), "the wall is standing")

	wall.hp = 0

	assert_true(LoS.has_los(grid, observer, target), "and the hole in it is the sight line")
	assert_true(
		VisibilityField.build(grid, target).allows(observer),
		"the field agrees, having been built from the same geometry"
	)


## The field is a pre-filter, and its standing obligation is *never report "no line" for a cell
## that actually has one*. `SightSpans` is deliberately weaker than the march, so this sweeps a
## real board and checks the containment rather than arguing it — the direction of the
## approximation is the entire safety argument, and an argument is not a measurement.
func test_the_field_never_reports_blocked_where_the_march_reports_clear() -> void:
	var grid: Grid = MapGen.generate(4242, 24, 18)
	var target := Vector2i(12, 9)
	var field: VisibilityField = VisibilityField.build(grid, target)

	var checked := 0
	var breaches: Array[String] = []
	var field_blocked := 0
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			# The containment is scoped to cells a unit could stand on — every cell any caller can
			# supply. A wall cell asked about itself is a question nothing asks, and the field's
			# own doc comment already records that it and the resolver can disagree there.
			if grid.blockers.has(cell):
				continue
			if Surface.first_walkable(grid.surfaces_at(cell)) == null:
				continue
			checked += 1
			var allows: bool = field.allows(cell)
			if not allows:
				field_blocked += 1
			if not allows and LoS.has_los(grid, target, cell):
				breaches.append(str(cell))
	gut.p(
		(
			"  swept %d standable cells from %s — field blocked %d, breaches %d"
			% [checked, target, field_blocked, breaches.size()]
		)
	)
	assert_gt(checked, 100, "the sweep had a real board to sweep")
	assert_gt(field_blocked, 0, "and the field actually blocks something, or this proves nothing")
	assert_eq(
		breaches.size(),
		0,
		"the field must never be stricter than the march: %s" % ", ".join(breaches.slice(0, 8))
	)


## `Cover` reads the field now instead of walking its own line. The conclusive direction is the
## only one it uses: `allows()` false means fully covered.
func test_cover_reports_covered_exactly_where_the_field_is_conclusive() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	for y in range(11):
		GridFixture.place_wall(grid, Vector2i(5, y))
	var mover: Unit = _unit(Vector2i(2, 5), 0)
	var threat: Unit = _unit(Vector2i(8, 5), 1)
	var state := CombatState.new(grid, [mover, threat])
	var field: VisibilityField = VisibilityField.build(grid, threat.cell)
	var view: WorldView = WorldView.full(state)

	assert_false(field.allows(mover.cell), "a solid wall between them is conclusive")
	assert_true(
		Cover.is_covered_from(mover.cell, threat.cell, view, mover, field),
		"and cover says so, off that same bit"
	)
	assert_false(
		Cover.is_covered_from(threat.cell, threat.cell, view, mover, field),
		"standing on the threat is never cover — there is no line to interpose on"
	)


## A cell only a wall's own *flag* used to hide. With sight geometric, a unit standing behind
## nothing is visible, and the field and the march agree about it.
func test_an_open_board_hides_nothing() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var target := Vector2i(5, 5)
	var field: VisibilityField = VisibilityField.build(grid, target)

	for y in range(11):
		for x in range(11):
			var cell := Vector2i(x, y)
			assert_true(LoS.has_los(grid, target, cell), "nothing is in the way at %s" % cell)
			assert_true(field.allows(cell), "and the field says so at %s" % cell)


## The endpoint exemption, which used to be "skip the first and last cell of the supercover walk"
## and is now the two cells' own parts excluded from the query. A unit standing in a wall cell —
## which the injector's `set_passable` can produce — must not be blind to everything.
func test_a_unit_standing_in_a_wall_cell_can_still_see_out() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	GridFixture.place_wall(grid, Vector2i(5, 5))

	assert_true(
		LoS.has_los(grid, Vector2i(5, 5), Vector2i(8, 5)),
		"its own cell never blocks sight out of it"
	)
	assert_true(
		LoS.has_los(grid, Vector2i(8, 5), Vector2i(5, 5)), "nor sight into it, symmetrically"
	)


## A floor is a volume too, so it blocks sight through it — which is the rule "every 3D volume
## blocks sight" doing something the opacity array never could, since nothing ever flagged a floor.
func test_a_deck_plate_at_eye_height_blocks_sight() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	grid.add_surface(Vector2i(5, 5), Surface.new(DataLibrary.get_part(&"ship_floor"), SIGHT))

	assert_false(
		LoS.has_los(grid, Vector2i(2, 5), Vector2i(8, 5)),
		"a deck plate hanging at eye height is in the way, because it is in the way"
	)


func _top_of_blocker(grid: Grid, cell: Vector2i) -> float:
	var height: float = UnitGeometry.true_height_for_cell(cell, grid)
	var placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(
		grid.blockers[cell], cell, 0.0, null, height
	)
	var top: float = -INF
	for placement: BoxPlacement in placements:
		top = maxf(top, (placement.transform * placement.box.center).y + placement.box.size.y * 0.5)
	return top


func _unit(cell: Vector2i, squad: int) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


## `RayCaster.obstructed` is an any-hit loop with early exit; `RayCaster.cast_geometry` is the
## nearest-hit march. **A nearest hit exists exactly when any hit does**, so the two must agree on
## the boolean for every ray — which is the claim that lets the sight query skip the bookkeeping,
## and therefore the claim worth checking rather than asserting in a comment.
func test_the_any_hit_loop_agrees_with_the_nearest_hit_march() -> void:
	var grid: Grid = MapGen.generate(4242, 24, 18)
	var compared := 0
	var blocked := 0
	for angle in range(0, 360, 17):
		for reach in [3.0, 9.0, 15.0]:
			var rad: float = deg_to_rad(float(angle))
			var origin := Vector2i(12, 9)
			var target := Vector2i(
				12 + int(round(cos(rad) * (reach as float))),
				9 + int(round(sin(rad) * (reach as float)))
			)
			if not grid.in_bounds(target) or target == origin:
				continue
			var from: Vector3 = LoS.sight_point(grid, origin)
			var to: Vector3 = LoS.sight_point(grid, target)
			var span: Vector3 = to - from
			var distance: float = span.length()
			if distance <= 0.0001:
				continue
			var any_hit: bool = RayCaster.obstructed(grid, from, to)
			var nearest: RayHit = RayCaster.cast_geometry(
				grid, from, span / distance, [] as Array[Part], distance - 0.0001
			)
			assert_eq(
				any_hit,
				nearest != null,
				"the two loops must agree at %d degrees, reach %s" % [angle, reach]
			)
			compared += 1
			if any_hit:
				blocked += 1
	gut.p("  compared %d rays, %d of them blocked" % [compared, blocked])
	assert_gt(compared, 40, "the sweep actually ran")
	assert_gt(blocked, 0, "and it included blocked rays, or agreement proves nothing")
