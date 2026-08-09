extends GutTest

## tb62 Pass B: **the mag lift — the third route up, and the only one that spends AP.**
##
## Steps need a short rise and cost MP; ladders need MP and are slow; a lift is instant and
## costs an action. The tests below are about what makes it a real alternative rather than a
## strictly better option: it takes AP, it refuses out loud, it obstructs nothing, and the
## generator stands it where it would otherwise have stood a ladder.

const PAD := &"mag_lift_pad"
const LOWER := Vector2i(0, 0)
const UPPER := Vector2i(1, 0)
const RISE: float = 2.0


## A two-cell board: `LOWER` at ground, `UPPER` a `RISE` ledge, a lift pad on each.
##
## Built through `GridPlacement` rather than by writing into `Grid.surfaces` directly, so
## these tests exercise the same attachment grammar the generator is held to — a pad the
## grammar would refuse must fail here too, not quietly work in a fixture.
func _lift_grid() -> Grid:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, UPPER, RISE)
	GridPlacement.place(grid, LOWER, DataLibrary.get_part(PAD).duplicate(true), 0.0)
	GridPlacement.place(grid, UPPER, DataLibrary.get_part(PAD).duplicate(true), RISE)
	return grid


func _unit_on(grid: Grid, cell: Vector2i) -> Dictionary:
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, 0)
	var state := CombatState.new(grid, [unit] as Array[Unit], 1)
	return {"state": state, "unit": state.units[0]}


# --- the ride ------------------------------------------------------------------------


## **The acceptance: step onto the lower pad, spend 1 AP, be on the upper one.** A teleport
## between the pair — the unit's cell AND its real height both move, because a lift that
## changed the cell and left the height behind would put the body inside the ledge.
func test_riding_the_lift_costs_one_ap_and_places_the_unit_on_the_upper_pad() -> void:
	var grid: Grid = _lift_grid()
	var staged: Dictionary = _unit_on(grid, LOWER)
	var state: CombatState = staged["state"]
	var unit: Unit = staged["unit"]
	var ap_before: int = unit.ap
	var mp_before: float = unit.mp

	var action := MagLiftAction.new(unit)
	assert_true(action.is_legal(state), "a unit standing on the lower pad may ride")
	action.apply(state)

	gut.p(
		(
			"rode from %s (h %.2f) to %s (h %.2f); AP %d -> %d, MP %.1f -> %.1f"
			% [LOWER, 0.0, unit.cell, unit.height, ap_before, unit.ap, mp_before, unit.mp]
		)
	)
	assert_eq(unit.cell, UPPER, "the unit is on the upper pad's cell")
	assert_almost_eq(unit.height, RISE, 0.0001, "and at the ledge's own real height")
	assert_eq(unit.ap, ap_before - MagLiftAction.AP_COST, "one AP, and only one")
	assert_almost_eq(unit.mp, mp_before, 0.0001, "and no MP at all — that is the whole point")
	assert_eq(state.grid.get_occupant_id(UPPER), unit.id, "the board agrees about where it is")
	assert_eq(state.grid.get_occupant_id(LOWER), -1, "and the cell it left is free")


## **It is a teleport, not a traversal**, so the pathfinder must not have grown an edge for
## it. A lift that showed up as a cheap `move_cost` would be a second mover inside the one
## that already exists — and the AI would route through it as though it were walking.
func test_the_pathfinder_knows_nothing_about_the_lift() -> void:
	var grid: Grid = _lift_grid()
	var staged: Dictionary = _unit_on(grid, LOWER)
	var pf := Pathfinder.for_unit(grid, staged["unit"])

	gut.p("lift edge cost: %.1f" % pf.move_cost(LOWER, UPPER))
	assert_almost_eq(
		pf.move_cost(LOWER, UPPER),
		-1.0,
		0.0001,
		"a 2.0 rise with no ladder is not a walkable edge, pads or no pads"
	)
	assert_eq(pf.astar(LOWER, UPPER), [] as Array[Vector2i], "and no route walks up it")


## **The refusal names its gate.** `PLAN`'s own bare-boolean item: a unit standing on a
## visible pad with nothing happening is exactly the unactionable silence that costs
## taskblocks to diagnose. Every gate reports which one it was, and `is_legal` is derived
## from the same call so the two cannot disagree.
func test_a_lift_with_no_ap_refuses_and_says_why() -> void:
	var grid: Grid = _lift_grid()
	var staged: Dictionary = _unit_on(grid, LOWER)
	var state: CombatState = staged["state"]
	var unit: Unit = staged["unit"]
	unit.ap = 0

	var action := MagLiftAction.new(unit)
	gut.p("refusal at 0 AP: %s" % action.refusal_reason(state))
	assert_eq(
		action.refusal_reason(state),
		MagLiftAction.REFUSAL_NO_AP,
		"an unaffordable ride says it is unaffordable"
	)
	assert_false(action.is_legal(state), "and the boolean agrees with the reason")


## Standing nowhere near a pad is a different refusal from being unable to pay for one.
## Asserted because a single "no" collapses them, which is the defect the reasons exist for.
func test_standing_off_the_pad_is_a_different_refusal_from_being_broke() -> void:
	var grid: Grid = _lift_grid()
	var staged: Dictionary = _unit_on(grid, Vector2i(2, 0))
	var action := MagLiftAction.new(staged["unit"])

	assert_eq(
		action.refusal_reason(staged["state"]),
		MagLiftAction.REFUSAL_NO_PAD,
		"no pad underfoot is its own answer, not 'not enough AP'"
	)


## A lone pad is a route that promises a way up and has none. The generator refuses to build
## one (`MapGen._stamp_mag_lift` clears both ends first), and the action names it if one ever
## reaches the board another way — an authored map may be broken on purpose.
func test_a_pad_with_no_partner_refuses_by_name() -> void:
	var grid := GridFixture.flat(3, 1)
	GridFixture.place_floor(grid, UPPER, RISE)
	GridPlacement.place(grid, LOWER, DataLibrary.get_part(PAD).duplicate(true), 0.0)
	var staged: Dictionary = _unit_on(grid, LOWER)

	assert_eq(
		MagLiftAction.new(staged["unit"]).refusal_reason(staged["state"]),
		MagLiftAction.REFUSAL_NO_DESTINATION,
		"a pad whose pair was never placed says so"
	)


## **The lift rides down for the same AP it rides up**, which is the supervisor's call of
## 2026-08-09 and a reversal of this file's first version.
##
## What separates a ride from a hop-down is **availability, not direction**: a hop-down works
## off any ledge anywhere, a lift works only at the two cells someone built it on. So a
## descending ride is not a lift muscling in on free descent — it is the pair doing the one
## job it has, in the direction the rider needs.
##
## The descent is asserted as the exact inverse of the ascent, from the same fixture, because
## "it also goes down" is a claim about the pair being symmetric rather than about a second
## mechanism existing.
func test_the_lift_rides_back_down_for_the_same_one_ap() -> void:
	var grid: Grid = _lift_grid()
	var staged: Dictionary = _unit_on(grid, UPPER)
	var state: CombatState = staged["state"]
	var unit: Unit = staged["unit"]
	var ap_before: int = unit.ap

	assert_eq(
		Surface.mag_lift_destination(grid, UPPER), LOWER, "the upper pad's partner is the lower"
	)
	var action := MagLiftAction.new(unit)
	assert_true(action.is_legal(state), "a unit on the upper pad may ride down")
	action.apply(state)

	gut.p("rode down to %s at height %.2f for %d AP" % [unit.cell, unit.height, ap_before - unit.ap])
	assert_eq(unit.cell, LOWER, "the descent lands on the lower pad's cell")
	assert_almost_eq(unit.height, 0.0, 0.0001, "at the low floor's own height")
	assert_eq(unit.ap, ap_before - MagLiftAction.AP_COST, "for the same single AP the ride up costs")


## **A ride is worth an action only where one was built**, and that is the whole of what makes
## it fair against a hop-down that works off any ledge. Stated as a test because the balance
## claim is easy to read as "the lift is cheaper", which the raw numbers do not support for a
## short drop — see `Surface.mag_lift_destination`'s own note.
func test_a_hop_down_needs_no_lift_and_a_ride_needs_one() -> void:
	var bare := GridFixture.flat(3, 1)
	GridFixture.place_floor(bare, UPPER, RISE)
	var staged: Dictionary = _unit_on(bare, UPPER)

	assert_null(
		Surface.mag_lift_destination(bare, UPPER),
		"an ordinary ledge with no pads on it offers no ride at all"
	)
	assert_eq(
		MagLiftAction.new(staged["unit"]).refusal_reason(staged["state"]),
		MagLiftAction.REFUSAL_NO_PAD,
		"and the refusal names the absence rather than the direction"
	)


# --- it is not a wall ----------------------------------------------------------------


## **Neither surface blocks a shot through its cell**, and it is structural rather than
## measured-thin: `mag_lift_pad` authors no `volume`, so there is no box for a ray to meet.
##
## Asserted by marching a real ray across both pads' cells with `RayCaster.obstructed` —
## the same call line-of-fire uses — rather than by inspecting the part, so this stays true
## if the pad ever grows geometry by accident.
func test_neither_pad_obstructs_a_shot_crossing_its_cell() -> void:
	var grid: Grid = _lift_grid()
	var chest: float = 1.0

	var across_lower: bool = RayCaster.obstructed(
		grid, Vector3(-1.0, chest, 0.0), Vector3(0.5, chest, 0.0)
	)
	var across_upper: bool = RayCaster.obstructed(
		grid, Vector3(1.0, RISE + chest, 0.0), Vector3(1.6, RISE + chest, 0.0)
	)

	gut.p("obstructed across lower pad: %s, across upper pad: %s" % [across_lower, across_upper])
	assert_false(across_lower, "the lower pad is a platform, not a wall")
	assert_false(across_upper, "and so is the upper one")


## The other half of the same claim, stated about the geometry itself: a pad contributes no
## box placements at all, so nothing downstream — ray marching, the shot plane, the board's
## own tile mesh — has anything to find.
func test_a_pad_contributes_no_geometry_at_all() -> void:
	var pad: Part = DataLibrary.get_part(PAD)

	assert_not_null(pad, "the library ships a mag lift pad")
	if pad == null:
		return
	assert_eq(pad.volume, [] as Array[Box], "a pad authors no boxes")
	assert_eq(
		UnitGeometry.assembly_placements(pad, LOWER, 0.0, null, 0.0).size(),
		0,
		"so it places no geometry on the board"
	)
	assert_false(
		Surface.WALKABLE_TAG in pad.tags,
		"and it is not walkable — standing is the floor's job, not the marker's"
	)


## **A shot fired from the upper pad originates up there.** The unit's real firing height
## follows it through the lift, so a rider gains the elevation it paid for. Read back off
## `UnitGeometry.muzzle_point` — the real muzzle on the real assembled body — rather than
## from `unit.height` plus an assumed shoulder offset.
func test_a_shot_from_the_upper_pad_originates_at_the_upper_height() -> void:
	var grid: Grid = _lift_grid()
	var staged: Dictionary = _unit_on(grid, LOWER)
	var state: CombatState = staged["state"]
	var unit: Unit = staged["unit"]
	var weapon: Part = DeepStrike.find_operable_weapon(unit)
	if weapon == null:
		fail_test("the reference humanoid must carry a weapon for this to mean anything")
		return

	var before: float = UnitGeometry.muzzle_point(unit, weapon).y
	MagLiftAction.new(unit).apply(state)
	var after: float = UnitGeometry.muzzle_point(unit, weapon).y

	gut.p("muzzle Y %.2f -> %.2f after riding a %.1f lift" % [before, after, RISE])
	assert_almost_eq(
		after - before, RISE, 0.0001, "the muzzle rose by exactly the lift's own rise"
	)


# --- the generator -------------------------------------------------------------------


## **The generator stands a lift where it would have stood a ladder** — same slot, same job,
## different currency. Measured across a seed sweep rather than pinned to one seed: which
## fixture a given repaired cell gets is a coin flip on `LIFT_SHARE`, so a single seed would
## be a re-pick treadmill (`PLAN`: pinning tests and sampling tests are different things).
func test_generated_maps_stand_lifts_where_ladders_would_go() -> void:
	var with_lifts := 0
	var pads := 0
	var ladders := 0
	for map_seed: int in [1, 2, 3, 4, 5, 9, 4242, 12345]:
		var grid: Grid = MapGen.generate(map_seed, 32, 24)
		var seed_pads := 0
		for surface: Surface in grid.placements():
			if Surface.MAG_LIFT_TAG in surface.part.tags:
				seed_pads += 1
			elif Surface.LADDER_TAG in surface.part.tags:
				ladders += 1
		pads += seed_pads
		if seed_pads > 0:
			with_lifts += 1
	gut.p("%d of 8 seeds carry a lift; %d pads and %d ladder segments in total" % [
		with_lifts, pads, ladders
	])

	assert_gt(pads, 0, "some generated route up must be a lift, or the branch is unreachable")
	assert_eq(pads % 2, 0, "and every pad is placed as half of a pair, never alone")


## **Every generated pad resolves to a partner, and the pairing is mutual.** A half-lift is
## worse than no lift — it reads as a route and is not one — and now that a ride runs both
## ways, "mutual" is the real invariant: whatever A rides to must ride back to A.
func test_every_generated_pad_pairs_with_one_that_pairs_back() -> void:
	var broken: Array[String] = []
	var pairs := 0
	for map_seed: int in [1, 2, 3, 4, 5, 9, 4242, 12345]:
		var grid: Grid = MapGen.generate(map_seed, 32, 24)
		for surface: Surface in grid.placements():
			if not Surface.MAG_LIFT_TAG in surface.part.tags:
				continue
			var partner: Variant = Surface.mag_lift_destination(grid, surface.cell)
			if partner == null:
				broken.append("seed %d: %s has no partner" % [map_seed, surface.cell])
				continue
			if Surface.mag_lift_destination(grid, partner as Vector2i) != surface.cell:
				broken.append(
					(
						"seed %d: %s rides to %s, which rides somewhere else"
						% [map_seed, surface.cell, partner]
					)
				)
				continue
			pairs += 1
	gut.p("%d mutually paired pads, %d broken" % [pairs, broken.size()])

	assert_eq(
		broken,
		[] as Array[String],
		"a pad whose partner does not ride back is a one-way trip nobody authored:\n%s"
		% "\n".join(broken)
	)


## **A repair with no RNG still stamps a ladder.** The editor and every test calling
## `guarantee_navigability` directly hand in no randomness, and a repair that varied by
## whether its caller happened to have some would be one nobody could reproduce.
func test_a_repair_with_no_rng_is_still_a_ladder() -> void:
	var grid := GridFixture.flat(4, 3)
	for y: int in range(3):
		GridFixture.place_floor(grid, Vector2i(3, y), RISE)

	MapGen.guarantee_navigability(grid, Unit.BASE_STEP_HEIGHT)

	var pads := 0
	for surface: Surface in grid.placements():
		if Surface.MAG_LIFT_TAG in surface.part.tags:
			pads += 1
	assert_eq(pads, 0, "no RNG, no lifts — the deterministic caller's behaviour is unchanged")
