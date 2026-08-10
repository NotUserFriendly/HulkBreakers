extends GutTest

## taskblock-52 Pass A2: **the seam baseline, re-taken — and the recorded
## diagnosis overturned by re-taking it.**
##
## `BR34.05` and `PLAN.md`'s *Wide scatter passing through a wall seam* both rest
## on one number, **56/200 empties at a lateral offset of ~8**, measured in
## taskblock-35 by a harness that was never committed. This file makes that
## experiment rerunnable, which is the whole reason Pass A takes a baseline before
## anything changes.
##
## ## The number reproduces exactly. The explanation attached to it does not.
##
## Both living documents record the cause as a projection artifact: *"adjacent
## cells' projected rects are not guaranteed to cell edge-to-edge from an
## arbitrary shooter angle, so a sufficiently wide lateral offset can thread a
## real gap between them."* Three measurements below say otherwise.
##
## 1. **The empties appear at exactly the wall line, not at a seam.** Sweeping one
##    axis in 0.25 steps, every offset up to 5.25 hits and every offset from 5.50
##    out misses — and 5.5 is precisely where the perimeter wall's own box ends
##    (`wall` is a full-cell cube, so the wall at row 10 spans 9.5 to 10.5, and the
##    shooter stands at row 5).
## 2. **The vanishing rounds begin their flight outside the building.**
##    `DamageResolver` tests every region at a *constant* lateral offset, so the
##    modelled flight is `origin + perp * point.x + dir * t` — a ray **parallel**
##    to the shooter-to-target line, translated sideways by the whole dartboard
##    offset. A wide offset therefore relocates the entire round, muzzle included,
##    past the wall and off the board. It does not thread the wall; it never
##    reaches it.
## 3. **A room big enough to hold every swept offset produces no empties at all** —
##    3 690 samples, 90 angles, offsets to 15, every one of them well inside the
##    walls. A rect-tiling seam would show up here, and there is none. (The first
##    run of this used 180 angles and 61 offsets for 10 980 samples, also zero; it
##    was trimmed because the negative result is already comfortable and the wide
##    version cost the suite 27 s a run.)
##
## **So the defect is in how scatter is modelled, not in how walls are
## projected**, and the ray chain fixes it by construction rather than by
## patching: A is the real muzzle, B is the aimed point, and a march from A to B
## diverges from the gun the way a real round does.

const ROOM := 11
const BIG_ROOM := 41
const AIM_HEIGHT := 1.0
## What the recorded experiment measured, reproduced. **This figure is expected to
## go to zero under the ray chain — that is the deliverable, not a regression.**
## The plane survives taskblock-52 (Pass F does not delete it), so this assertion
## keeps describing the plane after the ray chain becomes the default.
const RECORDED_EMPTIES := 56


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.material = &"steel"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _centre(room: int) -> Vector2i:
	@warning_ignore("integer_division")
	var half: int = room / 2
	return Vector2i(half, half)


func _state(room: int) -> CombatState:
	return CombatState.new(GridFixture.enclosed_room(room, room), [_shooter(_centre(room))])


## The plane resolver, as the sweep's `fire` — the exact call
## `ShotResolution.resolve_and_log_point` makes, minus the logging, so what is
## measured is production resolution rather than a re-derivation of it.
func _plane_fire(state: CombatState, damage: float = 0.0) -> Callable:
	var results_of: Callable = _plane_results(state, damage)
	return func(origin: Vector2, direction: Vector2, point: Vector2) -> bool:
		return not (results_of.call(origin, direction, point) as Array).is_empty()


func _plane_results(state: CombatState, damage: float = 0.0) -> Callable:
	var shooter: Unit = state.units[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	return func(origin: Vector2, direction: Vector2, point: Vector2) -> Array[ImpactResult]:
		return DamageResolver.resolve_shot(
			origin,
			direction,
			point,
			damage,
			0.0,
			state,
			state.material_table,
			rng,
			0,
			DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
			DamageResolver.DEFAULT_DAMAGE_FLOOR,
			DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
			excluded
		)


func _wall_hp_total(grid: Grid) -> int:
	var total := 0
	for cell: Vector2i in grid.blockers:
		total += (grid.blocker_part_at(cell) as Part).hp
	return total


## The recorded experiment, reproduced to the shot. An unreproduced number is not
## a baseline — and this one turned out to be reproducible only in a room of one
## particular size, which is itself the first clue that it measures the room
## rather than the wall.
func test_the_recorded_seam_measurement_reproduces_exactly() -> void:
	var state: CombatState = _state(ROOM)
	var report: Dictionary = (
		SeamSweep
		. run(
			Vector2(_centre(ROOM)),
			{
				"angles": SeamSweep.LEGACY_ANGLES,
				"lateral_samples": SeamSweep.LEGACY_LATERAL_SAMPLES,
				"lateral_max": SeamSweep.LEGACY_LATERAL_MAX,
				"height": AIM_HEIGHT,
			},
			_plane_fire(state)
		)
	)
	print(SeamSweep.describe(report, "shot plane, taskblock-35 shape, %d-room" % ROOM))

	assert_eq(report["shots"], 200, "the recorded experiment fired 200 shots")
	assert_eq(
		report["empties"],
		RECORDED_EMPTIES,
		"taskblock-35 recorded 56/200 empties; this is that experiment re-run"
	)


## **Finding 1: the threshold is the wall's own face, not a seam.** A seam between
## independently projected rects would produce scattered empties at assorted
## offsets and angles; what actually happens is a single clean edge, and it sits
## exactly where the perimeter wall box stops.
func test_empties_begin_exactly_where_the_perimeter_wall_box_ends() -> void:
	var state: CombatState = _state(ROOM)
	var fire: Callable = _plane_fire(state)
	var centre: Vector2i = _centre(ROOM)
	# `wall`'s volume is a full 1.0-wide cell cube, so the far perimeter row
	# (row ROOM-1) spans from (ROOM-1) - 0.5 to (ROOM-1) + 0.5 in world units.
	var wall_outer_face: float = float(ROOM - 1) + 0.5 - float(centre.y)

	var last_hit: float = -1.0
	var first_miss: float = -1.0
	for i in range(0, 41):
		var lateral: float = float(i) * 0.25
		var hit: bool = fire.call(Vector2(centre), Vector2(1, 0), Vector2(lateral, AIM_HEIGHT))
		if hit:
			last_hit = lateral
		elif first_miss < 0.0:
			first_miss = lateral
	print(
		(
			"last hit at lateral %.2f, first miss at %.2f; the wall's outer face is at %.2f"
			% [last_hit, first_miss, wall_outer_face]
		)
	)
	assert_lt(last_hit, wall_outer_face, "every hit lands within the wall's own box")
	assert_gte(first_miss, wall_outer_face, "nothing misses while still inside the wall")
	assert_almost_eq(
		first_miss,
		wall_outer_face,
		0.25,
		"the miss threshold IS the wall face — a seam would not land on it"
	)


## **Finding 2: the mechanism.** The plane resolves a scattered round as a ray
## parallel to the shooter-to-target line, offset sideways by the full dartboard
## displacement — so the flight of a wide-offset round starts outside the room
## rather than at the gun. This asserts the consequence directly (the start point
## is off the board) rather than re-deriving the formula that produces it.
func test_a_vanishing_round_begins_its_flight_outside_the_building() -> void:
	var state: CombatState = _state(ROOM)
	var results_of: Callable = _plane_results(state)
	var centre: Vector2i = _centre(ROOM)
	var direction := Vector2(1, 0)
	var perp := Vector2(-direction.y, direction.x)

	for lateral in [0.0, 4.0, 6.0, 8.0]:
		var results: Array = results_of.call(
			Vector2(centre), direction, Vector2(lateral, AIM_HEIGHT)
		)
		var start: Vector2 = Vector2(centre) + perp * lateral
		var in_bounds: bool = state.grid.in_bounds(Vector2i(roundi(start.x), roundi(start.y)))
		print(
			(
				"  lateral %4.1f: flight starts (%.2f, %.2f) in_bounds=%s -> %d impact(s)"
				% [lateral, start.x, start.y, str(in_bounds), results.size()]
			)
		)
		assert_eq(
			results.is_empty(),
			not in_bounds,
			(
				"lateral %.1f: a round vanishes exactly when its own modelled flight " % lateral
				+ "starts off the board — that is the defect, not a gap between walls"
			)
		)


## **Finding 3: there is no rect-tiling seam to find.** Every offset swept here
## stays well inside the walls, so nothing can vanish by being aimed outside the
## building; if adjacent wall cells failed to cell edge-to-edge from an arbitrary
## angle, 90 angles across several thousand samples is where it would show.
func test_a_room_large_enough_to_hold_every_offset_produces_no_empties() -> void:
	var state: CombatState = _state(BIG_ROOM)
	var report: Dictionary = (
		SeamSweep
		. run(
			Vector2(_centre(BIG_ROOM)),
			{
				"angles": 90,
				"lateral_samples": 41,
				"lateral_max": 15.0,
				"height": AIM_HEIGHT,
				"bands": 5,
			},
			_plane_fire(state)
		)
	)
	print(
		SeamSweep.describe(report, "shot plane, %d-room, every offset inside the walls" % BIG_ROOM)
	)
	assert_eq(
		report["empties"],
		0,
		(
			"no empties with every offset inside the walls — the recorded "
			+ "'adjacent rects do not cell edge-to-edge' cause is not measurable"
		)
	)


## **The probe must not consume the thing it measures.** A sweep that damaged the
## walls would be measuring a different, holier room by its fiftieth shot, and its
## empties would be real breaches rather than the effect under study. This is what
## licenses the zero-damage default documented on `SeamSweep`.
func test_the_sweep_leaves_the_room_it_measured_intact() -> void:
	var state: CombatState = _state(ROOM)
	var before: int = _wall_hp_total(state.grid)
	SeamSweep.run(
		Vector2(_centre(ROOM)),
		{"angles": 12, "lateral_samples": 9, "lateral_max": 8.0, "height": AIM_HEIGHT},
		_plane_fire(state)
	)
	assert_eq(_wall_hp_total(state.grid), before, "a zero-damage probe changes no wall's hp")


## The sweep is an instrument, so its own determinism is load-bearing: a figure
## that moves run to run cannot be a baseline for anything.
func test_the_sweep_reports_the_same_figure_twice() -> void:
	var config := {"angles": 12, "lateral_samples": 9, "lateral_max": 8.0, "height": AIM_HEIGHT}
	var first: Dictionary = SeamSweep.run(Vector2(_centre(ROOM)), config, _plane_fire(_state(ROOM)))
	var second: Dictionary = SeamSweep.run(
		Vector2(_centre(ROOM)), config, _plane_fire(_state(ROOM))
	)
	assert_eq(first["empties"], second["empties"], "same room, same sweep, same count")
	assert_eq(first["shots"], second["shots"])


## A guard on the fixture rather than on the resolver. Every empty this sweep
## reports is attributed to the resolver, which is only honest if the room is
## genuinely sealed — so the seal is asserted directly instead of assumed.
func test_the_enclosed_room_has_a_wall_on_every_perimeter_cell() -> void:
	var grid: Grid = GridFixture.enclosed_room(ROOM, ROOM)
	for x in range(ROOM):
		for y in range(ROOM):
			var cell := Vector2i(x, y)
			var on_edge: bool = x == 0 or y == 0 or x == ROOM - 1 or y == ROOM - 1
			assert_eq(grid.blockers.has(cell), on_edge, "cell %s: perimeter iff blocker" % cell)


## `_lateral_at` is arithmetic the whole measurement rests on — an off-by-one in
## it would silently narrow or widen the swept range and move every figure this
## file prints.
func test_lateral_samples_span_the_full_signed_range_inclusive() -> void:
	assert_almost_eq(SeamSweep._lateral_at(0, 5, 8.0), -8.0, 0.0001)
	assert_almost_eq(SeamSweep._lateral_at(2, 5, 8.0), 0.0, 0.0001)
	assert_almost_eq(SeamSweep._lateral_at(4, 5, 8.0), 8.0, 0.0001)
	assert_almost_eq(SeamSweep._lateral_at(0, 1, 8.0), 0.0, 0.0001, "a lone sample is centred")
