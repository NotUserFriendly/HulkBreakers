extends GutTest

## taskblock-52 Pass D: **membership dissolves — floors and field items are
## ordinary geometry to a ray.**
##
## `ShotPlane.build` looped `state.units` and `grid.blockers`. `PartPicker` looped
## `state.units`, `grid.blockers` and `grid.field_items`. **Neither looked at
## `grid.surfaces`**, and that absence is the whole of `BR34.05`'s "or the floor"
## half — a round angled slightly down had nothing to intersect, so "miss" was not
## a wrong branch being taken, it was the only branch that existed.
##
## A march does not enumerate a silhouette of the world; it meets what is in the
## way. Membership becomes a property of the query rather than a list maintained
## per caller.

const AIM_HEIGHT := 1.0


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"shooter_torso"
	torso.material = &"steel"
	torso.hp = 40
	torso.max_hp = 40
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## The floor exists as geometry at all. Authored as **data** — a `volume` on the
## `ship_floor` Part — rather than synthesised in code, because a designer adding
## a new walkable surface must not need a code edit (CLAUDE.md).
func test_the_shipped_floor_and_ramp_parts_carry_real_volume() -> void:
	for part_id in [&"ship_floor", &"ramp"]:
		var part: Part = DataLibrary.get_part(part_id)
		assert_not_null(part, "%s must load" % part_id)
		assert_false(part.volume.is_empty(), "%s must have geometry to be shootable" % part_id)
		var box: Box = part.volume[0]
		assert_almost_eq(box.size.x, 1.0, 0.0001, "%s spans its whole cell" % part_id)
		assert_almost_eq(box.size.z, 1.0, 0.0001, "%s spans its whole cell" % part_id)
		# The renderer draws a flat quad AT the surface height, so the box's top
		# face has to sit there — hence a centre half a thickness below zero.
		assert_almost_eq(
			box.center.y + box.size.y * 0.5,
			0.0,
			0.0001,
			"%s's top face sits exactly at the surface height" % part_id
		)


## **`BR34.05`'s "or the floor".** A downward shot strikes the floor, and the
## struck body is the surface's own `Part` — no stand-in type, no new outcome.
func test_a_downward_shot_strikes_the_floor_and_the_body_is_the_surfaces_own_part() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var shooter: Unit = _shooter(Vector2i(5, 5))
	var state := CombatState.new(grid, [shooter])
	var hit: RayHit = RayCaster.cast(
		state, Vector3(5.0, 2.0, 5.0), Vector3(0, -1, 0), shooter.shell.all_parts_with_joints()
	)
	assert_not_null(hit, "a round fired at the deck meets the deck")
	assert_eq(hit.kind, RayHit.KIND_SURFACE)
	assert_eq(hit.part.id, &"ship_floor", "the surface's own Part, not a stand-in")
	assert_eq(hit.body, hit.part, "a surface is its own body")
	assert_almost_eq(hit.point.y, 0.0, 0.0001, "struck at the deck's top face")
	assert_almost_eq(
		hit.normal.distance_to(Vector3(0, 1, 0)), 0.0, 0.0001, "on the upward-facing side"
	)


## An angled-down shot — the shape `BR34.05` describes, "a round angled slightly
## down, or passing over and between everything" — now lands. **In an enclosed
## room**, which is the arena the supervisor's rule is stated about.
func test_a_shallow_downward_shot_lands_rather_than_vanishing() -> void:
	var grid: Grid = GridFixture.enclosed_room(31, 31)
	var shooter: Unit = _shooter(Vector2i(15, 15))
	var state := CombatState.new(grid, [shooter])
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var from := Vector3(15.0, AIM_HEIGHT, 15.0)
	var landed := 0
	var shots := 0
	for degrees in range(1, 60):
		var drop: float = -tan(deg_to_rad(float(degrees)))
		var hit: RayHit = RayCaster.cast(
			state, from, Vector3(1.0, drop, 0.0).normalized(), excluded
		)
		shots += 1
		if hit != null:
			landed += 1
	print("  %d/%d shallow downward shots landed inside a closed room" % [landed, shots])
	assert_eq(landed, shots, "every one of them meets the deck or a wall")


## **The acceptance criterion's other half: every remaining miss has a named
## reason.** On an *open, unwalled* board a shallow enough round genuinely leaves
## the map — that is one of the two legitimate ways to hit nothing (`docs/02`:
## through an already-broken wall, or out through the ceiling; off the edge of an
## unenclosed board is the same fact).
##
## Asserted rather than waved at: a shot misses **exactly when** its own flight
## would run past the board before reaching the deck. The first version of this
## test asserted 29/29 on an open board, got 26, and was wrong — the three misses
## were the shallowest angles, which is correct behaviour.
func test_on_an_open_board_the_only_misses_are_rounds_that_leave_it() -> void:
	var grid: Grid = GridFixture.flat(31, 31)
	var shooter: Unit = _shooter(Vector2i(15, 15))
	var state := CombatState.new(grid, [shooter])
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var from := Vector3(15.0, AIM_HEIGHT, 15.0)
	# The deck's own top face is at 0.0, and the board's far edge is half a cell
	# past its last column.
	var run_to_edge: float = (float(grid.width - 1) - from.x) + 0.5
	var misses := 0
	for degrees in range(1, 60):
		var radians: float = deg_to_rad(float(degrees))
		var hit: RayHit = RayCaster.cast(
			state, from, Vector3(1.0, -tan(radians), 0.0).normalized(), excluded
		)
		# How far downrange this round needs to travel to reach the deck.
		var run_to_deck: float = from.y / tan(radians)
		var should_leave: bool = run_to_deck > run_to_edge
		if hit == null:
			misses += 1
		assert_eq(
			hit == null,
			should_leave,
			(
				"at %d degrees the round needs %.1f units of run and the board offers %.1f"
				% [degrees, run_to_deck, run_to_edge]
			)
		)
	print(
		(
			"  %d of 59 open-board shots left the map, each one shallower than the board is long"
			% misses
		)
	)
	assert_gt(misses, 0, "the sweep must actually produce the leaving case")


## Ramp-standing geometry resolves at its true ramp-aware height, and that is
## checked **against what `BoardView` renders**, not against a second copy of the
## height formula.
##
## taskblock-55 Pass B: `BoardView` no longer draws a quad per cell at all — it
## draws the placed `Surface` parts themselves, from the same
## `UnitGeometry.assembly_placements` call this ray march uses. So the agreement
## this test asserts is now structural rather than coincidental, and
## `true_height_for_cell` is asked here as the walkable top face a unit stands
## on, which is what a ramp cell's own height means.
func test_a_ramp_resolves_at_the_height_the_board_renders_it_at() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	GridFixture.place_ramp(grid, Vector2i(7, 5), 1.0)
	var state := CombatState.new(grid, [])
	var drawn: float = UnitGeometry.true_height_for_cell(Vector2i(7, 5), grid)
	print("  ramp at (7,5): BoardView draws its quad at y = %.3f" % drawn)
	assert_gt(drawn, 1.0, "a ramp cell rests above its own lower endpoint")

	var hit: RayHit = RayCaster.cast(state, Vector3(7.0, drawn + 2.0, 5.0), Vector3(0, -1, 0))
	assert_not_null(hit, "a round dropped onto the ramp meets it")
	assert_eq(hit.part.id, &"ramp")
	assert_almost_eq(hit.point.y, drawn, 0.0001, "struck exactly where the board draws the surface")


## A cell holding several surfaces exposes all of them — the catwalk-over-floor
## case `Surface`'s own doc comment names. Each is placed at **its own** height,
## which is why the surface march does not go through `true_height_for_cell`
## (that resolves to the first walkable one and would put both at the lower).
func test_a_cell_with_two_stacked_surfaces_exposes_both() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var catwalk: Part = DataLibrary.get_part(&"ship_floor")
	grid.add_surface(Vector2i(5, 5), Surface.new(catwalk, 3.0))
	var state := CombatState.new(grid, [])

	# From above, the catwalk is what a dropping round meets first.
	var upper: RayHit = RayCaster.cast(state, Vector3(5.0, 6.0, 5.0), Vector3(0, -1, 0))
	assert_not_null(upper)
	assert_almost_eq(upper.point.y, 3.0, 0.0001, "the catwalk, at its own height")

	# Started below it, the deck underneath is what it meets.
	var lower: RayHit = RayCaster.cast(state, Vector3(5.0, 2.0, 5.0), Vector3(0, -1, 0))
	assert_not_null(lower)
	assert_almost_eq(lower.point.y, 0.0, 0.0001, "and the deck below is still there")

	var surfaces: Array[Surface] = grid.surfaces_at(Vector2i(5, 5))
	assert_eq(surfaces.size(), 2, "both really are placed at that one cell")


## A cell holding several field items exposes all of them, not just the first —
## `Grid.shootable_part_at` returns only the first loose Part, and a march must
## not inherit that narrowing.
func test_a_cell_holding_several_field_items_exposes_all_of_them() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var near := Part.new()
	near.id = &"near_scrap"
	near.material = &"steel"
	near.hp = 20
	near.max_hp = 20
	near.volume = [Box.new(Vector3(-0.3, 0.5, 0.0), Vector3(0.2, 0.4, 0.4))]
	var far := Part.new()
	far.id = &"far_scrap"
	far.material = &"steel"
	far.hp = 20
	far.max_hp = 20
	far.volume = [Box.new(Vector3(0.3, 0.5, 0.0), Vector3(0.2, 0.4, 0.4))]
	grid.field_items[Vector2i(8, 5)] = [near, far]
	var state := CombatState.new(grid, [])

	var forward: RayHit = RayCaster.cast(state, Vector3(3.0, 0.5, 5.0), Vector3(1, 0, 0))
	assert_not_null(forward)
	assert_eq(forward.part, near, "approaching from -X, the -X-side pile is first")

	var backward: RayHit = RayCaster.cast(state, Vector3(13.0, 0.5, 5.0), Vector3(-1, 0, 0))
	assert_not_null(backward)
	assert_eq(backward.part, far, "and from +X the other one is — both are reachable")


## **`Part.is_destructible` was a dead flag until floors became geometry.** It is
## declared in `part.gd` and set false on `ship_floor` and `ramp`, and nothing
## read it. A 1-hp indestructible deck plate would have been destroyed by the
## first round to strike it, stopped projecting, and left a hole in the floor.
func test_an_indestructible_surface_takes_the_round_but_is_never_destroyed() -> void:
	var floor_part: Part = DataLibrary.get_part(&"ship_floor")
	assert_false(floor_part.is_destructible, "the shipped floor is permanent terrain")
	assert_eq(floor_part.hp, 1, "and carries exactly one hit point")

	var destroyed: bool = DamageResolver.apply_damage_to_part(floor_part, 500.0)
	assert_false(destroyed, "500 damage does not destroy permanent terrain")
	assert_eq(floor_part.hp, 1, "and does not even scratch its hp")


## The other side of the same rule: an ordinary destructible part is unaffected
## by the change. Without this the guard above could be silently switching off
## destruction everywhere.
func test_a_destructible_part_is_still_destroyed_exactly_as_before() -> void:
	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"steel"
	plate.hp = 10
	plate.max_hp = 10
	assert_false(DamageResolver.apply_damage_to_part(plate, 4.0), "4 of 10 does not destroy it")
	assert_eq(plate.hp, 6)
	assert_true(DamageResolver.apply_damage_to_part(plate, 6.0), "the rest does")
	assert_eq(plate.hp, 0)


## The chain end to end with a floor under it: a shot fired at the deck resolves
## through `RayChain` and produces a real impact, not an empty result.
func test_the_chain_resolves_a_shot_into_the_deck() -> void:
	var grid: Grid = GridFixture.flat(11, 11)
	var shooter: Unit = _shooter(Vector2i(5, 5))
	var state := CombatState.new(grid, [shooter])
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var results: Array[ImpactResult] = RayChain.resolve(
		state,
		Vector3(5.0, 1.5, 5.0),
		Vector3(8.0, 0.0, 5.0),
		8.0,
		0.0,
		state.material_table,
		rng,
		shooter.shell.all_parts_with_joints()
	)
	assert_false(results.is_empty(), "a shot at the deck hits the deck")
	var struck: Array[StringName] = []
	for result: ImpactResult in results:
		struck.append(result.region.part.id)
	print("  struck: %s" % str(struck))
	assert_true(&"ship_floor" in struck, "and the deck is what it struck")
	for result: ImpactResult in results:
		if result.region.part.id == &"ship_floor":
			assert_false(result.destroyed_part, "the deck survives being shot")


## **Can a round deflect off the floor?** (Supervisor, 2026-08-02: *"they should be
## able to."*) **Yes, and it falls out of the same incidence rule every other
## surface obeys** — the floor is ordinary geometry, so nothing special was needed
## to give it this.
##
## Fired low and shallow so the deck is reached before any wall: a grazing round
## skips off it, a steep one bites in.
func test_a_shallow_round_deflects_off_the_deck_and_a_steep_one_bites_in() -> void:
	var grid: Grid = GridFixture.enclosed_room(11, 11)
	var shooter: Unit = _shooter(Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter])
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	var from := Vector3(2.0, 0.3, 5.0)
	var seen: Dictionary = {}

	for degrees in [3, 75]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 52
		var direction: Vector3 = Vector3(1.0, -tan(deg_to_rad(float(degrees))), 0.0).normalized()
		# 3.0 is under steel's DT, so this is the deflect-or-stop decision rather
		# than a straight punch-through.
		var results: Array[ImpactResult] = RayChain.resolve(
			state, from, from + direction * 8.0, 3.0, 0.0, state.material_table, rng, excluded
		)
		for result: ImpactResult in results:
			if result.region.part.id == &"ship_floor" and not seen.has(degrees):
				seen[degrees] = Enums.Outcome.keys()[result.outcome]
		print(
			(
				"  %2d deg -> deck outcome %s (%d hop(s))"
				% [degrees, seen.get(degrees, "never reached it"), results.size()]
			)
		)

	assert_eq(seen.get(3, ""), "DEFLECT", "a grazing round skips off the deck")
	# **75, not 60.** At 60 degrees from horizontal the incidence against the deck's
	# own up-normal is exactly 30 — steel's `deflect_threshold_deg` to the degree —
	# so it lands on the boundary and float noise decides it. Picking the angle that
	# happens to fall the way an assertion wants is how a test starts describing its
	# own fixture; 75 sits at 15 degrees of incidence, unambiguously inside the
	# bite-in half.
	assert_eq(seen.get(75, ""), "STOP_DEAD", "and a steep one bites into it instead")


## **Deflecting off the deck must not depend on the deck being indestructible** —
## the supervisor's own note is that walls and ramps will not stay that way. The
## decision is incidence and DT, exactly as for any other surface, and
## `is_destructible` never enters it.
func test_a_deck_deflection_is_unchanged_when_the_deck_is_made_destructible() -> void:
	var outcomes: Array[String] = []
	for destructible in [false, true]:
		var grid: Grid = GridFixture.enclosed_room(11, 11)
		for surface: Surface in grid.placements():
			surface.part.is_destructible = destructible
		var shooter: Unit = _shooter(Vector2i(2, 5))
		var state := CombatState.new(grid, [shooter])
		var rng := RandomNumberGenerator.new()
		rng.seed = 52
		var direction: Vector3 = Vector3(1.0, -tan(deg_to_rad(3.0)), 0.0).normalized()
		var results: Array[ImpactResult] = RayChain.resolve(
			state,
			Vector3(2.0, 0.3, 5.0),
			Vector3(2.0, 0.3, 5.0) + direction * 8.0,
			3.0,
			0.0,
			state.material_table,
			rng,
			shooter.shell.all_parts_with_joints()
		)
		for result: ImpactResult in results:
			if result.region.part.id == &"ship_floor":
				outcomes.append(Enums.Outcome.keys()[result.outcome])
				break
	print("  indestructible -> %s ; destructible -> %s" % [outcomes[0], outcomes[1]])
	assert_eq(outcomes.size(), 2, "both runs struck the deck")
	assert_eq(outcomes[0], outcomes[1], "destructibility does not decide a deflection")
