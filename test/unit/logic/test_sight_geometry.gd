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
		grid.blocker_part_at(cell), cell, 0.0, null, height
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


## **The same sweep with the endpoint exemption actually applied** — `BR64.01`, tb64 Pass B.
##
## The sweep above passes `[] as Array[Part]`, and **the entire defect lived in how
## `exclude_parts` is applied**, so with nothing excluded the two loops agreed trivially and the
## disagreement went unseen through every run of it. `LoS.has_los` never calls either loop with
## an empty exclusion — it always passes `_endpoints` — so the configuration the sweep tested is
## the one production does not use.
##
## What it was hiding: `obstructed` filtered each candidate on the **root** it enumerated
## (`surface.part`) and then handed the whole assembly to `_any_box_hit`, which checked nothing
## per box. **A ladder socketed into a floor's `LEDGE` socket is a different `Part`**, so an
## excluded ladder still blinded — 56 of 751 blind pairs on seed `642296523`, and a unit blinded
## by a part its own endpoint exemption had already taken off the board.
##
## Sweeps cell PAIRS rather than angles, because the exemption is a property of the two endpoint
## cells and an angle sweep from one origin varies only one of them.
##
## **This is a breadth check and it is NOT what pins `BR64.01`** — stated plainly because the
## honest version of "add a test" is knowing which test carries the weight. Seed 4242 at 24x18
## has no socketed ledge ladder on any swept pair, so this passed both before and after the fix.
## `test_an_excluded_part_socketed_onto_a_neighbours_floor_does_not_blind` below is the guard;
## this one catches whatever else the two loops might disagree about later.
func test_the_two_loops_agree_when_the_endpoint_exemption_is_applied() -> void:
	var grid: Grid = MapGen.generate(4242, 24, 18)
	var pathfinder := Pathfinder.new(grid)
	var cells: Array[Vector2i] = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if pathfinder.is_walkable(cell):
				cells.append(cell)

	var compared := 0
	var blocked := 0
	var disagreements: Array[String] = []
	for a: Vector2i in cells:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]:
			var b: Vector2i = a + offset
			if not grid.in_bounds(b):
				continue
			# **The real exemption, not a re-derivation of it.** `LoS._endpoints` walks the
			# socket tree; rebuilding it from `grid.parts_at` here would test a second copy of
			# the rule and agree with nothing (`BR64.01` lived in exactly that gap).
			var excluded: Array[Part] = LoS._endpoints(grid, a, b)
			var from: Vector3 = LoS.sight_point(grid, a)
			var to: Vector3 = LoS.sight_point(grid, b)
			var span: Vector3 = to - from
			var distance: float = span.length()
			if distance <= 0.0001:
				continue
			var any_hit: bool = RayCaster.obstructed(grid, from, to, excluded)
			# `span`, not `span / distance` — see the note in
			# `test_generated_board_sight_sweep.gd`: normalising twice lands one ULP off what
			# `obstructed` computes, which only shows up on an exact corner graze.
			var nearest: RayHit = RayCaster.cast_geometry(
				grid, from, span, excluded, distance - 0.0001
			)
			compared += 1
			if any_hit:
				blocked += 1
			if any_hit != (nearest != null):
				disagreements.append(
					(
						"%s->%s obstructed=%s cast_geometry=%s"
						% [a, b, any_hit, "null" if nearest == null else str(nearest.part.id)]
					)
				)

	gut.p(
		(
			"  compared %d pairs, %d blocked, %d disagreements"
			% [compared, blocked, disagreements.size()]
		)
	)
	for line: String in disagreements:
		gut.p("    %s" % line)

	assert_gt(compared, 200, "the sweep actually ran")
	assert_gt(blocked, 0, "and it included blocked pairs, or agreement proves nothing")
	assert_eq(
		disagreements,
		[] as Array[String],
		(
			"the sight predicate and the shot march must meet the same geometry — RayCaster's own "
			+ "header: 'the thing LoS sees and the thing a round meets cannot drift apart'"
		)
	)


## **`BR64.01`'s guard** — the exact geometry, hand-built, tb64 Pass B.
##
## `GridPlacement.place` gives a side-attaching ladder two homes: it becomes a `Surface` at its
## own cell **and** an occupant of a neighbouring floor's `LEDGE` socket. So the same `Part` is
## reachable through two different roots, and the endpoint exemption only ever knew about one
## of them.
##
## Here the ladder is placed at `(2,2)` and takes `(1,2)`'s `LEDGE_E`. A sight line from `(1,3)`
## to `(2,2)` has the ladder **at an endpoint cell**, so `LoS._endpoints` excludes it — and
## `obstructed` reached it anyway through `(1,2)`'s `ship_floor` assembly, where nothing checked
## the exclusion per box. **A unit was blinded by the ladder it is standing next to.**
##
## `(2,1) -> (2,3)` is the control and must stay blocked: neither endpoint owns the ladder, so
## nothing exempts it and a tall enough panel across the line is a real occluder.
##
## **The control needs TWO segments since tb64 Pass F.** `LADDER_SEGMENT_RISE` went 2.0 -> 1.0
## (`BR63.01`), so one ground-level segment now tops out at 1.0 — below `LoS.SIGHT_HEIGHT` of
## 1.25 — and blinds nobody. A single segment would make this control silently vacuous, asserting
## a block that no longer happens for a reason unrelated to the exemption being tested.
func test_an_excluded_part_socketed_onto_a_neighbours_floor_does_not_blind() -> void:
	var grid: Grid = GridFixture.flat(6, 5, 0.0)
	# A height difference is what gives the ladder something to side-attach to.
	GridFixture.place_floor(grid, Vector2i(3, 2), 1.0)
	var placed: Surface = GridPlacement.place(
		grid, Vector2i(2, 2), DataLibrary.get_part(&"ladder"), 0.0
	)
	assert_not_null(placed, "the fixture needs the ladder to actually place")
	# The second segment is what carries the control above `SIGHT_HEIGHT`.
	assert_not_null(
		GridPlacement.place(grid, Vector2i(2, 2), DataLibrary.get_part(&"ladder"), 1.0),
		"and a second segment stacked on it, or the control below asserts nothing"
	)

	var ladder: Part = null
	for socket: Socket in Surface.first_walkable(grid.surfaces_at(Vector2i(1, 2))).part.sockets:
		if socket.occupant != null:
			ladder = socket.occupant
	assert_not_null(ladder, "the ladder must have taken the neighbouring floor's LEDGE socket")
	assert_true(
		grid.parts_at(Vector2i(2, 2)).has(ladder),
		"and must also be registered at its own cell, or the exemption never covers it"
	)

	gut.p(
		(
			"  (1,3) -> (2,2), ladder at an endpoint: %s"
			% LoS.has_los(grid, Vector2i(1, 3), Vector2i(2, 2))
		)
	)
	gut.p(
		(
			"  (2,1) -> (2,3), ladder at neither:     %s"
			% LoS.has_los(grid, Vector2i(2, 1), Vector2i(2, 3))
		)
	)

	assert_true(
		LoS.has_los(grid, Vector2i(1, 3), Vector2i(2, 2)),
		"a part the endpoint exemption excluded must not blind, whichever root reaches it"
	)
	assert_true(LoS.has_los(grid, Vector2i(2, 2), Vector2i(1, 3)), "and symmetrically")
	assert_false(
		LoS.has_los(grid, Vector2i(2, 1), Vector2i(2, 3)),
		"the control: exempt from nothing, a two-segment ladder across the line still blocks"
	)
