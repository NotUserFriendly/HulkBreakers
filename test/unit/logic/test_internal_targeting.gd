extends GutTest

## taskblock-20 Pass B: "occlusion gated by knowledge... build the occlusion
## (can't directly click an obscured part) and the aim-at-known-position
## path." Occlusion itself is confirmed, not built — ShotPlane's own
## frontmost-region resolution already can't land a default, center-mass
## shot on an internal sitting behind cladding and a joint (`Knowledge`,
## `InternalTargeting` are new; the resolution math underneath them is not).
## Every claim here is read off a real `DamageResolver.resolve_shot` cascade
## (CLAUDE.md: never re-derive a second copy of the same formula) — a live
## probe found the exact numbers below (reactor mounted at BACK sits partly
## behind torso_cladding's own mounting joint, a hard stop no damage
## punches through) before this file was written.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## A fresh, independently-built armored torso each call — resolve_shot
## mutates part hp in place, so two shots meant to be compared side by side
## (default vs. known-position) must never share one mutable fixture.
func _built() -> Dictionary:
	var torso: Part = DataLibrary.get_part(&"torso")
	var reactor: Part = DataLibrary.get_part(&"reactor")
	var cladding: Part = DataLibrary.get_part(&"torso_cladding")
	PartGraph.attach(reactor, torso, PartGraph.find_free_socket(torso, &"BACK"))
	PartGraph.attach(cladding, torso, PartGraph.find_free_socket(torso, &"CLADDING_TORSO"))

	var shooter := Unit.new(Matrix.new(), Shell.new(DataLibrary.get_part(&"torso")), Vector2i(0, 3))
	var target := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0))
	var state := CombatState.new(Grid.new(5, 5), [shooter, target])
	return {
		"shooter": shooter,
		"target": target,
		"state": state,
		"torso": torso,
		"reactor": reactor,
		"cladding": cladding,
	}


func _plane(built: Dictionary) -> Array[Region]:
	var shooter: Unit = built.shooter
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(built.target.cell - shooter.cell)
	return ShotPlane.build(origin, direction.normalized(), built.state)


func _fire(built: Dictionary, point: Vector2, damage: float) -> Array[ImpactResult]:
	var shooter: Unit = built.shooter
	var origin := Vector2(shooter.cell.x, shooter.cell.y)
	var direction := Vector2(built.target.cell - shooter.cell)
	return DamageResolver.resolve_shot(
		origin,
		direction.normalized(),
		point,
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


## "can't directly click an obscured part" — a default, center-mass shot
## (no knowledge of the internal's own position involved) must never reach
## the reactor: it cascades cladding -> the spine strut -> cladding's own
## mounting joint, which always consumes the round outright.
func test_a_default_center_mass_shot_never_reaches_the_occluded_reactor() -> void:
	var built: Dictionary = _built()
	var plane: Array[Region] = _plane(built)
	var center: Vector2 = ShotPlane.center_of(plane, built.target)

	var results: Array[ImpactResult] = _fire(built, center, 10.0)

	for result: ImpactResult in results:
		assert_ne(result.region.part, built.reactor, "occluded — a default aim must never land here")
	assert_gt(results.size(), 0, "sanity: the shot must hit something along the way")


## "the aim-at-known-position path" — a KNOWING shooter's aim_offset lands
## squarely on the reactor: the same depth cascade (cladding, then the
## reactor itself) does the actual penetration work, no bypass.
func test_a_known_position_aim_reaches_the_reactor_through_the_same_cascade() -> void:
	var built: Dictionary = _built()
	var plane: Array[Region] = _plane(built)
	var center: Vector2 = ShotPlane.center_of(plane, built.target)
	var offset: Variant = InternalTargeting.aim_offset_for(
		built.state, built.shooter, built.target, built.reactor, plane
	)
	assert_not_null(offset, "a known internal, present in the plane, must always resolve an offset")

	var results: Array[ImpactResult] = _fire(built, center + offset, 10.0)

	var hit_reactor := false
	for result: ImpactResult in results:
		if result.region.part == built.reactor:
			hit_reactor = true
	assert_true(hit_reactor, "a known aim must genuinely penetrate through to the reactor")


## "cladding removed -> directly targetable" — the occlusion isn't a
## property of the reactor, only of whatever currently stands in front of
## it. Once cladding is gone (the spine strut's own footprint is narrower
## than the reactor's — a real point clear of it, x=0.07, verified live
## before writing this assertion, same convention test_body_skeleton.gd's
## own equivalent claim uses), a plain frontmost-region lookup finds the
## reactor directly, no known-position offset needed at all.
func test_stripping_cladding_makes_the_reactor_directly_targetable() -> void:
	var built: Dictionary = _built()
	built.cladding.hp = 0
	var plane: Array[Region] = _plane(built)

	var hit: Region = ShotPlane.resolve_projectile(plane, Vector2(0.07, 1.3))

	assert_not_null(hit)
	assert_eq(hit.part, built.reactor)


## A part with no region of its own anywhere in the plane (already
## destroyed, or never mounted) can't be aimed at no matter what's known —
## there's nothing real to compute an offset toward.
func test_a_part_absent_from_the_plane_has_no_aim_offset() -> void:
	var built: Dictionary = _built()
	var never_mounted: Part = DataLibrary.get_part(&"reactor")
	var plane: Array[Region] = _plane(built)

	var offset: Variant = InternalTargeting.aim_offset_for(
		built.state, built.shooter, built.target, never_mounted, plane
	)
	assert_null(offset, "a part with no region in this plane can't be aimed at")
