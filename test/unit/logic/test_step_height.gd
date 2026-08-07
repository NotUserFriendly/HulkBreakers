extends GutTest

## tb60 Pass A: **the free rise, and the ramp subsystem it replaced.**
##
## Five categorical "is this cell labelled a ramp" checks became one continuous comparison
## against a per-unit stat. This file holds the claims that are about the replacement itself
## rather than about any one caller — the boundary behaviour, the stat's per-unit-ness, the
## generator's invariant, and the guard that stops the deleted identifiers coming back.

## The three identifiers the ramp subsystem was made of. **Identifiers, deliberately — not
## the word `ramp`.**
##
## A guard that banned the word outright would be the wrong instrument here, and the project
## has already learned that once: a total ban cannot tell a correct use from an incorrect
## one, and it fails the first code that uses the word as intended. **The word is not
## retired.** `data/parts/ramp.tres` still exists, `Surface.RAMP_TAG` still drives sloped
## rendering through `RampGeometry`, and `CellInspection` still names the shape to a player —
## a cosmetic ramp is content this pass deliberately kept. What is retired is the *machinery*:
## these three names, each of which was a traversal decision made from a label.
const RETIRED_IDENTIFIERS: Array[String] = ["is_ramp_at", "RAMP_MAX_RISE", "CellKind.RAMP"]
const SELF_PATH := "res://test/unit/logic/test_step_height.gd"


func _make_unit(cell: Vector2i, step_mod: float = 0.0) -> Unit:
	var root := Part.new()
	root.id = &"test_torso"
	root.hp = 5
	root.max_hp = 5
	if not is_zero_approx(step_mod):
		root.stat_mods = {Unit.STEP_HEIGHT_STAT_KEY: step_mod}
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


# --- the boundary --------------------------------------------------------------------


## The taskblock's own acceptance, stated as one test: **a unit with no climbing capability
## walks up a rise at or below its step height, and not one above.**
##
## The unit authors no `CLIMBER` tag, so before this pass it could not go up *at all* without
## a ramp or a ladder — which is precisely why a 0.3 tile was not walkable-onto by anything
## in the game and why the stat had to exist.
func test_a_non_climber_walks_up_to_its_step_height_and_no_further() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var at_the_limit := GridFixture.flat(2, 1)
	GridFixture.place_floor(at_the_limit, Vector2i(1, 0), unit.step_height())
	var just_over := GridFixture.flat(2, 1)
	GridFixture.place_floor(just_over, Vector2i(1, 0), unit.step_height() + 0.05)

	var limit_cost: float = Pathfinder.for_unit(at_the_limit, unit).move_cost(
		Vector2i(0, 0), Vector2i(1, 0)
	)
	var over_cost: float = Pathfinder.for_unit(just_over, unit).move_cost(
		Vector2i(0, 0), Vector2i(1, 0)
	)

	gut.p(
		(
			"step height %.2f: at-limit %.1f, just-over %.1f"
			% [unit.step_height(), limit_cost, over_cost]
		)
	)
	assert_almost_eq(
		limit_cost, Pathfinder.DEFAULT_COST, 0.0001, "a rise AT the step height is a plain walk"
	)
	assert_almost_eq(
		over_cost, -1.0, 0.0001, "and a rise just above it is not an edge for a non-climber"
	)


## **Symmetric, and that is load-bearing.** An asymmetric free rise would manufacture one-way
## ground a fraction of a level at a time — `BR46.02` in miniature — so a step you can climb
## must be a step you can descend.
func test_the_free_rise_is_the_same_going_down() -> void:
	var unit := _make_unit(Vector2i(0, 0))
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(0, 0), unit.step_height())
	var pf := Pathfinder.for_unit(grid, unit)

	assert_almost_eq(
		pf.move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.DEFAULT_COST,
		0.0001,
		"stepping down the same rise costs the same as stepping up it"
	)


# --- the stat ------------------------------------------------------------------------


## **Step height is a per-unit stat, which is the thing a ramp could never express.** Two
## units on the identical board disagree about whether the same rise is walkable — long legs
## step higher. Resolved through `StatResolver` like every other final number (docs/08), so a
## part swap changes it on the same frame and the tooltip and the pathfinder read one call.
func test_two_units_disagree_about_the_same_rise() -> void:
	var ordinary := _make_unit(Vector2i(0, 0))
	var long_legged := _make_unit(Vector2i(0, 0), 0.4)
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), Unit.BASE_STEP_HEIGHT + 0.2)

	gut.p("ordinary %.2f, long-legged %.2f" % [ordinary.step_height(), long_legged.step_height()])
	assert_gt(long_legged.step_height(), ordinary.step_height(), "the part mod raised the stat")
	assert_almost_eq(
		Pathfinder.for_unit(grid, ordinary).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		-1.0,
		0.0001,
		"the ordinary unit cannot make the step"
	)
	assert_almost_eq(
		Pathfinder.for_unit(grid, long_legged).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.DEFAULT_COST,
		0.0001,
		"and the long-legged one walks it, on the same board"
	)


## The stat resolves through the one resolver, with the part named as a real provenance
## source — not an ad-hoc sum. Read back off `StatResolver` rather than re-derived, so the
## number the tooltip would show is the number the pathfinder used.
func test_step_height_resolves_through_the_stat_resolver_with_provenance() -> void:
	var unit := _make_unit(Vector2i(0, 0), 0.4)
	var context := ResolverContext.new()
	context.base = Unit.BASE_STEP_HEIGHT
	context.parts = unit.shell.operable_parts()
	var resolved: StatValue = StatResolver.resolve(Unit.STEP_HEIGHT_STAT_KEY, context)

	assert_almost_eq(resolved.current, unit.step_height(), 0.0001, "one number, one call")
	assert_eq(resolved.sources.size(), 1, "the leg part is a named source, not an anonymous sum")


## **The invariant runs against the LOWEST step height in play, not a constant.** A rise that
## is free for one unit and a wall for another has to be judged on the worst case, or the
## check certifies boards the shortest-legged unit cannot leave.
func test_the_lowest_step_height_is_what_a_roster_reports() -> void:
	var roster: Array[Unit] = [_make_unit(Vector2i(0, 0), 0.4), _make_unit(Vector2i(1, 0), 0.1)]

	assert_almost_eq(
		Unit.lowest_step_height(roster),
		Unit.BASE_STEP_HEIGHT + 0.1,
		0.0001,
		"the shortest step in the roster is the one the map is judged against"
	)
	assert_almost_eq(
		Unit.lowest_step_height([] as Array[Unit]),
		Unit.BASE_STEP_HEIGHT,
		0.0001,
		"and an empty roster assumes the unmodified body rather than assuming nothing"
	)


# --- the generator -------------------------------------------------------------------


## A generated map passes the asymmetric navigability flood **against the lowest step height
## present**, which is the acceptance the taskblock states. Run at the base height, since no
## authored part carries a `step_height` modifier yet — so the lowest in play *is* the base,
## and this test says which it is rather than leaving it implied.
func test_generated_maps_are_navigable_at_the_lowest_step_height_in_play() -> void:
	var lowest: float = Unit.lowest_step_height([] as Array[Unit])
	for map_seed: int in [2, 9, 4242, 12345, 339963260]:
		var grid: Grid = MapGen.generate(map_seed, 32, 24, lowest)
		var stranded: Array[Vector2i] = MapNavigability.stranding_cells(grid, lowest)
		assert_eq(
			stranded,
			[] as Array[Vector2i],
			"seed %d must have no one-way ground at step height %.2f" % [map_seed, lowest]
		)


## **A stair is what the generator builds now, and it must actually be walkable end to end.**
## Asserted by walking the real board with a real non-climbing pathfinder rather than by
## inspecting authored levels — the levels are the implementation, "you can get up there" is
## the rule.
func test_a_generated_raised_room_is_reachable_by_a_non_climber() -> void:
	var reached_a_raised_cell := false
	for map_seed: int in [2, 4242, 6930958]:
		var grid: Grid = MapGen.generate(map_seed, 32, 24)
		var spawn: Array[Vector2i] = MapNavigability.spawn_cells(grid)
		if spawn.is_empty():
			continue
		var pf := Pathfinder.new(grid)
		for cell: Vector2i in pf.reachable(spawn[0], 9999.0):
			if UnitGeometry.true_height_for_cell(cell, grid) >= 0.9:
				reached_a_raised_cell = true
				break
		if reached_a_raised_cell:
			break
	assert_true(
		reached_a_raised_cell,
		"a unit with no climbing capability must be able to walk onto raised ground"
	)


# --- the editor ----------------------------------------------------------------------


## **The editor's auto-placed terrain is `ship_floor`.** Closed ad hoc after taskblock-59 and
## re-checked here rather than taken on trust, which is this pass's own instruction.
##
## The defect was not a ramp defect at all: the default was `surface_part_ids()[0]`, the
## GROUND-attaching parts sort `[ramp, ship_floor]`, so "the first surface part" had meant
## `ramp` since taskblock-56. **Pinned as a named default rather than an ordering**, so this
## cannot regress by someone authoring a part that sorts earlier.
func test_the_editors_default_floor_is_ship_floor() -> void:
	var module := EditorModule.new()

	assert_eq(
		module.default_floor(),
		&"ship_floor",
		"the editor must author the ordinary floor under a wall, never whatever sorts first"
	)


# --- the guard -----------------------------------------------------------------------


## Nothing references the retired ramp machinery. See `RETIRED_IDENTIFIERS` for why this
## bans three names and not the word.
func test_nothing_references_the_retired_ramp_machinery() -> void:
	var offenders: Array[String] = VocabularySweep.scan(
		[".gd"],
		SELF_PATH,
		func(path: String, line_number: int, line: String) -> String:
			var code: String = line.split("#")[0]
			for identifier: String in RETIRED_IDENTIFIERS:
				if identifier in code:
					return "%s:%d  %s" % [path, line_number, line.strip_edges()]
			return ""
	)

	assert_eq(
		offenders,
		[] as Array[String],
		"retired ramp machinery still referenced:\n%s" % "\n".join(offenders)
	)
