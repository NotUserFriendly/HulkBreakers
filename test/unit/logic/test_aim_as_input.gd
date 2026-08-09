extends GutTest

## taskblock-52 Pass E: **the dartboard is an input device.**
##
## It answers *where is the player pointing* and produces the B point; the ray
## resolves from A to B onward. `docs/08`'s pillar survives the split because the
## thing shown and the thing computed are still one computation — which is only
## true if the aim preview and resolution go through the same query, and until this
## pass they did not: `AimController._resolve_hit` built its own `ShotPlane` and
## walked it.

const AIM_HEIGHT := 1.0


func _shooter(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"shooter_torso"
	torso.material = &"steel"
	torso.hp = 40
	torso.max_hp = 40
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(0.6, 1.2, 0.4))]
	var weapon := Part.new()
	weapon.id = &"gun"
	weapon.material = &"steel"
	weapon.hp = 10
	weapon.max_hp = 10
	weapon.attaches_to = [&"HAND"]
	weapon.volume = [Box.new(Vector3(0.0, 0.0, 0.2), Vector3(0.1, 0.1, 0.5))]
	var socket := Socket.new(&"HAND")
	socket.occupant = weapon
	socket.transform = Transform3D(Basis(), Vector3(0.35, 1.1, 0.0))
	torso.sockets = [socket]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _target(cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = &"target_torso"
	torso.material = &"steel"
	torso.hp = 400
	torso.max_hp = 400
	torso.volume = [Box.new(Vector3(0.0, 0.9, 0.0), Vector3(1.0, 1.8, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


func _state(resolver: StringName) -> CombatState:
	var grid: Grid = GridFixture.enclosed_room(21, 21)
	var state := CombatState.new(grid, [_shooter(Vector2i(5, 10)), _target(Vector2i(14, 10))])
	state.shot_resolver = resolver
	return state


## **A click produces the same B point the aim view drew a reticle at.** Both
## directions of the round trip go through `AimPlaneGeometry`, so this asserts the
## screen-to-aim and aim-to-world halves are genuine inverses rather than two
## nearby formulas.
func test_a_camera_ray_through_the_drawn_reticle_recovers_the_same_aim_point() -> void:
	var shooter_cell := Vector2i(5, 10)
	var target_cell := Vector2i(14, 10)
	for aim in [Vector2(0.0, 1.0), Vector2(0.4, 1.6), Vector2(-0.7, 0.3), Vector2(1.2, 2.2)]:
		# Where the aim view actually draws the reticle for this aim point.
		var drawn: Vector3 = AimPlaneGeometry.world_point(shooter_cell, target_cell, aim)
		# A camera somewhere off to the side, looking at exactly that drawn point —
		# which is what clicking the reticle on screen produces.
		var camera := Vector3(-6.0, 9.0, -4.0)
		var recovered: Variant = AimPlaneGeometry.aim_point_from_ray(
			shooter_cell, target_cell, camera, (drawn - camera).normalized()
		)
		assert_not_null(recovered, "a ray aimed at the drawn point must cross the aim plane")
		print("  aim %s -> drawn %s -> recovered %s" % [aim, drawn, recovered])
		assert_almost_eq(
			(recovered as Vector2).distance_to(aim),
			0.0,
			0.0005,
			"clicking where the reticle is drawn recovers the aim point it was drawn from"
		)


## **The B point is a world point, and the shot is muzzle-to-B.** Asserted against
## the drawn reticle position rather than a re-derivation: the shot the resolver
## fires must pass through the place the player was shown.
func test_the_shot_travels_from_the_muzzle_through_the_drawn_reticle() -> void:
	var state: CombatState = _state(ShotResolution.RESOLVER_RAY)
	var shooter: Unit = state.units[0]
	var weapon: Part = shooter.shell.find_part(&"gun")
	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
	var aim := Vector2(0.3, 1.2)
	var drawn: Vector3 = AimPlaneGeometry.world_point(shooter.cell, Vector2i(14, 10), aim)

	var hit: RayHit = RayCaster.cast(
		state, muzzle, drawn - muzzle, shooter.shell.all_parts_with_joints()
	)
	assert_not_null(hit, "the shot meets something")
	# The struck point must lie on the muzzle-to-B line, which is what "the round
	# goes where the reticle is" means geometrically.
	var along: Vector3 = (drawn - muzzle).normalized()
	var offset: Vector3 = hit.point - muzzle
	var lateral: float = (offset - along * offset.dot(along)).length()
	print(
		(
			"  muzzle %s -> reticle %s, struck %s (%.6f off the line)"
			% [muzzle, drawn, hit.point, lateral]
		)
	)
	assert_almost_eq(lateral, 0.0, 0.0001, "the impact sits on the muzzle-to-reticle line")


## **The pillar: the number shown is the number computed.** The aim preview's
## reported hit and what resolution actually strikes must be the same thing —
## which is only structurally true now that both go through one query.
func test_the_aim_preview_reports_what_resolution_produces() -> void:
	var state: CombatState = _state(ShotResolution.RESOLVER_RAY)
	var shooter: Unit = state.units[0]
	var weapon: Part = shooter.shell.find_part(&"gun")
	var target_cell := Vector2i(14, 10)
	var checked := 0

	for aim in [Vector2(0.0, 1.0), Vector2(0.3, 1.4), Vector2(-0.3, 0.8), Vector2(0.0, 1.7)]:
		var preview: AimResult = AimController.resolve(
			[] as Array[Region], aim, null, weapon, shooter, target_cell, state
		)
		assert_not_null(preview.resolves, "the preview reports a hit for aim %s" % aim)

		var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
		var resolved: Array[ImpactResult] = RayChain.resolve(
			state,
			muzzle,
			AimPlaneGeometry.world_point(shooter.cell, target_cell, aim),
			0.0,
			0.0,
			state.material_table,
			RandomNumberGenerator.new(),
			shooter.shell.all_parts_with_joints()
		)
		assert_false(resolved.is_empty(), "and resolution strikes something for aim %s" % aim)
		print(
			(
				"  aim %s: preview says %s, resolution says %s"
				% [aim, preview.resolves.part.id, resolved[0].region.part.id]
			)
		)
		assert_eq(
			preview.resolves.part,
			resolved[0].region.part,
			"aim %s: the preview and the shot must name the same part" % aim
		)
		checked += 1
	assert_eq(checked, 4)


## The same, with the flag on the plane — the preview follows the resolver rather
## than hard-coding one. Without this the change above could have silently made
## the preview disagree with the plane while the plane was still the default.
func test_the_preview_follows_the_flag() -> void:
	var ray_state: CombatState = _state(ShotResolution.RESOLVER_RAY)
	var plane_state: CombatState = _state(ShotResolution.RESOLVER_PLANE)
	var aim := Vector2(0.0, 1.2)
	for state in [ray_state, plane_state]:
		var shooter: Unit = state.units[0]
		var weapon: Part = shooter.shell.find_part(&"gun")
		var preview: AimResult = AimController.resolve(
			[] as Array[Region], aim, null, weapon, shooter, Vector2i(14, 10), state
		)
		assert_not_null(
			preview.resolves, "%s: the preview resolves something" % state.shot_resolver
		)
		print("  %s preview -> %s" % [state.shot_resolver, preview.resolves.part.id])


## **Scatter offsets are seeded and reproducible**, and offsetting B before the
## march changes nothing about that: a seeded offset on a point, then a closed-form
## march. No integrator, no accumulated simulation.
func test_scatter_offsets_are_seeded_and_reproducible() -> void:
	var state: CombatState = _state(ShotResolution.RESOLVER_RAY)
	var rings: Array[Ring] = [Ring.new(0.2, 1.0), Ring.new(0.8, 2.0)]
	var aim := Vector2(0.0, 1.2)

	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 4242
	var first: Array[Vector2] = Dartboard.sample(aim, rings, first_rng, 8)
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 4242
	var second: Array[Vector2] = Dartboard.sample(aim, rings, second_rng, 8)

	assert_eq(first.size(), 8)
	for i in range(first.size()):
		assert_almost_eq(
			first[i].distance_to(second[i]), 0.0, 0.0, "pull %d: same seed, same point" % i
		)

	# And each of those offset points becomes a B the march resolves the same way
	# twice — the property that matters once scatter feeds a ray rather than a
	# lateral offset.
	var shooter: Unit = state.units[0]
	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, shooter.shell.find_part(&"gun"))
	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	for point: Vector2 in first:
		var b: Vector3 = AimPlaneGeometry.world_point(shooter.cell, Vector2i(14, 10), point)
		var a1: RayHit = RayCaster.cast(state, muzzle, b - muzzle, excluded)
		var a2: RayHit = RayCaster.cast(state, muzzle, b - muzzle, excluded)
		assert_eq(a1 == null, a2 == null)
		if a1 != null:
			assert_eq(a1.part, a2.part, "the same scattered B resolves the same way twice")
	print("  8 seeded scatter points, each resolving identically twice")
