extends GutTest

## docs/03: armor is not more hitpoints. resolve_impact() decides penetrate/
## stop-dead/deflect from real geometry, never a roll; resolve_shot()
## cascades penetration into whatever's behind and follows a deflection's
## ricochet through a fresh shot plane, terminating via a depth cap and a
## damage floor.


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func _region(material: StringName, dt_part_hp: int = 10) -> Region:
	var part := Part.new()
	part.id = &"plate"
	part.material = material
	part.hp = dt_part_hp
	part.max_hp = dt_part_hp
	return Region.new(Rect2(), 0.0, part, Vector3(1.0, 0.0, 0.0))


## `-dir` sits `incidence_deg` from the fixed normal (1,0,0), matching how
## resolve_impact measures incidence: "steep/near head-on" is a small angle,
## grazing-along-the-surface approaches 90 degrees.
func _dir_at_incidence(incidence_deg: float) -> Vector2:
	var rad: float = deg_to_rad(incidence_deg)
	return -Vector2(cos(rad), sin(rad))


func test_chaingun_burst_under_dt_fails_to_penetrate_steel() -> void:
	var table := DataLibrary.material_table()
	var region := _region(&"steel")  # dt 6
	var dir := _dir_at_incidence(0.0)  # dead-on: also exercises stop-dead
	for i in range(5):
		var result := DamageResolver.resolve_impact(dir, 3.0, region, table)
		assert_ne(result.outcome, Enums.Outcome.PENETRATE, "round %d must fail to penetrate" % i)


func test_rifle_round_over_dt_damages_the_plate_and_the_part_behind() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"steel"
	plate.hp = 10
	plate.max_hp = 10
	plate.attaches_to = [&"CHEST"]
	plate.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(2.0, 1.0, 0.2))]

	var socket := Socket.new(&"CHEST")
	socket.occupant = plate
	torso.sockets = [socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var grid := Grid.new(6, 6)
	var state := CombatState.new(grid, [unit])
	var table := DataLibrary.material_table()

	# Front-on: the unit's front faces world +Y (orientation 0), so a shot
	# fired from further along +Y traveling in -Y hits the plate (at local
	# z +0.4, in front) before the torso (z 0).
	var origin := Vector2(2, 5)
	var direction := Vector2(0, -1)
	var aim_point := Vector2(0.0, 0.5)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 10.0, 0.0, state, table, _rng(1)
	)

	assert_eq(results.size(), 2)
	assert_eq(results[0].region.part.id, &"plate")
	assert_eq(results[0].outcome, Enums.Outcome.PENETRATE)
	assert_eq(results[1].region.part.id, &"torso")
	assert_eq(results[1].outcome, Enums.Outcome.PENETRATE)
	assert_lt(plate.hp, 10)
	assert_lt(torso.hp, 10)


## taskblock-09 B: "a 10-damage shot on a DT-4 plate deals 10 to the plate
## and spills 6" — the plate's own numbers, not the taskblock's exact
## words, since `_region`'s helper materials don't happen to include a
## DT-4 entry; the arithmetic is what's under test.
func test_penetration_spill_is_reduced_by_effective_dt_not_reapplied_in_full() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"dt4", MaterialEntry.new(4.0, 30.0))

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"dt4"
	plate.hp = 20
	plate.max_hp = 20
	plate.attaches_to = [&"CHEST"]
	plate.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(2.0, 1.0, 0.2))]

	var socket := Socket.new(&"CHEST")
	socket.occupant = plate
	torso.sockets = [socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var state := CombatState.new(Grid.new(6, 6), [unit])

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		Vector2(2, 5), Vector2(0, -1), Vector2(0.0, 0.5), 10.0, 0.0, state, table, _rng(1)
	)

	assert_eq(results.size(), 2)
	assert_eq(results[0].region.part.id, &"plate")
	assert_eq(results[0].part_damage, 10.0, "the plate eats the full damage, never a reduced share")
	assert_eq(plate.hp, 10, "20 hp - ceil(10 damage)")
	assert_eq(results[1].region.part.id, &"torso")
	assert_eq(results[1].part_damage, 6.0, "spill = 10 damage - effective_dt 4")
	assert_eq(torso.hp, 14, "20 hp - ceil(6 spill)")


## taskblock-09 B: equal damage/DT still penetrates (the flagged `>=`
## default) but leaves a spill of exactly 0 — the round stops at the
## plate, the same as if nothing else were behind it.
func test_a_bare_margin_penetration_spills_zero_and_stops_at_the_plate() -> void:
	var table := MaterialTable.new()
	table.set_entry(&"dt10", MaterialEntry.new(10.0, 30.0))

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 20
	torso.max_hp = 20
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]

	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"dt10"
	plate.hp = 20
	plate.max_hp = 20
	plate.attaches_to = [&"CHEST"]
	plate.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(2.0, 1.0, 0.2))]

	var socket := Socket.new(&"CHEST")
	socket.occupant = plate
	torso.sockets = [socket]

	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
	var state := CombatState.new(Grid.new(6, 6), [unit])

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		Vector2(2, 5), Vector2(0, -1), Vector2(0.0, 0.5), 10.0, 0.0, state, table, _rng(1)
	)

	assert_eq(results.size(), 1, "a spill of exactly 0 must stop the cascade at the plate")
	assert_eq(results[0].region.part.id, &"plate")
	assert_eq(results[0].outcome, Enums.Outcome.PENETRATE, "equal damage/DT still penetrates (>=)")
	assert_eq(torso.hp, 20, "nothing must reach the part behind")


func test_stop_dead_damages_the_plate_deflect_does_not() -> void:
	var table := DataLibrary.material_table()

	var head_on := _region(&"steel")
	var stop_result := DamageResolver.resolve_impact(_dir_at_incidence(0.0), 3.0, head_on, table)
	assert_eq(stop_result.outcome, Enums.Outcome.STOP_DEAD)
	assert_eq(stop_result.part_damage, 3.0)

	var oblique := _region(&"steel")
	var deflect_result := DamageResolver.resolve_impact(
		_dir_at_incidence(80.0), 3.0, oblique, table
	)
	assert_eq(deflect_result.outcome, Enums.Outcome.DEFLECT)
	assert_eq(deflect_result.part_damage, 0.0)


func test_a_graze_retains_about_90_percent_a_near_right_angle_bounce_about_25_percent() -> void:
	var table := DataLibrary.material_table()
	var low_threshold := MaterialEntry.new(6.0, 1.0)  # anything past 1 degree deflects
	table.set_entry(&"grazing_test", low_threshold)

	var graze := _region(&"grazing_test")
	var graze_result := DamageResolver.resolve_impact(_dir_at_incidence(89.0), 3.0, graze, table)
	assert_eq(graze_result.outcome, Enums.Outcome.DEFLECT)
	assert_almost_eq(graze_result.retained_fraction, 0.90, 0.05)

	var near_right_angle := _region(&"grazing_test")
	var bounce_result := DamageResolver.resolve_impact(
		_dir_at_incidence(2.0), 3.0, near_right_angle, table
	)
	assert_eq(bounce_result.outcome, Enums.Outcome.DEFLECT)
	assert_almost_eq(bounce_result.retained_fraction, 0.25, 0.05)


## Each round in a burst has its own muzzle-to-impact ray (docs/03 fix: a
## burst previously reused one shared `dir` for every round, so every
## deflection off the same flat surface read an identical incidence — this
## is what made checkpoint 3 show one repeated retained value). Aiming at
## different points across a wide, close-range surface should now read
## visibly different angles and retain visibly different fractions.
func test_a_burst_across_a_wide_surface_retains_a_spread_not_one_repeated_value() -> void:
	var grid := Grid.new(10, 10)
	var wall := Part.new()
	wall.id = &"wall"
	wall.material = &"wide_test"
	wall.hp = 50
	wall.max_hp = 50
	wall.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(4.0, 1.0, 0.6))]
	grid.blockers[Vector2i(5, 2)] = wall

	var table := DataLibrary.material_table()
	# Low threshold: everything but a near dead-center shot reads oblique
	# enough to deflect, so the whole spread below is comparable.
	table.set_entry(&"wide_test", MaterialEntry.new(6.0, 5.0))
	var state := CombatState.new(grid)
	var origin := Vector2(5, 0)
	var direction := Vector2(0, 1)

	var retained_by_offset: Dictionary = {}
	for offset in [0.6, 1.2, 1.8]:
		var point := Vector2(offset, 0.5)
		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			origin, direction, point, 3.0, 0.0, state, table, _rng(1)
		)
		assert_eq(results.size(), 1)
		assert_eq(results[0].outcome, Enums.Outcome.DEFLECT, "offset %s must deflect" % offset)
		retained_by_offset[offset] = results[0].retained_fraction

	# Further off-center means a shallower, more grazing muzzle-to-impact
	# angle, which retains *more* (a graze barely turns the path) — the
	# near-dead-center shot bends hardest and retains least.
	var values: Array = retained_by_offset.values()
	assert_true(
		values[0] < values[1] and values[1] < values[2],
		"retention must rise as the point moves further off-center: %s" % [values]
	)
	assert_true(
		values[2] - values[0] > 0.15,
		"the spread across one burst must clear the old ~11-point band: %s" % [values]
	)


func test_depth_cap_of_zero_stops_a_deflection_from_spawning_any_ricochet() -> void:
	var grid := Grid.new(6, 6)
	var state := CombatState.new(grid)
	var cover := Part.new()
	cover.id = &"cover"
	cover.material = &"steel"
	cover.hp = 20
	cover.max_hp = 20
	cover.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	grid.blockers[Vector2i(2, 2)] = cover

	var table := DataLibrary.material_table()
	var origin := Vector2(2, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	var region := _find_region(plane, cover)
	var aim_point: Vector2 = region.rect.get_center()

	var probe := DamageResolver.resolve_impact(direction, 3.0, region, table)
	assert_eq(probe.outcome, Enums.Outcome.DEFLECT, "fixture must actually deflect")

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 3.0, 0.0, state, table, _rng(1), 0, 0
	)
	assert_eq(results.size(), 1, "max_ricochet_depth 0 must forbid any ricochet")


func test_damage_floor_stops_a_deflection_from_spawning_a_ricochet() -> void:
	var grid := Grid.new(6, 6)
	var state := CombatState.new(grid)
	var cover := Part.new()
	cover.id = &"cover"
	cover.material = &"steel"
	cover.hp = 20
	cover.max_hp = 20
	cover.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	grid.blockers[Vector2i(2, 2)] = cover

	var table := DataLibrary.material_table()
	var origin := Vector2(2, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(direction.x, 0.0, direction.y), state
	)
	var region := _find_region(plane, cover)
	var aim_point: Vector2 = region.rect.get_center()

	# Tiny initial damage: even at ~90% retention the ricochet can't clear
	# any reasonable floor.
	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 0.5, 0.0, state, table, _rng(1), 0, 2, 1.0
	)
	assert_eq(results.size(), 1, "a ricochet below the damage floor must not be spawned")


func _find_region(plane: Array[Region], part: Part) -> Region:
	for region: Region in plane:
		if region.part == part:
			return region
	fail_test("part not found in plane")
	return null


func test_a_ricochet_can_tag_a_pre_positioned_third_party_and_replays_identically() -> void:
	var grid := Grid.new(20, 20)
	var cover := Part.new()
	cover.id = &"cover"
	cover.material = &"steel"
	cover.hp = 20
	cover.max_hp = 20
	cover.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	grid.blockers[Vector2i(10, 10)] = cover

	var table := DataLibrary.material_table()
	var origin := Vector2(10, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)

	var state_for_probe := CombatState.new(grid)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(dir.x, 0.0, dir.y), state_for_probe
	)
	var cover_region := _find_region(plane, cover)
	var aim_point: Vector2 = cover_region.rect.get_center()

	# resolve_shot derives each projectile's own muzzle-to-impact direction
	# rather than reusing the nominal `dir` (a burst's rounds land at
	# different points, not just different angles from the same ray) —
	# mirror that here so the probe predicts the same ricochet resolve_shot
	# will actually spawn.
	var shot_dir: Vector2 = (dir * cover_region.depth + perp * aim_point.x).normalized()
	var probe := DamageResolver.resolve_impact(shot_dir, 3.0, cover_region, table)
	assert_eq(probe.outcome, Enums.Outcome.DEFLECT, "fixture must actually deflect")

	var world_hit: Vector2 = origin + dir * cover_region.depth + perp * aim_point.x
	var third_party_cell := Vector2i(
		roundi(world_hit.x + probe.reflected_dir.x * 3.0),
		roundi(world_hit.y + probe.reflected_dir.y * 3.0)
	)
	var victim := Part.new()
	victim.id = &"victim"
	victim.hp = 10
	victim.max_hp = 10
	victim.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(3.0, 3.0, 3.0))]

	var summaries: Array = []
	for run in range(2):
		var run_cover := Part.new()
		run_cover.id = &"cover"
		run_cover.material = &"steel"
		run_cover.hp = 20
		run_cover.max_hp = 20
		run_cover.volume = cover.volume
		var run_grid := Grid.new(20, 20)
		run_grid.blockers[Vector2i(10, 10)] = run_cover

		var run_victim := Part.new()
		run_victim.id = &"victim"
		run_victim.hp = 10
		run_victim.max_hp = 10
		run_victim.volume = victim.volume
		var run_unit := Unit.new(Matrix.new(), Shell.new(run_victim), third_party_cell)
		var run_state := CombatState.new(run_grid, [run_unit])

		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			origin, direction, aim_point, 3.0, 0.0, run_state, table, _rng(99)
		)
		var summary: Array = []
		for result: ImpactResult in results:
			summary.append([result.outcome, result.region.part.id, result.part_damage])
		summaries.append(summary)

		assert_true(results.size() >= 2, "run %d: the ricochet must have hit something" % run)
		assert_eq(
			results[-1].region.part.id,
			&"victim",
			"run %d: the ricochet must tag the pre-positioned third party" % run
		)

	assert_eq(summaries[0], summaries[1], "same seed must replay an identical impact sequence")


## taskblock-22 Pass D: "every shot is visible... muzzle -> hit 1 ->
## (deflect) -> hit 2." Each ImpactResult now stamps its own real hop
## origin/landing point — the whole point being that a ricochet's SECOND
## hop must carry a DIFFERENT origin (the bounce point, open air) than the
## first (the true shooter's own muzzle), so the view can draw each
## segment from where it actually started instead of always from the
## shooter's own body.
func test_each_ricochet_hop_stamps_its_own_real_origin_and_hit_point() -> void:
	var grid := Grid.new(20, 20)
	var cover := Part.new()
	cover.id = &"cover"
	cover.material = &"steel"
	cover.hp = 20
	cover.max_hp = 20
	cover.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	grid.blockers[Vector2i(10, 10)] = cover

	var table := DataLibrary.material_table()
	var origin := Vector2(10, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)

	var state_for_probe := CombatState.new(grid)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(origin.x, 0.0, origin.y), Vector3(dir.x, 0.0, dir.y), state_for_probe
	)
	var cover_region := _find_region(plane, cover)
	var aim_point: Vector2 = cover_region.rect.get_center()

	var victim := Part.new()
	victim.id = &"victim"
	victim.hp = 10
	victim.max_hp = 10
	victim.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(3.0, 3.0, 3.0))]
	var shot_dir: Vector2 = (dir * cover_region.depth + perp * aim_point.x).normalized()
	var probe := DamageResolver.resolve_impact(shot_dir, 3.0, cover_region, table)
	assert_eq(probe.outcome, Enums.Outcome.DEFLECT, "fixture must actually deflect")
	var world_hit: Vector2 = origin + dir * cover_region.depth + perp * aim_point.x
	var third_party_cell := Vector2i(
		roundi(world_hit.x + probe.reflected_dir.x * 3.0),
		roundi(world_hit.y + probe.reflected_dir.y * 3.0)
	)
	var victim_unit := Unit.new(Matrix.new(), Shell.new(victim), third_party_cell)
	var state := CombatState.new(grid, [victim_unit])

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 3.0, 0.0, state, table, _rng(99)
	)

	assert_true(results.size() >= 2, "sanity: the ricochet must have hit something further")
	var first_hop: ImpactResult = results[0]
	var second_hop: ImpactResult = results[1]
	assert_almost_eq(
		first_hop.origin.x, origin.x, 0.01, "the first hop's own muzzle is the shooter"
	)
	assert_almost_eq(first_hop.origin.y, origin.y, 0.01)
	assert_almost_eq(
		first_hop.hit_point.x, world_hit.x, 0.01, "the first hop must land where it deflected"
	)
	assert_almost_eq(first_hop.hit_point.y, world_hit.y, 0.01)
	assert_ne(
		second_hop.origin,
		first_hop.origin,
		"the ricochet's own second hop must NOT originate from the shooter's own muzzle"
	)
	assert_almost_eq(
		second_hop.origin.x,
		first_hop.hit_point.x,
		0.01,
		"the second hop's own muzzle is exactly where the first hop bounced"
	)
	assert_almost_eq(second_hop.origin.y, first_hop.hit_point.y, 0.01)


func test_crit_chance_over_100_percent_always_crits_and_the_excess_is_the_double_crit_chance(
) -> void:
	var rng := _rng(5)
	const SAMPLES := 2000
	var double_crits := 0
	for i in range(SAMPLES):
		var roll: Dictionary = DamageResolver._roll_crit(1.25, rng)
		assert_true(roll.is_crit, "125%% crit chance must always crit")
		if roll.is_double_crit:
			double_crits += 1
	assert_almost_eq(float(double_crits) / SAMPLES, 0.25, 0.04)


func test_crit_effects_bypass_armor_when_armored_bonus_damage_when_not() -> void:
	var crit_on_armor: Dictionary = DamageResolver._crit_effects(true, false, true)
	assert_true(crit_on_armor.bypass)
	assert_false(crit_on_armor.bonus)

	var crit_on_bare: Dictionary = DamageResolver._crit_effects(true, false, false)
	assert_false(crit_on_bare.bypass)
	assert_true(crit_on_bare.bonus)

	var double_on_armor: Dictionary = DamageResolver._crit_effects(true, true, true)
	assert_true(double_on_armor.bypass)
	assert_true(double_on_armor.bonus)

	var double_on_bare: Dictionary = DamageResolver._crit_effects(true, true, false)
	assert_false(double_on_bare.bypass)
	assert_true(double_on_bare.bonus)


func test_double_crit_end_to_end_bypasses_armor_and_applies_bonus_damage() -> void:
	var plate := Part.new()
	plate.id = &"plate"
	plate.material = &"steel"
	plate.hp = 10
	plate.max_hp = 10
	plate.volume = [Box.new(Vector3(0.0, 0.5, 0.4), Vector3(2.0, 1.0, 0.2))]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	var socket := Socket.new(&"CHEST")
	socket.occupant = plate
	plate.attaches_to = [&"CHEST"]
	torso.sockets = [socket]

	var table := DataLibrary.material_table()
	# Front-on, as in the rifle-round test above: the plate (local z +0.4)
	# must be resolved before the torso (z 0).
	var origin := Vector2(2, 5)
	var direction := Vector2(0, -1)
	var aim_point := Vector2(0.0, 0.5)

	for attempt in range(200):
		plate.hp = 10
		torso.hp = 10
		var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(2, 2))
		var grid := Grid.new(6, 6)
		var state := CombatState.new(grid, [unit])

		var results: Array[ImpactResult] = DamageResolver.resolve_shot(
			origin, direction, aim_point, 2.0, 1.25, state, table, _rng(attempt)
		)
		if results.size() >= 1 and results[0].is_double_crit:
			assert_true(results[0].bypassed_armor, "double crit must bypass the plate")
			assert_eq(results[1].region.part.id, &"torso")
			assert_gt(
				results[1].part_damage, 2.0, "double crit must apply bonus damage to the hit behind"
			)
			return

	fail_test("no double crit observed in 200 seeded attempts")


func test_destroying_a_volatile_part_detonates_and_hits_units_in_radius_only() -> void:
	var rack := Part.new()
	rack.id = &"rack"
	rack.tags = [&"VOLATILE"]
	rack.failure_mode = &"DETONATE"
	rack.detonate_damage = 5.0
	rack.detonate_radius = 2.0
	rack.hp = 1
	rack.max_hp = 1

	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(5, 5)] = rack

	var near_root := Part.new()
	near_root.hp = 10
	near_root.max_hp = 10
	var near_unit := Unit.new(Matrix.new(), Shell.new(near_root), Vector2i(6, 6))

	var far_root := Part.new()
	far_root.hp = 10
	far_root.max_hp = 10
	var far_unit := Unit.new(Matrix.new(), Shell.new(far_root), Vector2i(9, 9))

	var state := CombatState.new(grid, [near_unit, far_unit])

	var destroyed := DamageResolver.apply_damage_to_part(rack, 10.0)
	assert_true(destroyed)

	var affected: Array[Unit] = DamageResolver.detonate(rack, state)
	assert_eq(affected.size(), 1)
	assert_eq(affected[0], near_unit)
	assert_eq(near_root.hp, 5)
	assert_eq(far_root.hp, 10)


## docs/10 taskblock04 C3: "a goo_barrel cooks off" — the starter field
## object's own data (VOLATILE + failure_mode DETONATE + a real
## detonate_damage), run through the exact same pre-existing detonate()
## mechanic every other volatile part uses. No new code, just the data
## actually being correct.
func test_the_goo_barrel_field_object_detonates() -> void:
	var barrel: Part = DataLibrary.get_part(&"goo_barrel")
	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(5, 5)] = barrel

	var near_root := Part.new()
	near_root.hp = 20
	near_root.max_hp = 20
	var near_unit := Unit.new(Matrix.new(), Shell.new(near_root), Vector2i(6, 6))
	var state := CombatState.new(grid, [near_unit])

	assert_true(DamageResolver.apply_damage_to_part(barrel, 999.0))
	var affected: Array[Unit] = DamageResolver.detonate(barrel, state)

	assert_eq(affected, [near_unit])
	assert_lt(near_root.hp, 20, "the goo barrel's own detonate_damage must actually have landed")


func test_detonate_is_a_no_op_without_real_detonate_damage() -> void:
	var inert := Part.new()
	inert.id = &"inert"
	inert.hp = 0
	inert.max_hp = 1
	var grid := Grid.new(5, 5)
	grid.blockers[Vector2i(2, 2)] = inert
	var state := CombatState.new(grid)
	assert_eq(DamageResolver.detonate(inert, state), [] as Array[Unit])

	inert.tags = [&"VOLATILE"]
	inert.failure_mode = &"DETONATE"
	assert_eq(
		DamageResolver.detonate(inert, state),
		[] as Array[Unit],
		"DETONATE with detonate_damage 0 must still be inert"
	)


## taskblock-09 A4: FRAGMENT sprays fragment_count rays in even directions
## from its own cell — direction 0 is always due +x (angle = TAU * 0 / K),
## so a target placed directly east of the shrapnel source is guaranteed to
## be in the path of one of them, proving the spray both fires and
## terminates (each ray is a real resolve_shot flight — `fragment_hits` is
## every ImpactResult across all K rays, not one-per-ray: a ray into open
## space contributes zero, one that penetrates can contribute several).
func test_fragment_sprays_rays_that_hit_and_terminate() -> void:
	var part := Part.new()
	part.id = &"ammo_crate"
	part.failure_mode = &"FRAGMENT"
	part.fragment_count = 4
	part.fragment_damage = 5.0
	part.hp = 1
	part.max_hp = 1

	var grid := Grid.new(20, 20)
	grid.blockers[Vector2i(5, 5)] = part

	var victim_root := Part.new()
	victim_root.hp = 10
	victim_root.max_hp = 10
	victim_root.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(3.0, 3.0, 3.0))]
	var victim := Unit.new(Matrix.new(), Shell.new(victim_root), Vector2i(8, 5))

	var state := CombatState.new(grid, [victim])
	assert_true(DamageResolver.apply_damage_to_part(part, 10.0))

	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(part, state, impact)

	assert_false(impact.fragment_hits.is_empty(), "the spray must have terminated with real hits")
	assert_lt(victim_root.hp, 10, "one of the four even-direction rays must have found the victim")


## taskblock-09 A4: a MELTDOWN part doesn't detonate on the hit that kills
## it — it arms a countdown, ticked by CombatState._start_turn via
## tick_meltdowns(), and only actually detonates once that countdown
## reaches 0. tick_meltdowns walks the OWNING unit's own shell (mirroring
## CombatState._start_turn's real call), so the reactor must actually be
## attached to that unit, not just sitting nearby as a field object.
func test_meltdown_counts_down_then_detonates() -> void:
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.failure_mode = &"MELTDOWN"
	reactor.meltdown_turns = 2
	reactor.detonate_damage = 5.0
	reactor.detonate_radius = 2.0
	reactor.hp = 1
	reactor.max_hp = 1

	var owner_torso := Part.new()
	owner_torso.id = &"owner_torso"
	owner_torso.hp = 20
	owner_torso.max_hp = 20
	var internal := Socket.new(&"INTERNAL")
	internal.occupant = reactor
	owner_torso.sockets = [internal]
	var owner := Unit.new(Matrix.new(), Shell.new(owner_torso), Vector2i(5, 5))

	var near_root := Part.new()
	near_root.hp = 10
	near_root.max_hp = 10
	var near_unit := Unit.new(Matrix.new(), Shell.new(near_root), Vector2i(5, 6))
	var state := CombatState.new(Grid.new(10, 10), [owner, near_unit])

	assert_true(DamageResolver.apply_damage_to_part(reactor, 10.0))
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(reactor, state, impact)

	assert_true(impact.meltdown_armed, "the killing hit only arms the countdown, it doesn't fire")
	assert_eq(near_root.hp, 10, "no damage yet — the countdown hasn't expired")
	assert_eq(reactor.meltdown_countdown, 2)

	var first_tick: Array[Dictionary] = DamageResolver.tick_meltdowns(owner, state)
	assert_eq(first_tick.size(), 0, "one turn down, still counting")
	assert_eq(reactor.meltdown_countdown, 1)
	assert_eq(near_root.hp, 10)

	var second_tick: Array[Dictionary] = DamageResolver.tick_meltdowns(owner, state)
	assert_eq(second_tick.size(), 1, "the countdown expired: it must detonate exactly now")
	assert_eq(second_tick[0].part, reactor)
	assert_has(second_tick[0].units, near_unit)
	assert_lt(near_root.hp, 10, "the expired countdown must actually deal its detonate_damage")


## taskblock-22 Pass C: "a wounded unit that shuts down may trigger its
## reactor's MELTDOWN if the reactor is in that state." A shut-down unit
## never gets another turn, so `tick_meltdowns` (only ever called at THIS
## unit's own turn start) could otherwise never actually finish a primed
## countdown — `trigger_primed_meltdowns` detonates it immediately instead
## of waiting for a tick that will never come.
func test_trigger_primed_meltdowns_detonates_a_live_countdown_immediately() -> void:
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.failure_mode = &"MELTDOWN"
	reactor.meltdown_turns = 5
	reactor.detonate_damage = 5.0
	reactor.detonate_radius = 2.0
	reactor.hp = 1
	reactor.max_hp = 1

	var owner_torso := Part.new()
	owner_torso.id = &"owner_torso"
	owner_torso.hp = 20
	owner_torso.max_hp = 20
	var internal := Socket.new(&"INTERNAL")
	internal.occupant = reactor
	owner_torso.sockets = [internal]
	var owner := Unit.new(Matrix.new(), Shell.new(owner_torso), Vector2i(5, 5))

	var near_root := Part.new()
	near_root.hp = 10
	near_root.max_hp = 10
	var near_unit := Unit.new(Matrix.new(), Shell.new(near_root), Vector2i(5, 6))
	var state := CombatState.new(Grid.new(10, 10), [owner, near_unit])

	assert_true(DamageResolver.apply_damage_to_part(reactor, 10.0))
	var impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(reactor, state, impact)
	assert_eq(reactor.meltdown_countdown, 5, "sanity: armed, nowhere near naturally expiring yet")

	var events: Array[Dictionary] = DamageResolver.trigger_primed_meltdowns(owner, state)

	assert_eq(events.size(), 1, "the live countdown must detonate now, not wait out its own clock")
	assert_eq(events[0].part, reactor)
	assert_has(events[0].units, near_unit)
	assert_eq(reactor.meltdown_countdown, -1, "the clock is cancelled, not left running")
	assert_lt(near_root.hp, 10)


## A healthy unit (no part ever armed a countdown) triggers nothing —
## shutdown is a complete no-op for the meltdown hook here.
func test_trigger_primed_meltdowns_is_a_no_op_with_nothing_armed() -> void:
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.failure_mode = &"MELTDOWN"
	reactor.meltdown_turns = 5
	reactor.hp = 5
	reactor.max_hp = 5

	var owner := Unit.new(Matrix.new(), Shell.new(reactor), Vector2i(5, 5))
	var state := CombatState.new(Grid.new(10, 10), [owner])

	var events: Array[Dictionary] = DamageResolver.trigger_primed_meltdowns(owner, state)

	assert_eq(events, [] as Array[Dictionary])


## taskblock-09 A4: re-destroying a part already counting down detonates it
## immediately rather than waiting out the rest of the clock.
func test_meltdown_detonates_early_if_re_killed_mid_countdown() -> void:
	var reactor := Part.new()
	reactor.id = &"reactor"
	reactor.failure_mode = &"MELTDOWN"
	reactor.meltdown_turns = 5
	reactor.detonate_damage = 5.0
	reactor.detonate_radius = 2.0
	reactor.hp = 1
	reactor.max_hp = 1

	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(5, 5)] = reactor

	var near_root := Part.new()
	near_root.hp = 10
	near_root.max_hp = 10
	var near_unit := Unit.new(Matrix.new(), Shell.new(near_root), Vector2i(5, 6))
	var state := CombatState.new(grid, [near_unit])

	assert_true(DamageResolver.apply_damage_to_part(reactor, 10.0))
	var first_impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(reactor, state, first_impact)
	assert_true(first_impact.meltdown_armed)
	assert_eq(reactor.meltdown_countdown, 5)

	var second_impact := ImpactResult.new()
	DamageResolver.resolve_part_failure(reactor, state, second_impact)

	assert_eq(second_impact.detonated_units, [near_unit], "re-killed mid-countdown: fires now")
	assert_eq(reactor.meltdown_countdown, -1, "the clock is cancelled, not left running")
	assert_lt(near_root.hp, 10)


## taskblock-23 Pass C: the real bug Pass A's own height-retaining fix
## exposed — the old `normal_2d := Vector2(surface_normal.x,
## surface_normal.z)` truncation silently discarded surface_normal's own Y
## (Pass A: no longer forced to 0). A face pointing straight up is the
## clearest case: its ground-plane projection is the ZERO vector, so the
## old incidence math saw a degenerate (0,0) normal and always read 90
## degrees (maximal, glancing) no matter how steep the real shot — even a
## near-vertical dive straight onto it, which is actually nearly dead-on.
func test_resolve_impact_incidence_uses_the_regions_real_3d_normal_not_a_flattened_one() -> void:
	var table := DataLibrary.material_table()
	var part := Part.new()
	part.id = &"plate"
	part.material = &"steel"
	part.hp = 20
	part.max_hp = 20
	var region := Region.new(Rect2(), 1.0, part, Vector3(0.0, 1.0, 0.0))

	var level_shot: ImpactResult = DamageResolver.resolve_impact(
		Vector2(1.0, 0.0), 1.0, region, table
	)
	var steep_dive: ImpactResult = DamageResolver.resolve_impact(
		Vector2(1.0, 0.0), 1.0, region, table, 0.0, 100.0
	)

	assert_eq(
		level_shot.outcome,
		Enums.Outcome.DEFLECT,
		"a dead-level shot grazing a face pointing straight up is maximal incidence -- glancing"
	)
	assert_eq(
		steep_dive.outcome,
		Enums.Outcome.STOP_DEAD,
		"a near-vertical dive onto the SAME face is nearly dead-on -- the real 3D normal must see it"
	)


## taskblock-23 Pass C: `resolve_shot` now tests each region at ITS OWN
## real height (`point.y` rising/falling with that region's own depth via
## `vertical_slope`), not one fixed height for the whole flight. Same two
## boxes, same everything else — only the flight's own tilt decides which
## one (if either) it actually reaches, proven at the full resolve_shot
## level (not just the `_find_next`/`resolve_ray` primitives it shares the
## mechanism with).
func test_a_tilted_flight_vertical_slope_changes_which_region_resolve_shot_hits() -> void:
	var grid := Grid.new(10, 10)
	var state := CombatState.new(grid)
	var table := DataLibrary.material_table()
	var near_low := Part.new()
	near_low.id = &"near_low"
	near_low.material = &"steel"
	near_low.hp = 20
	near_low.max_hp = 20
	near_low.volume = [Box.new(Vector3(0.0, 0.25, 0.0), Vector3(2.0, 0.5, 0.6))]  # y [0.0, 0.5]
	var far_high := Part.new()
	far_high.id = &"far_high"
	far_high.material = &"steel"
	far_high.hp = 20
	far_high.max_hp = 20
	far_high.volume = [Box.new(Vector3(0.0, 1.5, 0.0), Vector3(2.0, 1.0, 0.6))]  # y [1.0, 2.0]
	grid.blockers[Vector2i(2, 2)] = near_low
	grid.blockers[Vector2i(2, 6)] = far_high

	var origin := Vector2(2, 0)
	var direction := Vector2(0, 1)

	var flat_results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, Vector2(0.0, 0.25), 1.0, 0.0, state, table, _rng(1)
	)
	assert_eq(
		flat_results[0].region.part, near_low, "a flat flight at 0.25 lands on the near, low cover"
	)

	# Same flight, same aim height, but climbing (vertical_slope 0.3) —
	# clears the near cover's own rect ([0.0, 0.5]) by the time it gets
	# there and instead reaches the far, tall one ([1.0, 2.0]).
	var tilted_results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction,
		Vector2(0.0, 0.25),
		1.0,
		0.0,
		state,
		table,
		_rng(1),
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		[],
		0.0,
		0.3
	)
	assert_eq(
		tilted_results[0].region.part,
		far_high,
		"the SAME flight, climbing, clears the near cover and reaches the far, tall one instead"
	)


## taskblock-23 Pass C: "a ricochet hop travels a 3D reflected direction
## (can gain/lose height)" — a real shot, through the real BodyProjector
## pipeline (not a hand-built Region), deflecting off a genuinely tilted
## body part (`Poses.aiming()`'s own shoulder tilt, the exact fixture
## `test_body_projector.gd` already proves produces surface_normal.y ~=
## 0.707107) must come back with a real, nonzero reflected_vertical — a
## DEAD-LEVEL incoming shot (incoming_vertical 0.0) reflecting off
## anything but a purely vertical face is only possible to have a nonzero
## reflected_vertical at all because the fix respects the face's own real
## tilt; the old code had no such concept and every ricochet flattened to
## one height by construction.
func test_a_deflection_off_a_real_tilted_body_part_gains_a_genuine_vertical_component() -> void:
	var arm := Part.new()
	arm.id = &"arm"
	arm.material = &"steel"
	arm.hp = 4
	arm.max_hp = 4
	arm.volume = [Box.new(Vector3(0.0, -0.3, 0.0), Vector3(0.4, 0.9, 0.4))]
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder_r := Socket.new(
		&"SHOULDER", Transform3D(Basis(), Vector3(0.31, 1.53, 0.0)), &"SHOULDER_R"
	)
	shoulder_r.occupant = arm
	torso.sockets = [shoulder_r]
	var target := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	target.pose = Poses.aiming()
	var grid := Grid.new(20, 20)
	var state := CombatState.new(grid, [target])
	var table := DataLibrary.material_table()

	var origin := Vector2(0, 10)
	var direction := Vector2(0, -1)
	var aim_point := Vector2(0.3, 1.4)  # inside the tilted arm's own real rect

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin, direction, aim_point, 5.0, 0.0, state, table, _rng(1)
	)

	assert_eq(results[0].region.part, arm)
	assert_eq(results[0].outcome, Enums.Outcome.DEFLECT, "fixture must actually deflect")
	assert_almost_eq(
		results[0].hit_height, aim_point.y, 0.01, "the first hop's own real height is stamped"
	)
	assert_gt(
		results[0].reflected_vertical,
		1.0,
		"a dead-level shot off a 45-degree-tilted face must reflect with a real, steep vertical rise"
	)
