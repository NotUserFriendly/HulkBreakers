extends GutTest

## taskblock-52 hard pause: **the parity evidence, run as a test so it can be
## re-taken rather than quoted.**
##
## Four things the taskblock asks for before the ray chain may become the default:
## the seam sweep through both models, a differential over the same seeded shots
## with every disagreement explicable, determinism, and traversal order being
## geometric rather than dictionary order. Cost is the fifth and lives in
## `tools/shot_cost_bench.gd`, because it needs a release build.

const ROOM := 11
const BIG_ROOM := 41
const AIM_HEIGHT := 1.0


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"shooter_torso"
	torso.material = &"steel"
	torso.hp = 40
	torso.max_hp = 40
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _centre(room: int) -> Vector2i:
	@warning_ignore("integer_division")
	var half: int = room / 2
	return Vector2i(half, half)


func _state(room: int, resolver: StringName) -> CombatState:
	var state := CombatState.new(GridFixture.enclosed_room(room, room), [_shooter(_centre(room))])
	state.shot_resolver = resolver
	return state


func _fire(state: CombatState) -> Callable:
	var shooter: Unit = state.units[0]
	return func(origin: Vector2, direction: Vector2, point: Vector2) -> bool:
		return not (
			ShotResolution
			. resolve_point(
				state,
				shooter,
				origin,
				direction,
				point,
				0.0,
				0.0,
				0.0,
				AIM_HEIGHT,
				DamageResolver.DEFLECT_MODE_RICOCHET,
				0.0,
				0.0,
				0.0
			)
			. is_empty()
		)


## **The ray chain is the default. The flip landed in taskblock-52 Pass F.**
##
## This test asserted the opposite for the length of the block — it is the guard that
## records which model a shot resolves through, so it inverts exactly once, here.
## The two fixtures that gated the flip were both fixture defects, not resolver ones:
## `BR52.08` (the fixture weapon authored no `volume`, so no muzzle-height test in
## `test_attack_action.gd` fired from the height it asked for) and this file's own
## sibling `test_shot_resolution.gd` deflect geometry, whose lateral aim offset
## rotated the real flight to 16 degrees while its comment claimed 37.
##
## **The plane is still selectable and still tested** — every parity experiment below
## runs both models on the identical board, which is the whole point of keeping it.
## `ShotPlane` is referenced at 133 sites across 76 files and deleting it belongs to
## its own block, not to the one that changed the default.
func test_the_ray_chain_is_the_default_and_the_plane_is_still_selectable() -> void:
	var state := CombatState.new(GridFixture.flat(5, 5), [])
	assert_eq(
		state.shot_resolver,
		ShotResolution.RESOLVER_RAY,
		"the flip landed — a shot resolves through the ray chain unless told otherwise"
	)
	assert_eq(state.dup().shot_resolver, ShotResolution.RESOLVER_RAY, "and a preview carries it")

	state.shot_resolver = ShotResolution.RESOLVER_PLANE
	assert_eq(
		state.dup().shot_resolver,
		ShotResolution.RESOLVER_PLANE,
		"the plane remains reachable by one field, for the differential and for a rollback"
	)


## **The seam sweep, both models.** The recorded taskblock-35 experiment, re-run
## through each resolver on the identical room.
func test_the_seam_sweep_through_both_models() -> void:
	var config := {
		"angles": SeamSweep.LEGACY_ANGLES,
		"lateral_samples": SeamSweep.LEGACY_LATERAL_SAMPLES,
		"lateral_max": SeamSweep.LEGACY_LATERAL_MAX,
		"height": AIM_HEIGHT,
	}
	var plane: Dictionary = SeamSweep.run(
		Vector2(_centre(ROOM)), config, _fire(_state(ROOM, ShotResolution.RESOLVER_PLANE))
	)
	var ray: Dictionary = SeamSweep.run(
		Vector2(_centre(ROOM)), config, _fire(_state(ROOM, ShotResolution.RESOLVER_RAY))
	)
	print(SeamSweep.describe(plane, "PLANE, %d-room" % ROOM))
	print(SeamSweep.describe(ray, "RAY CHAIN, %d-room" % ROOM))

	assert_eq(plane["empties"], 56, "the plane still measures the recorded 56/200")
	assert_eq(ray["empties"], 0, "the ray chain loses none of them")


## The same, on a room large enough that the plane has no empties either — so a
## zero from the ray chain is not merely the absence of the plane's own defect.
func test_both_models_are_clean_on_a_room_that_holds_every_offset() -> void:
	var config := {
		"angles": 45, "lateral_samples": 21, "lateral_max": 15.0, "height": AIM_HEIGHT, "bands": 5
	}
	var plane: Dictionary = SeamSweep.run(
		Vector2(_centre(BIG_ROOM)), config, _fire(_state(BIG_ROOM, ShotResolution.RESOLVER_PLANE))
	)
	var ray: Dictionary = SeamSweep.run(
		Vector2(_centre(BIG_ROOM)), config, _fire(_state(BIG_ROOM, ShotResolution.RESOLVER_RAY))
	)
	print(
		(
			"  big room — plane %d/%d empty, ray %d/%d empty"
			% [plane["empties"], plane["shots"], ray["empties"], ray["shots"]]
		)
	)
	assert_eq(plane["empties"], 0)
	assert_eq(ray["empties"], 0)


## **The differential.** Every disagreement is listed with both answers, so each
## can be judged rather than counted.
func test_the_differential_over_seeded_shots_lists_every_disagreement() -> void:
	var centre: Vector2i = _centre(ROOM)
	var shots: Array[Dictionary] = []
	for a in range(24):
		var angle: float = TAU * float(a) / 24.0
		var direction := Vector2(cos(angle), sin(angle)) * 4.0
		for s in range(9):
			var lateral: float = SeamSweep._lateral_at(s, 9, 8.0)
			(
				shots
				. append(
					{
						"origin": Vector2(centre),
						"direction": direction,
						"point": Vector2(lateral, AIM_HEIGHT),
						"damage": 0.0,
						"origin_height": AIM_HEIGHT,
					}
				)
			)

	var report: Dictionary = ResolverDifferential.run(
		func() -> CombatState: return _state(ROOM, ShotResolution.RESOLVER_PLANE), shots
	)
	print(ResolverDifferential.describe(report, "%d-room, chest height" % ROOM))

	assert_eq(report["shots"], 216)
	# **The ray chain never loses a shot the plane found.** That direction is the
	# one that would be a defect; the reverse is the improvement being bought.
	assert_eq(
		int((report["counts"] as Dictionary).get(ResolverDifferential.KIND_PLANE_ONLY, 0)),
		0,
		"the ray chain must never miss something the plane hit"
	)
	assert_gt(
		int((report["counts"] as Dictionary).get(ResolverDifferential.KIND_RAY_ONLY, 0)),
		0,
		"and it must find shots the plane lost, or it is not worth adopting"
	)


## **Why the disagreements are explicable, turned into evidence rather than an
## assurance.**
##
## The differential's largest bucket is `different_part` — the two models
## attributing one shot to different places. The claim is that the ray chain's
## attribution is the correct one, and that is checkable directly: **a reported
## hit point should lie on the surface it says it struck.**
##
## The plane's reported `hit_point` is reconstructed from `(depth, lateral)` in a
## parallel-ray model, where `depth` is the struck cell's *centre* projected on the
## shooter-to-target line, not the face the round met — so it can name a coordinate
## that is nowhere near the thing it says it struck. Counted here rather than
## argued.
func test_the_ray_chains_attribution_lands_on_real_geometry_and_the_planes_often_does_not() -> void:
	var centre: Vector2i = _centre(ROOM)
	var plane_state: CombatState = _state(ROOM, ShotResolution.RESOLVER_PLANE)
	var ray_state: CombatState = _state(ROOM, ShotResolution.RESOLVER_RAY)
	var plane_on_geometry := 0
	var plane_hits := 0
	var ray_on_geometry := 0
	var ray_hits := 0

	for a in range(24):
		var angle: float = TAU * float(a) / 24.0
		var direction := Vector2(cos(angle), sin(angle)) * 4.0
		for s in range(9):
			var point := Vector2(SeamSweep._lateral_at(s, 9, 8.0), AIM_HEIGHT)
			for pair in [
				[plane_state, ShotResolution.RESOLVER_PLANE],
				[ray_state, ShotResolution.RESOLVER_RAY],
			]:
				var state: CombatState = pair[0]
				var results: Array[ImpactResult] = ShotResolution.resolve_point(
					state,
					state.units[0],
					Vector2(centre),
					direction,
					point,
					0.0,
					0.0,
					0.0,
					AIM_HEIGHT,
					DamageResolver.DEFLECT_MODE_RICOCHET,
					0.0,
					0.0,
					0.0,
					pair[1]
				)
				if results.is_empty():
					continue
				var landed := Vector3(
					results[0].hit_point.x * UnitGeometry.CELL_SIZE,
					results[0].hit_height,
					results[0].hit_point.y * UnitGeometry.CELL_SIZE
				)
				# **Distance to the nearest real wall surface**, not a rounded
				# cell lookup: a hit lands exactly ON a box face, and rounding a
				# coordinate sitting at 0.5 puts it in the neighbouring cell.
				# The first version of this test did that and reported the ray
				# chain at 51% — measuring its own rounding, not the resolver.
				var gap: float = _distance_to_nearest_blocker(state.grid, landed)
				if pair[1] == ShotResolution.RESOLVER_PLANE:
					plane_hits += 1
					plane_on_geometry += 1 if gap < 0.01 else 0
				else:
					ray_hits += 1
					ray_on_geometry += 1 if gap < 0.01 else 0

	print(
		(
			"  plane: %d/%d reported hit points lie on the geometry they struck (%.1f%%)"
			% [plane_on_geometry, plane_hits, 100.0 * float(plane_on_geometry) / plane_hits]
		)
	)
	print(
		(
			"  ray  : %d/%d reported hit points lie on the geometry they struck (%.1f%%)"
			% [ray_on_geometry, ray_hits, 100.0 * float(ray_on_geometry) / ray_hits]
		)
	)
	assert_eq(ray_on_geometry, ray_hits, "every ray-chain hit point lies on the surface it struck")
	assert_lt(
		plane_on_geometry,
		plane_hits,
		(
			"and the plane's does not always — which is what the different_part "
			+ "bucket in the differential actually is"
		)
	)


## Shortest distance from a world point to any placed blocker box, 0.0 when the
## point sits on (or inside) one. Ordinary point-to-oriented-box arithmetic, done
## in each box's own local frame the same way the slab test is.
func _distance_to_nearest_blocker(grid: Grid, point: Vector3) -> float:
	var nearest: float = INF
	for cell: Vector2i in grid.blockers:
		var height: float = UnitGeometry.true_height_for_cell(cell, grid)
		var placements: Array[BoxPlacement] = UnitGeometry.assembly_placements(
			grid.blockers[cell], cell, 0.0, null, height
		)
		for placement: BoxPlacement in placements:
			var local: Vector3 = placement.transform.affine_inverse() * point
			var half: Vector3 = placement.box.size * 0.5
			var delta := Vector3(
				maxf(absf(local.x - placement.box.center.x) - half.x, 0.0),
				maxf(absf(local.y - placement.box.center.y) - half.y, 0.0),
				maxf(absf(local.z - placement.box.center.z) - half.z, 0.0)
			)
			nearest = minf(nearest, delta.length())
	return nearest


## Determinism, through the flag, for both models. Same seed, same board, same
## answer — the standing rule, checked on the new path as well as the old.
func test_both_models_resolve_identically_across_runs() -> void:
	for resolver in [ShotResolution.RESOLVER_PLANE, ShotResolution.RESOLVER_RAY]:
		for a in range(0, 360, 23):
			var angle: float = deg_to_rad(float(a))
			var direction := Vector2(cos(angle), sin(angle)) * 4.0
			var point := Vector2(2.0, AIM_HEIGHT)
			var first: Array[ImpactResult] = ShotResolution.resolve_point(
				_state(ROOM, resolver),
				_state(ROOM, resolver).units[0],
				Vector2(_centre(ROOM)),
				direction,
				point,
				4.0,
				0.0,
				0.0,
				AIM_HEIGHT,
				DamageResolver.DEFLECT_MODE_RICOCHET,
				0.0,
				0.0,
				0.0
			)
			var second: Array[ImpactResult] = ShotResolution.resolve_point(
				_state(ROOM, resolver),
				_state(ROOM, resolver).units[0],
				Vector2(_centre(ROOM)),
				direction,
				point,
				4.0,
				0.0,
				0.0,
				AIM_HEIGHT,
				DamageResolver.DEFLECT_MODE_RICOCHET,
				0.0,
				0.0,
				0.0
			)
			assert_eq(first.size(), second.size(), "%s: same hops at %d deg" % [resolver, a])
			for i in range(first.size()):
				assert_eq(
					first[i].region.part.id,
					second[i].region.part.id,
					"%s: same part at %d deg hop %d" % [resolver, a, i]
				)


## **Traversal order is geometric, not dictionary order** — a stronger guarantee
## than the plane's `sort_custom` over `Dictionary` iteration, which is insertion
## order and therefore a property of the map generator.
##
## Asserted by building the same room with its blockers inserted in **reverse**
## order and checking the answer does not move. The plane's own sort is stable
## only because generation happens to be seeded; the march never consults
## insertion order at all.
func test_the_march_does_not_depend_on_the_order_blockers_were_inserted() -> void:
	var forward := CombatState.new(GridFixture.enclosed_room(ROOM, ROOM), [])
	var reversed_grid: Grid = GridFixture.flat(ROOM, ROOM)
	var cells: Array[Vector2i] = []
	for x in range(ROOM):
		for y in range(ROOM):
			if x == 0 or y == 0 or x == ROOM - 1 or y == ROOM - 1:
				cells.append(Vector2i(x, y))
	cells.reverse()
	for cell: Vector2i in cells:
		GridFixture.place_wall(reversed_grid, cell)
	var backward := CombatState.new(reversed_grid, [])

	assert_eq(
		forward.grid.blockers.size(), backward.grid.blockers.size(), "same room, other insert order"
	)
	assert_ne(
		(forward.grid.blockers.keys() as Array)[0],
		(backward.grid.blockers.keys() as Array)[0],
		"and the dictionaries really do iterate differently"
	)

	var checked := 0
	for a in range(0, 360, 7):
		var angle: float = deg_to_rad(float(a))
		var from := Vector3(_centre(ROOM).x, AIM_HEIGHT, _centre(ROOM).y)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var one: RayHit = RayCaster.cast(forward, from, dir)
		var two: RayHit = RayCaster.cast(backward, from, dir)
		assert_eq(one == null, two == null, "same answer at %d degrees" % a)
		if one != null:
			assert_eq(one.cell, two.cell, "same cell at %d degrees, whatever the insert order" % a)
			assert_almost_eq(one.t, two.t, 0.0, "and the same distance")
		checked += 1
	print("  %d headings identical across two insertion orders" % checked)
	assert_gt(checked, 40)
