extends GutTest

## taskblock-20 Pass C: "the cascade already traverses depth; make it
## correct for bodies." C1/C2 are confirm-only — the existing depth-sorted
## cascade already does the right thing, tested explicitly rather than left
## implicit. C3 (`Part.hollow`) and C4 (a lodged wound when a round floors
## inside a hollow shell) are the real new mechanics. Every claim here is
## read off a real `DamageResolver.resolve_shot` cascade (CLAUDE.md: never
## re-derive a second copy of the same formula) — live probes found the
## exact numbers below, including a real incidence-angle bug in
## `resolve_impact` that hollow parts' own EXIT faces exposed (a face hit
## from the inside, whose normal points the SAME way as the shot's own
## travel, used to compute as a bogus 180 degrees instead of 0) before this
## file was written.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _box_region(thickness: float, normal: Vector3 = Vector3(0, 0, 1)) -> Region:
	var part := Part.new()
	part.id = &"test_part"
	part.material = &"sheet_steel"
	var region := Region.new(Rect2(-0.1, -0.1, 0.2, 0.2), 1.0, part, normal)
	region.thickness = thickness
	return region


## C1: sheet_steel authors no `dt_curve`, so `dt_at()` always falls back to
## the flat `dt` field regardless of `region.thickness` — a soft material
## deducts little REGARDLESS of how physically thick its own box is; box
## size never sneaks in as a second, undeclared attenuation factor.
func test_effective_dt_is_the_same_material_regardless_of_box_thickness() -> void:
	var table: MaterialTable = DataLibrary.material_table()

	var thin: Region = _box_region(0.05)
	var thick: Region = _box_region(6.0)

	var thin_impact: ImpactResult = DamageResolver.resolve_impact(Vector2(0, -1), 2.0, thin, table)
	var thick_impact: ImpactResult = DamageResolver.resolve_impact(
		Vector2(0, -1), 2.0, thick, table
	)

	assert_eq(thin_impact.effective_dt, thick_impact.effective_dt, "thickness must not attenuate")
	assert_eq(thin_impact.outcome, thick_impact.outcome, "same material, same outcome either way")


## C1's other half: a real material comparison — high-DT stops a round a
## soft one lets straight through, confirming the MATERIAL (not size) is
## what actually governs, using the same-thickness boxes deliberately (the
## test above already isolates thickness as a non-factor).
func test_a_high_dt_material_stops_what_a_soft_one_lets_through() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	var hard: Region = _box_region(0.1)
	hard.part.material = &"reactive"  # dt 12.0
	var soft: Region = _box_region(0.1)
	soft.part.material = &"artificial_muscle"  # dt 1.0

	var hard_impact: ImpactResult = DamageResolver.resolve_impact(Vector2(0, -1), 5.0, hard, table)
	var soft_impact: ImpactResult = DamageResolver.resolve_impact(Vector2(0, -1), 5.0, soft, table)

	assert_ne(hard_impact.outcome, Enums.Outcome.PENETRATE, "the hard plate must stop this round")
	assert_eq(soft_impact.outcome, Enums.Outcome.PENETRATE, "the soft material barely slows it")


func _lined_up_units() -> Dictionary:
	var front_box := Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.1))
	var front_part := Part.new()
	front_part.id = &"front_target"
	front_part.material = &"sheet_steel"
	front_part.hp = 20
	front_part.max_hp = 20
	front_part.volume = [front_box]

	var back_box := Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.1))
	var back_part := Part.new()
	back_part.id = &"back_target"
	back_part.material = &"sheet_steel"
	back_part.hp = 20
	back_part.max_hp = 20
	back_part.volume = [back_box]

	var shooter := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 5))
	var front_unit := Unit.new(Matrix.new(), Shell.new(front_part), Vector2i(0, 3))
	var back_unit := Unit.new(Matrix.new(), Shell.new(back_part), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(6, 6), [shooter, front_unit, back_unit])
	return {
		"shooter": shooter,
		"front_unit": front_unit,
		"back_unit": back_unit,
		"front_part": front_part,
		"back_part": back_part,
		"state": state,
	}


## C2: "route through-shots through ricochet-continuation at bend 0; no
## separate overpen system" — there already IS no separate system: the same
## depth-sorted plane includes every unit along the line of fire, so a round
## with enough leftover damage to clear the front unit's own part just keeps
## walking the SAME cascade into whatever's standing behind it.
func test_a_through_shot_exits_the_front_unit_and_hits_the_unit_behind() -> void:
	var built: Dictionary = _lined_up_units()
	var shooter: Unit = built.shooter
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(built.front_unit.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), built.state)
	var center: Vector2 = ShotPlane.center_of(plane, built.front_unit)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction.normalized(),
		center,
		15.0,
		0.0,
		built.state,
		built.state.material_table,
		built.state.rng,
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		shooter.shell.all_parts()
	)

	var hit_parts: Array[Part] = []
	for result: ImpactResult in results:
		hit_parts.append(result.region.part)
	assert_true(hit_parts.has(built.front_part), "must hit the near unit first")
	assert_true(
		hit_parts.has(built.back_part), "leftover damage must carry through to the far unit"
	)


func _hollow_shell_unit(shooter_distance: int = 3) -> Dictionary:
	var shell_box := Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.1))
	var shell := Part.new()
	shell.id = &"test_hollow_shell"
	shell.material = &"sheet_steel"  # dt 3.0
	shell.hollow = true
	shell.hp = 20
	shell.max_hp = 20
	shell.volume = [shell_box]

	var shooter := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, shooter_distance))
	var target := Unit.new(Matrix.new(), Shell.new(shell), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [shooter, target])
	return {"shooter": shooter, "target": target, "shell": shell, "state": state}


func _fire_at_shell(built: Dictionary, damage: float) -> Array[ImpactResult]:
	var shooter: Unit = built.shooter
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(built.target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), built.state)
	var center: Vector2 = ShotPlane.center_of(plane, built.target)
	return DamageResolver.resolve_shot(
		origin,
		direction.normalized(),
		center,
		damage,
		0.0,
		built.state,
		built.state.material_table,
		built.state.rng,
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		shooter.shell.all_parts()
	)


## C3: a `hollow` part's own near AND far faces both register as real,
## separate Regions of the SAME part — struck entering and again exiting,
## not one blended hit — when the round carries enough damage to clear both.
func test_a_hollow_part_with_enough_damage_is_struck_entering_and_exiting() -> void:
	var built: Dictionary = _hollow_shell_unit()

	var results: Array[ImpactResult] = _fire_at_shell(built, 15.0)

	assert_eq(results.size(), 2, "the shell's own near and far faces, two separate impacts")
	for result: ImpactResult in results:
		assert_eq(result.region.part, built.shell)
		assert_eq(result.outcome, Enums.Outcome.PENETRATE)
	assert_eq(built.shell.wounds, [] as Array[StringName], "a clean through-shot lodges nothing")


## C4 (the .22 case): a round that beats the entry face's own DT but leaves
## too little to also clear the identical exit face's DT floors inside the
## shell — `&"lodged_bullet"` on the part it was resolving against, logged
## the same way every other world-changing consequence is.
func test_a_round_that_floors_inside_a_hollow_shell_inflicts_a_lodged_wound() -> void:
	var built: Dictionary = _hollow_shell_unit()

	# sheet_steel dt=3: 4.0 clears the entry (spill 1.0) but not the
	# identical-material exit (1.0 < 3.0) — verified live before writing
	# this assertion.
	var results: Array[ImpactResult] = _fire_at_shell(built, 4.0)

	assert_eq(results.size(), 2, "it reached the exit face, just couldn't clear it")
	assert_eq(results[0].outcome, Enums.Outcome.PENETRATE, "the entry face gave way")
	assert_eq(results[1].wound_inflicted, &"lodged_bullet")
	assert_has(built.shell.wounds, &"lodged_bullet")


## The same lodged-wound condition must reach the combat log — docs/09 "if
## it changed the world, it's in the log" — independent of whether the part
## was actually destroyed (a lodged bullet can land on a part that survives
## comfortably above 0 hp).
func test_a_lodged_wound_is_logged_independent_of_part_destruction() -> void:
	var built: Dictionary = _hollow_shell_unit()
	var shooter: Unit = built.shooter
	var sink := MemorySink.new()
	built.state.combat_log.add_sink(sink)

	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(built.target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), built.state)
	var center: Vector2 = ShotPlane.center_of(plane, built.target)
	ShotResolution.resolve_and_log_point(
		built.state, shooter, origin, direction, center, 4.0, 0.0, 0.0, null
	)

	var wound_events: Array[LogEvent] = sink.events_of_kind(&"wound_inflicted")
	assert_eq(wound_events.size(), 1)
	assert_eq(wound_events[0].data.get("wound"), &"lodged_bullet")
	assert_gt(built.shell.hp, 0, "the shell survives this hit comfortably — the wound isn't a kill")


## No lodged wound when the round never actually got inside anything —
## stopping cold on a SOLID (non-hollow) part is just "stopped," not
## "lodged": there was never a far face to fail to reach.
func test_a_round_stopped_on_a_solid_part_never_lodges_a_wound() -> void:
	var solid := Part.new()
	solid.id = &"solid_wall"
	solid.material = &"reactive"  # dt 12.0 — easily stops a weak round
	solid.hp = 20
	solid.max_hp = 20
	solid.volume = [Box.new(Vector3.ZERO, Vector3(0.3, 0.3, 0.1))]

	var shooter := Unit.new(Matrix.new(), Shell.new(Part.new()), Vector2i(0, 3))
	var target := Unit.new(Matrix.new(), Shell.new(solid), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [shooter, target])
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var center: Vector2 = ShotPlane.center_of(plane, target)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction.normalized(),
		center,
		2.0,
		0.0,
		state,
		state.material_table,
		state.rng,
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		shooter.shell.all_parts()
	)

	assert_eq(results[-1].wound_inflicted, &"")
	assert_eq(solid.wounds, [] as Array[StringName])


## Determinism through a multi-layer traversal (CLAUDE.md: same seed, same
## battle, always) — a hollow shell's own two-region cascade is exactly the
## kind of multi-layer path a seeded RNG must reproduce bit-for-bit.
func test_multi_layer_traversal_is_deterministic_across_runs_with_the_same_seed() -> void:
	var first: Dictionary = _hollow_shell_unit()
	first.state.rng.seed = 4242
	var second: Dictionary = _hollow_shell_unit()
	second.state.rng.seed = 4242

	var first_results: Array[ImpactResult] = _fire_at_shell(first, 4.0)
	var second_results: Array[ImpactResult] = _fire_at_shell(second, 4.0)

	assert_eq(first_results.size(), second_results.size())
	for i in range(first_results.size()):
		assert_eq(first_results[i].outcome, second_results[i].outcome, "impact %d outcome" % i)
		assert_eq(
			first_results[i].part_damage, second_results[i].part_damage, "impact %d damage" % i
		)
	assert_eq(first.shell.wounds, second.shell.wounds)
