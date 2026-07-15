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
	var table := MaterialTable.default_table()
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

	var unit := Unit.new(Matrix.new(), Frame.new(torso), Vector2i(2, 2))
	var grid := Grid.new(6, 6)
	var state := CombatState.new(grid, [unit])
	var table := MaterialTable.default_table()

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


func test_stop_dead_damages_the_plate_deflect_does_not() -> void:
	var table := MaterialTable.default_table()

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
	var table := MaterialTable.default_table()
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

	var table := MaterialTable.default_table()
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

	var table := MaterialTable.default_table()
	var origin := Vector2(2, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)
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

	var table := MaterialTable.default_table()
	var origin := Vector2(2, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)
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

	var table := MaterialTable.default_table()
	var origin := Vector2(10, 0)
	var direction := Vector2(3, 4)  # incidence ~37 deg: clears the 30 deg default threshold
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)

	var state_for_probe := CombatState.new(grid)
	var plane: Array[Region] = ShotPlane.build(origin, dir, state_for_probe)
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
		var run_unit := Unit.new(Matrix.new(), Frame.new(run_victim), third_party_cell)
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

	var table := MaterialTable.default_table()
	# Front-on, as in the rifle-round test above: the plate (local z +0.4)
	# must be resolved before the torso (z 0).
	var origin := Vector2(2, 5)
	var direction := Vector2(0, -1)
	var aim_point := Vector2(0.0, 0.5)

	for attempt in range(200):
		plate.hp = 10
		torso.hp = 10
		var unit := Unit.new(Matrix.new(), Frame.new(torso), Vector2i(2, 2))
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


func test_destroying_a_volatile_part_cooks_off_and_hits_units_in_radius_only() -> void:
	var rack := Part.new()
	rack.id = &"rack"
	rack.tags = [&"VOLATILE"]
	rack.cook_off_damage = 5.0
	rack.cook_off_radius = 2.0
	rack.hp = 1
	rack.max_hp = 1

	var grid := Grid.new(10, 10)
	grid.blockers[Vector2i(5, 5)] = rack

	var near_root := Part.new()
	near_root.hp = 10
	near_root.max_hp = 10
	var near_unit := Unit.new(Matrix.new(), Frame.new(near_root), Vector2i(6, 6))

	var far_root := Part.new()
	far_root.hp = 10
	far_root.max_hp = 10
	var far_unit := Unit.new(Matrix.new(), Frame.new(far_root), Vector2i(9, 9))

	var state := CombatState.new(grid, [near_unit, far_unit])

	var destroyed := DamageResolver.apply_damage_to_part(rack, 10.0)
	assert_true(destroyed)

	var affected: Array[Unit] = DamageResolver.cook_off(rack, state)
	assert_eq(affected.size(), 1)
	assert_eq(affected[0], near_unit)
	assert_eq(near_root.hp, 5)
	assert_eq(far_root.hp, 10)


func test_cook_off_is_a_no_op_without_the_volatile_tag_or_zero_damage() -> void:
	var inert := Part.new()
	inert.id = &"inert"
	inert.hp = 0
	inert.max_hp = 1
	var grid := Grid.new(5, 5)
	grid.blockers[Vector2i(2, 2)] = inert
	var state := CombatState.new(grid)
	assert_eq(DamageResolver.cook_off(inert, state), [] as Array[Unit])

	inert.tags = [&"VOLATILE"]
	assert_eq(
		DamageResolver.cook_off(inert, state),
		[] as Array[Unit],
		"VOLATILE with cook_off_damage 0 must still be inert"
	)


func _make_matrix_hosting_torso(cell: Vector2i) -> Dictionary:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 5
	torso.max_hp = 5
	torso.hosts_matrix = true
	var link := Matrix.new()
	link.id = &"link"
	torso.hosted_matrix = link
	var unit := Unit.new(Matrix.new(), Frame.new(torso), cell)
	return {"unit": unit, "torso": torso, "link": link}


func test_destroying_the_matrix_hosting_part_ejects_it_demotes_and_disables() -> void:
	var built: Dictionary = _make_matrix_hosting_torso(Vector2i(2, 2))
	var unit: Unit = built.unit
	var torso: Part = built.torso
	var link: Matrix = built.link
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid, [unit])

	DamageResolver.apply_damage_to_part(torso, 10.0)
	var ejected: Matrix = DamageResolver.eject_matrix_if_needed(torso, state)

	assert_eq(ejected, link)
	assert_null(torso.hosted_matrix, "the part no longer hosts the matrix once it's ejected")
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(link),
		"the ejected matrix must land as a recoverable field item, never simply discarded"
	)
	assert_false(unit.alive, "unpiloted once its matrix ejects")
	assert_eq(unit.surrogate_tier.id, &"PERIPHERAL", "one rung down from FULL")
	assert_eq(unit.exposed_turns, 1, "the exposure clock must start ticking")


func test_eject_matrix_if_needed_is_a_no_op_for_a_part_that_hosts_none() -> void:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 0
	torso.max_hp = 5
	var state := CombatState.new(Grid.new(5, 5))
	assert_null(DamageResolver.eject_matrix_if_needed(torso, state))


func test_a_torso_chewed_to_spinal_still_functions_it_only_stops_at_matrix_ejection() -> void:
	# docs/04: demotion tracks matrix-hosting-part destruction, not simply
	# taking damage — a hit that doesn't destroy the host leaves the
	# surrogate tier untouched.
	var built: Dictionary = _make_matrix_hosting_torso(Vector2i(2, 2))
	var unit: Unit = built.unit
	var torso: Part = built.torso
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(torso, 2.0)  # 5 hp -> 3, still alive
	DamageResolver.eject_matrix_if_needed(torso, state)

	assert_eq(unit.surrogate_tier.id, &"FULL", "the host survived, nothing should have demoted yet")
	assert_true(unit.alive)


## torso -[SHOULDER]- arm -[WRIST]- hand -[GRIP]- pistol
func _make_armed_unit(cell: Vector2i) -> Dictionary:
	var pistol := Part.new()
	pistol.id = &"pistol"
	pistol.hp = 3
	pistol.max_hp = 3

	var hand := Part.new()
	hand.id = &"hand"
	hand.hp = 3
	hand.max_hp = 3
	var grip := Socket.new(&"GRIP")
	grip.occupant = pistol
	hand.sockets = [grip]

	var arm := Part.new()
	arm.id = &"arm"
	arm.hp = 3
	arm.max_hp = 3
	var wrist := Socket.new(&"WRIST")
	wrist.occupant = hand
	arm.sockets = [wrist]

	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var shoulder := Socket.new(&"SHOULDER")
	shoulder.occupant = arm
	torso.sockets = [shoulder]

	var unit := Unit.new(Matrix.new(), Frame.new(torso), cell)
	return {"unit": unit, "torso": torso, "arm": arm, "hand": hand, "pistol": pistol}


func test_destroying_a_limb_drops_its_whole_subtree_as_one_intact_assembly() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var hand: Part = built.hand
	var pistol: Part = built.pistol
	var grid := Grid.new(5, 5)
	var state := CombatState.new(grid, [unit])

	DamageResolver.apply_damage_to_part(arm, 10.0)
	var dropped: Part = DamageResolver.drop_subtree_if_destroyed(arm, state)

	assert_eq(dropped, arm)
	assert_false(
		unit.frame.all_parts().has(arm), "the arm is no longer part of the unit's own assembly"
	)
	assert_true(
		state.grid.field_items[Vector2i(2, 2)].has(arm),
		"the dropped arm must land as a recoverable field item"
	)
	assert_true(
		PartGraph.walk(arm).has(hand) and PartGraph.walk(arm).has(pistol),
		"the arm's own subtree (hand, pistol) must still hang off it, fully assembled"
	)


func test_drop_subtree_if_destroyed_is_a_no_op_for_a_part_still_alive() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var arm: Part = built.arm
	var state := CombatState.new(Grid.new(5, 5), [unit])

	assert_null(DamageResolver.drop_subtree_if_destroyed(arm, state))


func test_drop_subtree_if_destroyed_is_a_no_op_for_the_frames_own_root() -> void:
	var built: Dictionary = _make_armed_unit(Vector2i(2, 2))
	var unit: Unit = built.unit
	var torso: Part = built.torso
	var state := CombatState.new(Grid.new(5, 5), [unit])

	DamageResolver.apply_damage_to_part(torso, 10.0)
	assert_null(
		DamageResolver.drop_subtree_if_destroyed(torso, state),
		"the root has no parent within its own frame to drop it from"
	)
