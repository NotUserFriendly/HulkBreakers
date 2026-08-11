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


## A shell with `offers.size()` authored legs, each offering the height at its index.
##
## **The legs are a test fixture on purpose** (CLAUDE.md: "if a test needs a concrete list,
## the *test* authors it"). The shipped library has exactly one leg and it offers 0.4, so
## every claim about *disagreeing* strides needs a leg the library does not ship — and
## inventing a long-legged part in `data/` to satisfy a test would be authoring content to
## fit the test rather than the other way round.
## tb64 audit rebuild: **this file builds bouts and was running them in the fast gate.** It
## predates its own registration in `SuiteTier.BOUT_FILES` — the committed profile had not been
## regenerated since taskblock-56, so nothing could see the bouts it had started building.
##
## Untyped return on purpose, against this project's static-typing rule: GUT declares
## `func should_skip_script():` with no return type, and Godot treats an override that adds
## `-> Variant` as a signature mismatch — the script then fails to parse and GUT reports it as
## "does not extend GutTest", a long way from the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func _make_unit(cell: Vector2i, offers: Array[float] = []) -> Unit:
	var root := Part.new()
	root.id = &"test_torso"
	root.hp = 5
	root.max_hp = 5
	for i in range(offers.size()):
		var leg := Part.new()
		leg.id = StringName("test_leg_%d" % i)
		leg.hp = 5
		leg.max_hp = 5
		leg.stat_mods = {Unit.STEP_HEIGHT_STAT_KEY: offers[i]}
		var socket := Socket.new()
		socket.socket_type = &"HIP"
		socket.id = StringName("HIP_%d" % i)
		socket.occupant = leg
		root.sockets.append(socket)
	return Unit.new(Matrix.new(), Shell.new(root), cell, 0)


## Two ordinary legs at the shipped offer — the body every other test in this file means
## when it says "a default unit".
func _two_legged(cell: Vector2i, offer: float = Unit.BASE_STEP_HEIGHT) -> Unit:
	return _make_unit(cell, [offer, offer] as Array[float])


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
	var ordinary := _two_legged(Vector2i(0, 0))
	var long_legged := _make_unit(Vector2i(0, 0), [0.6, 0.6] as Array[float])
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 0.6)

	gut.p("ordinary %.2f, long-legged %.2f" % [ordinary.step_height(), long_legged.step_height()])
	assert_gt(long_legged.step_height(), ordinary.step_height(), "the longer leg offers more")
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


## **The supervisor's rule, 2026-08-09: the largest offer wins, and the count is irrelevant
## to the height.** A normal leg beside a long one steps the long one's 0.6 — *"because it
## has a max of 0.6, and has a supporting leg at all"*.
##
## **This is the assertion that would have caught the shape being wrong.** Until tb62 the
## stat summed, so this pairing resolved to 0.4 + 0.6 = 1.0 — a whole level walked for free
## — and nothing noticed, because no two parts in the library authored the stat at once.
func test_the_longest_leg_sets_the_stride_and_a_mismatched_pair_takes_the_longer() -> void:
	var mismatched := _make_unit(Vector2i(0, 0), [0.4, 0.6] as Array[float])
	var four_short := _make_unit(Vector2i(0, 0), [0.4, 0.4, 0.4, 0.4] as Array[float])

	gut.p(
		(
			"one 0.4 + one 0.6 steps %.2f; four 0.4 legs step %.2f"
			% [mismatched.step_height(), four_short.step_height()]
		)
	)
	assert_almost_eq(
		mismatched.step_height(), 0.6, 0.0001, "the longer leg sets the stride, it is not added to"
	)
	assert_almost_eq(
		four_short.step_height(),
		Unit.BASE_STEP_HEIGHT,
		0.0001,
		"and leg COUNT buys no height at all — four short legs step exactly what two do"
	)


## **Two legs to step up, or none of the offer is usable.** A single leg has nothing to push
## off, so it resolves to 0.0 rather than to its own offer — an absent capability, not a
## reduced stride.
func test_one_leg_cannot_step_up_at_all() -> void:
	var one_leg := _make_unit(Vector2i(0, 0), [0.6] as Array[float])
	var two_legs := _make_unit(Vector2i(0, 0), [0.6, 0.6] as Array[float])
	var grid := GridFixture.flat(2, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), 0.2)

	gut.p("one leg steps %.2f, two step %.2f" % [one_leg.step_height(), two_legs.step_height()])
	assert_almost_eq(one_leg.step_height(), 0.0, 0.0001, "one leg offers a height it cannot use")
	assert_eq(Unit.LEGS_TO_STEP_UP, 2, "a leg to rise with and a leg to push from")
	assert_almost_eq(
		Pathfinder.for_unit(grid, one_leg).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		-1.0,
		0.0001,
		"so even a 0.2 rise is not an edge for a one-legged shell"
	)
	assert_almost_eq(
		Pathfinder.for_unit(grid, two_legs).move_cost(Vector2i(0, 0), Vector2i(1, 0)),
		Pathfinder.DEFAULT_COST,
		0.0001,
		"and the same shell with a second leg walks it"
	)


## The stat resolves through the one resolver, with every leg named as a real provenance
## source — not an ad-hoc maximum computed beside it. Read back off `StatResolver` rather
## than re-derived, so the number the tooltip would show is the number the pathfinder used.
func test_step_height_resolves_through_the_stat_resolver_with_provenance() -> void:
	var unit := _make_unit(Vector2i(0, 0), [0.4, 0.6] as Array[float])
	var context := ResolverContext.new()
	context.base = 0.0
	context.extra_sources = StatResolver.gather_part_sources(
		Unit.STEP_HEIGHT_STAT_KEY, unit.shell.operable_parts(), Enums.ModOp.MAX
	)
	var resolved: StatValue = StatResolver.resolve(Unit.STEP_HEIGHT_STAT_KEY, context)

	assert_almost_eq(resolved.current, unit.step_height(), 0.0001, "one number, one call")
	assert_eq(resolved.sources.size(), 2, "both legs are named sources, not an anonymous max")
	for source: ModSource in resolved.sources:
		assert_eq(source.op, Enums.ModOp.MAX, "and each is an offer, not a contribution")


# --- the authored part (tb62 Pass A) --------------------------------------------------


## **`leg.tres` authors its own offer, and it is the only part in the library that does.**
## 0.4 — *"almost every robot can step this"* — authored in data rather than inherited from
## `Unit.BASE_STEP_HEIGHT`, so a leg that strides differently is a `.tres` edit and not a
## code edit. The two numbers agreeing today is what makes this pass behaviour-neutral for
## every shipped body; they are not the same fact.
func test_the_shipped_leg_authors_the_step_height_it_offers() -> void:
	var authors: Array[String] = []
	for part: Part in DataLibrary.parts_pool():
		if part.stat_mods.has(Unit.STEP_HEIGHT_STAT_KEY):
			authors.append("%s offers %.2f" % [part.id, part.stat_mods[Unit.STEP_HEIGHT_STAT_KEY]])
	gut.p("library step-height authors: %s" % ", ".join(authors))

	var leg: Part = DataLibrary.get_part(&"leg")
	assert_not_null(leg, "the library ships a leg")
	if leg == null:
		return
	assert_true(leg.stat_mods.has(Unit.STEP_HEIGHT_STAT_KEY), "and the leg authors what it offers")
	assert_almost_eq(
		float(leg.stat_mods[Unit.STEP_HEIGHT_STAT_KEY]),
		0.4,
		0.0001,
		"an ordinary leg offers 0.4 — the height almost every robot can step"
	)


## **The acceptance through the real assembly path**, rather than against a hand-built
## stand-in: a real reference humanoid, built from a real preset, steps the height its real
## legs offer. `PLAN`'s "do the tests approximate things the game already defines?" item is
## why this exists beside the fixture tests rather than instead of them — the fixtures prove
## the *rule*, this proves the shipped body actually goes through it.
func test_a_real_assembled_humanoid_steps_what_its_legs_offer() -> void:
	var laborer: Unit = _unit_from_preset(&"a_brand_laborer")
	assert_not_null(laborer, "the standard laborer preset assembles")
	if laborer == null:
		return

	var offers: Array[ModSource] = StatResolver.gather_part_sources(
		Unit.STEP_HEIGHT_STAT_KEY, laborer.shell.operable_parts(), Enums.ModOp.MAX
	)
	gut.p(
		(
			"a real laborer has %d authored legs and steps %.2f"
			% [offers.size(), laborer.step_height()]
		)
	)
	assert_eq(offers.size(), 2, "a reference humanoid carries two authored legs")
	assert_almost_eq(
		laborer.step_height(),
		Unit.BASE_STEP_HEIGHT,
		0.0001,
		"two 0.4 legs step 0.4 — unchanged from before the stat was authored at all"
	)


## **A shell that authors nothing gets `BASE_STEP_HEIGHT`** — absence is an assumption about
## an unmodified body, never a claim that the body has no legs. This is what keeps every
## hand-built fixture in the suite, and every caller with no roster, behaving as it did.
func test_a_shell_with_no_authoring_gets_the_base_step_height() -> void:
	var bare := _make_unit(Vector2i(0, 0))

	assert_almost_eq(bare.step_height(), Unit.BASE_STEP_HEIGHT, 0.0001, "the unmodified body")


## **What makes the design baseline honest.** `MapGen` authors and repairs every board at
## `DESIGN_STEP_HEIGHT` — the unmodified body — and `MapNavigability.roster_report` skips its
## flood outright for any roster stepping at least that far, on the grounds that such a roster
## can walk every edge a baseline unit can. **That shortcut is exact only while no shipped part
## offers less than the baseline**, so this asserts exactly that and no more.
##
## **When this goes red it is a finding, not a number to tune.** The chassis that steps
## nowhere at all — tracked, legless, the thing `PLAN` says brings ramps back — is a real
## future part, and the day it lands, `roster_report` starts flooding and starts reporting
## boards that squad cannot cross. That is the designed behaviour, not a regression; what this
## test protects is that nobody is *surprised* by it.
func test_no_shipped_part_offers_less_than_the_base_step_height() -> void:
	var shorter: Array[String] = []
	for part: Part in DataLibrary.parts_pool():
		if not part.stat_mods.has(Unit.STEP_HEIGHT_STAT_KEY):
			continue
		var offer: float = float(part.stat_mods[Unit.STEP_HEIGHT_STAT_KEY])
		if offer < Unit.BASE_STEP_HEIGHT:
			shorter.append("%s (%.2f)" % [part.id, offer])

	assert_eq(
		shorter,
		[] as Array[String],
		(
			"a part offering LESS than the base makes BASE_STEP_HEIGHT no longer the worst case, "
			+ (
				"so every roster-less MapGen.generate is certifying against the wrong floor:\n%s"
				% "\n".join(shorter)
			)
		)
	)


func _unit_from_preset(preset_id: StringName) -> Unit:
	var preset: BotPreset = DataLibrary.get_preset(preset_id)
	if preset == null:
		return null
	return DeepStrike.assemble_from_preset(preset, Matrix.new(), Vector2i(0, 0), 0)


## **The invariant runs against the LOWEST step height in play, not a constant.** A rise that
## is free for one unit and a wall for another has to be judged on the worst case, or the
## check certifies boards the shortest-legged unit cannot leave.
func test_the_lowest_step_height_is_what_a_roster_reports() -> void:
	var roster: Array[Unit] = [
		_make_unit(Vector2i(0, 0), [0.8, 0.8] as Array[float]),
		_make_unit(Vector2i(1, 0), [0.5, 0.5] as Array[float]),
	]

	assert_almost_eq(
		Unit.lowest_step_height(roster),
		0.5,
		0.0001,
		"the shortest step in the roster is the one the map is judged against"
	)
	assert_almost_eq(
		Unit.lowest_step_height([_make_unit(Vector2i(0, 0), [0.8] as Array[float])] as Array[Unit]),
		0.0,
		0.0001,
		"and a unit that cannot step up at all drags the roster's floor to zero, honestly"
	)
	assert_almost_eq(
		Unit.lowest_step_height([] as Array[Unit]),
		Unit.BASE_STEP_HEIGHT,
		0.0001,
		"and an empty roster assumes the unmodified body rather than assuming nothing"
	)


# --- the generator -------------------------------------------------------------------


## **The flood judges a map by the shortest step in play, and a map only the tallest unit
## could cross fails it.** One board, two step heights, opposite verdicts — which is the
## whole reason the invariant takes the minimum rather than the default.
##
## The rise is placed strictly between the two authored heights, so the shelf beyond it is
## ordinary ground to a long-legged body and unreachable to a standard one.
func test_the_navigability_flood_uses_the_minimum_and_fails_a_tallest_only_map() -> void:
	var tallest: float = 0.6
	var only_the_tallest: float = (Unit.BASE_STEP_HEIGHT + tallest) * 0.5
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, Vector2i(1, 0), only_the_tallest)
	GridFixture.place_floor(grid, Vector2i(2, 0), only_the_tallest)

	var at_base: Dictionary = MapNavigability.flood(grid, Vector2i(0, 0), Unit.BASE_STEP_HEIGHT)
	var at_tallest: Dictionary = MapNavigability.flood(grid, Vector2i(0, 0), tallest)

	(
		gut
		. p(
			(
				"rise %.2f: flood reaches %d cells at %.2f, %d cells at %.2f"
				% [
					only_the_tallest,
					at_base.size(),
					Unit.BASE_STEP_HEIGHT,
					at_tallest.size(),
					tallest,
				]
			)
		)
	)
	assert_eq(at_base.size(), 1, "at the minimum step height the shelf is not reachable at all")
	assert_eq(at_tallest.size(), 3, "and the tallest unit crosses the identical board")


## **tb65 Pass B's whole point: a seed is the whole address of a board.** Two genuinely
## different rosters, the same bout seed, and the boards must be bit-for-bit the same terrain.
##
## **This test is the reversal of `test_the_generators_step_height_is_load_bearing`**, which
## asserted the opposite — that the same seed must *not* produce the same terraces for two
## strides — and was correct about the code and wrong about the design. `MapGen` sizes a stair
## at `ceil(rise / step_height)`, so while the roster's stride was an input, map 4242 really was
## a different board for a long-legged squad than for a short one. See `SUPERSEDED.md`.
##
## **Different presets, not different fixtures**, because this has to run through the real
## `BoutSetup.build_bout` path — that is where the roster's stride used to be read. The two
## rosters carry different parts, different weapons and different tiers; if any unit feature
## still reached generation, this is where it would show.
func test_the_same_seed_is_the_same_board_for_any_roster() -> void:
	var laborers: Dictionary = BoutSetup.build_bout(
		_roster(&"a_brand_laborer", 2), _roster(&"a_brand_laborer", 2), 771
	)
	var snipers: Dictionary = BoutSetup.build_bout(
		_roster(&"combat_tester_sniper_rifle", 2), _roster(&"combat_tester_chaingun", 2), 771
	)
	assert_eq(laborers.get("error", ""), "", "seed 771 builds a laborer bout")
	assert_eq(snipers.get("error", ""), "", "seed 771 builds a combat-tester bout")
	if laborers.get("error", "") != "" or snipers.get("error", "") != "":
		return

	var a: CombatState = laborers["state"]
	var b: CombatState = snipers["state"]
	gut.p(
		(
			"laborers step %.2f, combat testers step %.2f"
			% [Unit.lowest_step_height(a.units), Unit.lowest_step_height(b.units)]
		)
	)
	assert_eq(
		_height_signature(a.grid),
		_height_signature(b.grid),
		"the same map seed must produce the same terrain whoever is going to play on it"
	)


## **And the board is the one a roster-less generation produces**, read back off the real
## `build_bout` path rather than asserted about the code that calls it.
##
## The test above would still pass if generation were shaped by something *both* rosters
## happen to share. This one pins the board to `MapGen.generate(seed, w, h)` with no roster in
## existence at all, which is the assertion that goes red the moment anyone threads a unit
## feature back into the generator.
func test_a_bouts_map_is_the_one_generated_with_no_roster_at_all() -> void:
	var built: Dictionary = BoutSetup.build_bout(
		_roster(&"a_brand_laborer", 2), _roster(&"a_brand_laborer", 2), 771
	)
	assert_eq(built.get("error", ""), "", "seed 771 builds a bout")
	if built.get("error", "") != "":
		return
	var state: CombatState = built["state"]

	# The same derivation `build_bout` uses: the bout seed drives an RNG whose first draw is
	# the map seed. Re-derived here because nothing else surfaces it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	var expected: Grid = MapGen.generate(rng.randi(), BoutSetup.GRID_WIDTH, BoutSetup.GRID_HEIGHT)

	assert_eq(
		_height_signature(state.grid),
		_height_signature(expected),
		"a bout's board must be exactly what the seed alone generates"
	)


## **A roster that cannot cross a generated board is reported, not engineered away.**
##
## The generator used to take the roster's stride and author terrain the roster could cross, so
## *"a unit cannot reach somewhere"* never occurred in a generated bout — while the
## pace-and-shutdown mitigation, the one-way hop-down awareness and Panic all exist to handle
## exactly that. This asserts the finding is now produced, and — the half that matters — that
## producing it leaves the board **untouched**.
func test_a_roster_that_cannot_cross_is_reported_and_the_board_is_left_alone() -> void:
	var grid: Grid = MapCorpus.read(4242, 32, 24)
	var before: String = _height_signature(grid)
	# One leg resolves to a step height of 0.0 — an absent capability, not a short stride — so
	# this roster cannot make any rise at all. `_two_legged` is the control.
	var cannot: Array[Unit] = [_make_unit(Vector2i(0, 0), [0.6] as Array[float])]
	var can: Array[Unit] = [_two_legged(Vector2i(0, 0))]

	var refused: Dictionary = MapNavigability.roster_report(grid, cannot)
	var certified: Dictionary = MapNavigability.roster_report(grid, can)

	gut.p("one-legged: %s" % refused["summary"])
	gut.p("two-legged: %s" % certified["summary"])
	assert_false(refused["certified"], "a roster that cannot make any rise must not be certified")
	assert_gt(
		(refused["stranded"] as Array[Vector2i]).size(),
		0,
		"and the report must name the ground it cannot leave, not merely say no"
	)
	assert_true(
		certified["certified"],
		"while a roster at the design baseline is covered by the board's own guarantee"
	)
	assert_eq(
		_height_signature(grid),
		before,
		"reporting must not reshape the board — that is the whole difference from tb62"
	)


## Every walkable surface height on the board, row-major, as one comparable string. Heights
## rather than blockers, because the step height only ever moves elevation around — a
## comparison on `blockers` alone would have called two genuinely different terraces equal.
##
## **Read off the placed surfaces, not off the generator's own arithmetic.**
func _height_signature(grid: Grid) -> String:
	var heights: PackedStringArray = []
	for y: int in range(grid.rows):
		for x: int in range(grid.width):
			heights.append("%.2f" % UnitGeometry.true_height_for_cell(Vector2i(x, y), grid))
	return ",".join(heights)


func _roster(preset_id: StringName, count: int) -> Array[BoutRosterEntry]:
	var roster: Array[BoutRosterEntry] = []
	for _i in range(count):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.get_preset(preset_id)
		roster.append(entry)
	return roster


## A generated map passes the asymmetric navigability flood **at the design baseline**, which
## is what the generator promises since tb65 Pass B. It used to be run against "the lowest step
## height in play"; the two are the same number today and they are not the same claim, and the
## generator is only entitled to the narrower one — see `MapGen.DESIGN_STEP_HEIGHT`.
##
## Boards come from `MapCorpus`: read-only, and the corpus already holds seeds 0-49 at this
## size (tb65 Pass A).
func test_generated_maps_are_navigable_at_the_design_baseline() -> void:
	for map_seed: int in [2, 9, 4242, 12345, 339963260]:
		var grid: Grid = MapCorpus.read(map_seed, 32, 24)
		var stranded: Array[Vector2i] = MapNavigability.stranding_cells(
			grid, MapGen.DESIGN_STEP_HEIGHT
		)
		assert_eq(
			stranded,
			[] as Array[Vector2i],
			(
				"seed %d must have no one-way ground at the design baseline %.2f"
				% [map_seed, MapGen.DESIGN_STEP_HEIGHT]
			)
		)


## **A stair is what the generator builds now, and it must actually be walkable end to end.**
## Asserted by walking the real board with a real non-climbing pathfinder rather than by
## inspecting authored levels — the levels are the implementation, "you can get up there" is
## the rule.
func test_a_generated_raised_room_is_reachable_by_a_non_climber() -> void:
	var reached_a_raised_cell := false
	for map_seed: int in [2, 4242, 6930958]:
		var grid: Grid = MapCorpus.read(map_seed, 32, 24)
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
