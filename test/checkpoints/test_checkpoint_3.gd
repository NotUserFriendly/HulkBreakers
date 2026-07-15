extends GutTest

## Checkpoint 3 artifact (docs/09): a seeded burst fired at a steel-plated
## torso, dumped round by round — outcome, retained damage, and any
## ricochet's landing spot — so a human can eyeball "does grazing keep
## ~90%, do bounces land somewhere plausible, is the spray chaotic but not
## insane." Run via ./checkpoint.sh 3 — its stdout is what lands in
## out/checkpoints/03/output.txt.

const BURST_SIZE := 10
const SEED := 20260715


func _armored_unit(cell: Vector2i) -> Unit:
	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"steel"
	plate.hp = 20
	plate.max_hp = 20
	plate.attaches_to = [&"CHEST"]
	plate.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(2.0, 1.0, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var socket := Socket.new(&"CHEST")
	socket.occupant = plate
	torso.sockets = [socket]

	return Unit.new(Matrix.new(), Frame.new(torso), cell)


func _outcome_name(outcome: int) -> String:
	match outcome:
		Enums.Outcome.PENETRATE:
			return "PENETRATE"
		Enums.Outcome.STOP_DEAD:
			return "STOP_DEAD"
		Enums.Outcome.DEFLECT:
			return "DEFLECT"
	return "?"


func _bystander_unit(cell: Vector2i) -> Unit:
	var root := Part.new()
	root.id = &"bystander"
	root.hp = 10
	root.max_hp = 10
	root.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))]
	return Unit.new(Matrix.new(), Frame.new(root), cell)


func test_seeded_burst_into_armor() -> void:
	var target := _armored_unit(Vector2i(10, 10))
	# In the path of the expected ricochet, so a deflected round has a
	# plausible chance of tagging someone else entirely.
	var bystander := _bystander_unit(Vector2i(14, 13))
	var grid := Grid.new(30, 30)
	var state := CombatState.new(grid, [target, bystander])
	var table := MaterialTable.default_table()

	# `origin` is placed exactly along `direction` back from the target's
	# cell, so aiming dead-center genuinely reproduces this nominal ~53
	# degree incidence (each scattered round then reads its own, slightly
	# different angle from its own muzzle-to-impact ray — docs/03). 53
	# degrees clears the 30-degree default deflect threshold with enough
	# margin that scatter doesn't flip most rounds to stopping dead.
	var direction := Vector2(4, -3)
	var dir: Vector2 = direction.normalized()
	var origin: Vector2 = Vector2(10, 10) - dir * 8.0

	var plane: Array[Region] = ShotPlane.build(origin, dir, state)
	var plate_region: Region = null
	for region: Region in plane:
		if region.part.id == &"plate" and region.surface_normal.z > 0.5:
			plate_region = region  # the front face specifically, not the side sliver
	var aim_point: Vector2 = plate_region.rect.get_center()

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var scatter: Array[Ring] = [Ring.new(0.2, 1.0), Ring.new(1.0, 2.0)]
	var points: Array[Vector2] = Dartboard.sample(aim_point, scatter, rng, BURST_SIZE)

	print("\n=== seeded burst into a steel-plated torso (seed %d) ===" % SEED)
	print(AsciiRender.plane_to_text(AsciiRender.recenter(plane, 4.0), 8, 2))

	for i in range(BURST_SIZE):
		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			origin, direction, points[i], 3.0, 0.0, state, table, rng
		)
		print("\n--- round %d ---" % (i + 1))
		if results.is_empty():
			print("  clean miss — nothing in the plane at this point")
		for result: ImpactResult in results:
			var line: String = "  %s on %s" % [_outcome_name(result.outcome), result.region.part.id]
			if result.outcome == Enums.Outcome.DEFLECT:
				line += (
					" (retained %.0f%%, reflected %s)"
					% [result.retained_fraction * 100.0, result.reflected_dir]
				)
			else:
				line += " (%.1f damage)" % result.part_damage
			print(line)

	var plate: Part = target.frame.root.sockets[0].occupant
	print(
		(
			"\nplate hp: %d/20   torso hp: %d/20   bystander hp: %d/10"
			% [plate.hp, target.frame.root.hp, bystander.frame.root.hp]
		)
	)
	assert_true(true, "artifact generated — see printed rounds above")
