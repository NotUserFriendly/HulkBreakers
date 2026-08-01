extends GutTest

## taskblock-52 Pass A2: **the shot plane does not amortise across a burst, and the
## whole cost case for keeping it rests on the belief that it does.**
##
## The trade the ray chain is weighed against was stated as: *one build serves a
## whole burst, then N cheap point-in-rect tests, where a ray chain pays per round.*
## That is not what the code does. `DamageResolver.resolve_shot` builds its **own**
## plane on entry — every pull, every pellet, and every ricochet hop, each of which
## recurses into another `resolve_shot` and therefore another build. The plane
## `BurstAction` builds up front is used only to pick the aim point.
##
## Measured on a real 217-blocker board (`tools/shot_cost_bench.gd`): a 12-round
## chaingun burst builds **20 planes**, at roughly 8.5 ms each, for ~183 ms of
## resolution. The plane walk itself is noise — about 260 usec against an 8 500 usec
## build, so **~97% of a shot's cost is building the plane it then barely uses.**
##
## This file pins the *count*, not the timing. A count is deterministic, machine
## independent and names its own cause, which is the same reasoning `SuiteBudget`
## is built on.

const AIM_HEIGHT := 1.25


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.material = &"steel"
	torso.hp = 40
	torso.max_hp = 40
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _target(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"target_torso"
	torso.material = &"steel"
	torso.hp = 400
	torso.max_hp = 400
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.8, 1.6, 0.5))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _state() -> CombatState:
	var grid: Grid = GridFixture.enclosed_room(21, 21)
	return CombatState.new(grid, [_shooter(Vector2i(5, 10)), _target(Vector2i(15, 10))])


func _fire_one(state: CombatState) -> void:
	var shooter: Unit = state.units[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	DamageResolver.resolve_shot(
		Vector2(shooter.cell),
		Vector2(1, 0),
		Vector2(0.0, AIM_HEIGHT),
		0.0,
		0.0,
		state,
		state.material_table,
		rng,
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		shooter.shell.all_parts_with_joints()
	)


## The fact itself: **one projectile, one plane.** Nothing is shared between two
## rounds fired down the same line on the same turn.
func test_every_projectile_builds_its_own_plane() -> void:
	var state: CombatState = _state()
	for rounds in [1, 5, 12]:
		var before: int = ShotPlane.builds
		for _i in range(rounds):
			_fire_one(state)
		var built: int = ShotPlane.builds - before
		print("%2d rounds down one line -> %2d plane builds" % [rounds, built])
		assert_eq(
			built,
			rounds,
			(
				(
					"%d identical rounds built %d planes — the amortisation the plane is "
					% [rounds, built]
				)
				+ "credited with would make this 1"
			)
		)


## The other half of the same fact: the walk the plane exists to make cheap is not
## where the time goes. Asserted as a *structural* property rather than a timing —
## the plane holds every region on the board, and a single shot inspects only the
## ones its own point falls in.
func test_a_shot_builds_far_more_regions_than_it_ever_inspects() -> void:
	var state: CombatState = _state()
	var shooter: Unit = state.units[0]
	var plane: Array[Region] = ShotPlane.build(
		Vector3(shooter.cell.x, AIM_HEIGHT, shooter.cell.y), Vector3(1, 0, 0), state
	)
	var point := Vector2(0.0, AIM_HEIGHT)
	var containing := 0
	for region: Region in plane:
		if region.depth >= 0.0 and region.rect.has_point(point):
			containing += 1
	print(
		(
			"plane holds %d regions; %d of them contain the aim point (%.2f%%)"
			% [plane.size(), containing, 100.0 * float(containing) / float(plane.size())]
		)
	)
	# This fixture is a bare 21x21 room: 80 perimeter walls and two simple bodies.
	# A real generated board measured **1291 regions** for the same single point
	# (`tools/shot_cost_bench.gd`, 217 blockers), so the ratio here is the
	# conservative end of the effect, not the dramatic one.
	assert_gt(plane.size(), 50, "even a bare room projects a plane of real size")
	assert_lt(
		float(containing) / float(plane.size()),
		0.1,
		"a shot uses a tiny fraction of what its plane cost to build"
	)


## A ricochet is a fresh `resolve_shot`, so it is a fresh plane — which is why the
## measured burst count (20) exceeded the round count (12).
##
## **Swept rather than staged, and asserted against vacuity**, because the first
## version of this test fired one round that happened to `STOP_DEAD`, counted zero
## deflections, and passed a `builds == 1 + 0` assertion that proved nothing about
## ricochets at all. That is the exact "green beside a live defect" shape this
## project keeps finding, so the sweep now has to produce both cases or fail.
func test_a_deflection_builds_another_plane_and_a_stopped_round_does_not() -> void:
	var state: CombatState = _state()
	var shooter: Unit = state.units[0]
	var stopped_cases := 0
	var deflected_cases := 0

	for step in range(0, 10):
		var lateral: float = float(step)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var before: int = ShotPlane.builds
		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			Vector2(shooter.cell),
			Vector2(1, 0),
			Vector2(lateral, AIM_HEIGHT),
			4.0,  # under steel's DT, so the round can never simply punch through
			0.0,
			state,
			state.material_table,
			rng,
			0,
			DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
			DamageResolver.DEFAULT_DAMAGE_FLOOR,
			DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
			shooter.shell.all_parts_with_joints()
		)
		var built: int = ShotPlane.builds - before
		var deflects := 0
		for result: ImpactResult in results:
			if result.outcome == Enums.Outcome.DEFLECT:
				deflects += 1
		print(
			(
				"  lateral %4.1f: %d hop(s), %d deflect(s) -> %d plane build(s)"
				% [lateral, results.size(), deflects, built]
			)
		)
		if results.is_empty():
			continue
		if deflects == 0:
			stopped_cases += 1
			assert_eq(
				built, 1, "lateral %.1f: a round that stops builds exactly one plane" % lateral
			)
		else:
			deflected_cases += 1
			assert_gt(
				built,
				1,
				"lateral %.1f: a deflection must build a plane for its new heading" % lateral
			)

	assert_gt(stopped_cases, 0, "the sweep must actually produce a stopped round")
	assert_gt(
		deflected_cases,
		0,
		"the sweep must actually produce a deflection — otherwise this test asserts nothing"
	)
