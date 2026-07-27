extends GutTest

## taskblock-44 Pass B: the line-of-fire query inverted — one field built from
## the target, after which each candidate cell's question is a bit test.
##
## **The acceptance is containment, not speed.** The field is a conservative
## prefilter and `ShotPlane` stays the one canonical resolver, so the only thing
## that can make this unsound is the field saying "no line" about a cell that
## actually has one. Every other kind of wrongness costs a `ShotPlane` build and
## nothing else.
##
## Containment is asserted in ONE direction on purpose. Asserting equality with
## `ShotPlane` would be asserting the thing the design explicitly refuses to
## promise — two visibility systems agreeing exactly — and would fail on cover,
## on units, and across levels, all three of which the field deliberately
## over-includes.


func _armed_unit(id: StringName, cell: Vector2i, squad_id: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var weapon := Part.new()
	weapon.id = StringName("%s_gun" % id)
	weapon.hp = 3
	weapon.max_hp = 3
	weapon.attaches_to = [&"GRIP"]
	weapon.requires = {&"TRIGGER": 1}
	weapon.damage = 5.0
	weapon.ap_cost = 1
	weapon.provides_actions = [&"shoot"]
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.max_range = 30.0
	weapon.scatter = [Ring.new(0.1, 1.0)]

	var hand := Part.new()
	hand.id = StringName("%s_hand" % id)
	hand.hp = 4
	hand.max_hp = 4
	hand.attaches_to = [&"HAND"]
	hand.capabilities = [&"TRIGGER"]
	var grip := Socket.new(&"GRIP")
	grip.occupant = weapon
	hand.sockets = [grip]
	var hand_socket := Socket.new(&"HAND")
	hand_socket.occupant = hand
	torso.sockets = [hand_socket]

	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad_id)


# --- containment: the real acceptance ----------------------------------------


## Swept over every cell of a real walled board: wherever `ShotPlane` says there
## is a clear line, the field must have that cell set. A one-directional superset
## check — the field may claim more, never less.
func test_every_cell_shot_plane_calls_clear_is_set_in_the_field() -> void:
	var grid: Grid = GridFixture.flat(20, 16)
	for y in range(2, 12):
		GridFixture.place_wall(grid, Vector2i(9, y))
	for x in range(4, 14):
		GridFixture.place_wall(grid, Vector2i(x, 12))
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(1, 1), 0)
	var target: Unit = _armed_unit(&"target", Vector2i(17, 6), 1)
	var state := CombatState.new(grid, [shooter, target])
	var field: VisibilityField = VisibilityField.build(state, target.cell)

	var clear_cells := 0
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if cell == target.cell:
				continue
			# Only cells a unit could actually stand on. Candidates always come
			# from `Pathfinder.reachable`, which never returns a cell holding a
			# live blocker, so the field's obligation is scoped to those — and a
			# wall cell asked about itself is a question no call site can pose.
			if BodyProjector.projects(grid.blockers.get(cell)):
				continue
			if not LineOfFire.has_clear_line_of_fire(shooter, target, cell, state):
				continue
			clear_cells += 1
			assert_true(
				field.allows(cell), "cell %s has a real line and must be in the field" % cell
			)
	assert_gt(clear_cells, 0, "sanity: the fixture has cells with a real line")


## A destroyed wall is the case where an opacity-only field would be WRONG rather
## than merely coarse: `Grid.opacity` is never cleared when a wall dies, but
## `BodyProjector` stops projecting it, so shots pass through a cell that still
## reads opaque. Under-inclusion is the one failure mode that matters, and this
## is where it would come from.
func test_a_destroyed_wall_stops_occluding_even_though_it_stays_opaque() -> void:
	var grid: Grid = GridFixture.flat(14, 8)
	var wall: Part = GridFixture.place_wall(grid, Vector2i(7, 4))
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(2, 4), 0)
	var target: Unit = _armed_unit(&"target", Vector2i(12, 4), 1)
	var state := CombatState.new(grid, [shooter, target])

	assert_false(
		VisibilityField.build(state, target.cell).allows(shooter.cell),
		"sanity: the standing wall does occlude"
	)

	wall.hp = 0

	assert_almost_eq(
		grid.get_opacity(Vector2i(7, 4)), 1.0, 0.001, "opacity is deliberately NOT cleared"
	)
	assert_true(
		VisibilityField.build(state, target.cell).allows(shooter.cell),
		"a dead wall no longer projects, so the field must stop occluding on it"
	)


## Cover blocks shots but not sight, so the field includes cells behind it. That
## is over-inclusion — safe by construction, and pinned here so a later
## "optimisation" that starts occluding on cover is caught as the correctness
## regression it would be.
func test_cover_does_not_occlude_the_field() -> void:
	var grid: Grid = GridFixture.flat(14, 8)
	var crate := Part.new()
	crate.id = &"crate"
	crate.hp = 5
	crate.max_hp = 5
	crate.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))]
	grid.blockers[Vector2i(7, 4)] = crate
	var target: Unit = _armed_unit(&"target", Vector2i(12, 4), 1)
	var state := CombatState.new(grid, [_armed_unit(&"shooter", Vector2i(2, 4), 0), target])

	assert_true(VisibilityField.build(state, target.cell).allows(Vector2i(2, 4)))


# --- the case the pass exists for --------------------------------------------


## taskblock-43's census: 19 of 60 turns end with no reachable cell having a
## line, and each used to build a real `ShotPlane` per candidate to find out.
## **Exactly zero**, asserted as a number rather than a bound, because this is
## the case the whole inversion is for.
func test_a_walled_off_target_costs_exactly_zero_shot_plane_builds() -> void:
	var grid: Grid = GridFixture.flat(20, 12)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(10, y))
	var shooter: Unit = _armed_unit(&"shooter", Vector2i(3, 5), 0)
	var target: Unit = _armed_unit(&"target", Vector2i(17, 5), 1)
	var state := CombatState.new(grid, [shooter, target])
	var reachable: Array[Vector2i] = []
	for y in range(3, 8):
		for x in range(1, 8):
			reachable.append(Vector2i(x, y))
	var field: VisibilityField = VisibilityField.build(state, target.cell)

	assert_true(field.allows_none(reachable), "the wall spans the board, so nothing has a line")

	ShotPlane.builds = 0
	var any: bool = UnitAI._any_reachable_has_lof(
		shooter, target, state, reachable, shooter.shell.find_part(&"shooter_gun"), {}, field
	)

	assert_false(any)
	assert_eq(ShotPlane.builds, 0, "the negative answer cost no geometry at all")


## Without this, a field with every bit set would pass containment and do
## nothing — the same reason taskblock-43 Pass A needed its skip-count test.
func test_the_field_actually_eliminates_candidates() -> void:
	var grid: Grid = GridFixture.flat(20, 12)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(10, y))
	var target: Unit = _armed_unit(&"target", Vector2i(17, 5), 1)
	var state := CombatState.new(grid, [_armed_unit(&"shooter", Vector2i(3, 5), 0), target])
	var field: VisibilityField = VisibilityField.build(state, target.cell)

	var allowed := 0
	var rejected := 0
	for y in range(grid.rows):
		for x in range(grid.width):
			if field.allows(Vector2i(x, y)):
				allowed += 1
			else:
				rejected += 1

	assert_gt(rejected, 0, "it rejects something")
	assert_gt(allowed, 0, "and it is not rejecting everything either")


# --- cross-level -------------------------------------------------------------


## A cell at a different elevation from the target is always included — the
## field's occlusion data is 2D and says nothing reliable about a shot passing
## over a wall from higher ground. Over-inclusive, therefore sound, and pinned so
## the exemption isn't quietly dropped later.
func test_a_cell_one_level_up_is_always_allowed() -> void:
	var grid: Grid = GridFixture.flat(16, 8)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(8, y))
	GridFixture.place_floor(grid, Vector2i(3, 4), 1.0)
	var target: Unit = _armed_unit(&"target", Vector2i(13, 4), 1)
	var state := CombatState.new(grid, [_armed_unit(&"shooter", Vector2i(3, 4), 0), target])
	var field: VisibilityField = VisibilityField.build(state, target.cell)

	assert_true(field.allows(Vector2i(3, 4)), "raised cell, behind a wall, still allowed")
	assert_false(field.allows(Vector2i(4, 4)), "its ground-level neighbour is not")


func test_a_cell_one_level_down_is_always_allowed() -> void:
	var grid: Grid = GridFixture.flat(16, 8, 1.0)
	for y in range(grid.rows):
		GridFixture.place_wall(grid, Vector2i(8, y))
	GridFixture.place_floor(grid, Vector2i(3, 4), 0.0)
	var target: Unit = _armed_unit(&"target", Vector2i(13, 4), 1)
	var state := CombatState.new(grid, [_armed_unit(&"shooter", Vector2i(3, 4), 0), target])
	var field: VisibilityField = VisibilityField.build(state, target.cell)

	assert_true(field.allows(Vector2i(3, 4)))
	assert_false(field.allows(Vector2i(4, 4)))


# --- geometry basics ---------------------------------------------------------


func test_the_targets_own_cell_is_allowed() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	var target: Unit = _armed_unit(&"target", Vector2i(5, 5), 1)
	var state := CombatState.new(grid, [target])

	assert_true(VisibilityField.build(state, target.cell).allows(target.cell))


## Out of bounds reads true: a caller asking about a cell off the board is asking
## something the field has no standing to answer negatively.
func test_out_of_bounds_is_allowed_rather_than_rejected() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	var state := CombatState.new(grid, [_armed_unit(&"target", Vector2i(5, 5), 1)])
	var field: VisibilityField = VisibilityField.build(state, Vector2i(5, 5))

	assert_true(field.allows(Vector2i(-1, 5)))
	assert_true(field.allows(Vector2i(99, 5)))
