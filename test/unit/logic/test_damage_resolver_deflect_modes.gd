extends GutTest

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): the three deflect
## RESPONSES `resolve_shot`'s own DEFLECT branch can take — split out of
## test_damage_resolver.gd (which was already at the file-length cap), not
## a separate concern: same fixture shape as that file's own
## test_depth_cap_of_zero_stops_a_deflection_from_spawning_any_ricochet /
## test_damage_floor_stops_a_deflection_from_spawning_a_ricochet.


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


func _find_region(plane: Array[Region], part: Part) -> Region:
	for region: Region in plane:
		if region.part == part:
			return region
	return null


func _deflecting_fixture() -> Dictionary:
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
	var plane: Array[Region] = ShotPlane.build(origin, direction, state)
	var region := _find_region(plane, cover)
	var aim_point: Vector2 = region.rect.get_center()

	var probe := DamageResolver.resolve_impact(direction, 3.0, region, table)
	assert_eq(probe.outcome, Enums.Outcome.DEFLECT, "fixture must actually deflect")

	return {
		"state": state, "table": table, "origin": origin, "direction": direction, "point": aim_point
	}


## taskblock-25 Pass C: stab's own DEFLECT response — "slides sideways
## along the surface to an adjacent point, not an angular bounce."
func test_slide_deflect_mode_resolves_an_adjacent_point_not_a_ricochet() -> void:
	var f: Dictionary = _deflecting_fixture()

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		f.origin,
		f.direction,
		f.point,
		3.0,
		0.0,
		f.state,
		f.table,
		_rng(1),
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		[],
		0.0,
		0.0,
		0.0,
		DamageResolver.DEFLECT_MODE_SLIDE
	)

	assert_eq(
		results.size(),
		2,
		"the original deflect plus exactly one adjacent-point resolution, never a ricochet chain"
	)
	assert_eq(results[0].outcome, Enums.Outcome.DEFLECT)
	assert_eq(
		results[1].region.part.id, &"cover", "the slid point must still land on the same surface"
	)


## taskblock-25 Pass C: hold/slash's own DEFLECT response — "no deflect at
## all: chew through or nothing." The exact same fixture that ricochets by
## default and slides under `DEFLECT_MODE_SLIDE` must produce nothing
## further at all under `DEFLECT_MODE_NONE`.
func test_none_deflect_mode_never_bounces_or_slides() -> void:
	var f: Dictionary = _deflecting_fixture()

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		f.origin,
		f.direction,
		f.point,
		3.0,
		0.0,
		f.state,
		f.table,
		_rng(1),
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		[],
		0.0,
		0.0,
		0.0,
		DamageResolver.DEFLECT_MODE_NONE
	)

	assert_eq(
		results.size(), 1, "no deflect at all: chew through or nothing, never a follow-up hit"
	)
	assert_eq(results[0].outcome, Enums.Outcome.DEFLECT)


## taskblock-26 (CC, re-diagnosing A2 "muzzle origin inside the shooter's
## own armor"): `_resolve_slide` re-searches the WHOLE plane from index 0
## (the lateral nudge can reveal something NEARER than the original hit) —
## without the shooter's own parts excluded on that re-search, a stab that
## deflects and slides at point-blank range can land back on the
## shooter's own body, which sits at the ray's own (near-zero-depth)
## origin. A shooter unit occupying the exact origin cell, wide enough to
## cover the nudged lateral point, proves the exclusion actually reaches
## this second lookup.
func test_slide_deflect_never_lands_back_on_the_shooters_own_excluded_body() -> void:
	var f: Dictionary = _deflecting_fixture()
	var shooter_torso := Part.new()
	shooter_torso.id = &"shooter_torso"
	shooter_torso.hp = 10
	shooter_torso.max_hp = 10
	# Wide enough that its own projected rect actually spans the slide's
	# nudged lateral point below — a narrower box (matching the cover's own
	# size) wouldn't reach far enough to reproduce the regression at all.
	shooter_torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(6.0, 1.0, 0.6))]
	var shooter := Unit.new(Matrix.new(), Shell.new(shooter_torso), Vector2i(2, 0))
	f.state.add_unit(shooter)

	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		f.origin,
		f.direction,
		f.point,
		3.0,
		0.0,
		f.state,
		f.table,
		_rng(1),
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		[shooter_torso],
		0.0,
		0.0,
		0.0,
		DamageResolver.DEFLECT_MODE_SLIDE
	)

	assert_eq(results.size(), 2, "the original deflect plus exactly one adjacent-point resolution")
	for result: ImpactResult in results:
		assert_ne(
			result.region.part,
			shooter_torso,
			"the slide must never land back on the shooter's own excluded body"
		)
