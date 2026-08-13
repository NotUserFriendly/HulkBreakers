extends GutTest

## tb33 Pass A: `LineOfFire` answers a different question than `LoS` — "would
## a shot from here actually hit the target," resolved against the same
## `ShotPlane` a real `AttackAction` fires through, not a second approximation
## of the geometry. These tests exercise the predicate directly; the AI-level
## consumers (fire gate, engagement scorer, approach fallback) have their own
## coverage in `test/unit/logic/ai/`.


func _standing_unit(id: StringName, half_width: float, cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id)
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(half_width * 2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell, 0)


func test_has_clear_line_of_fire_is_true_with_nothing_in_the_way() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])

	assert_true(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## Same wall-part fixture `test_shot_plane.gd`'s own
## `test_a_wall_part_between_shooter_and_target_blocks_the_shot` uses (BR30.10:
## a real MapGen wall is a `grid.blockers` Part, not just opaque terrain).
func test_has_clear_line_of_fire_is_false_when_a_wall_blocks_the_shot() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.place_blocker(Vector2i(2, 2), DataLibrary.get_part(&"wall"))

	assert_false(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## The predicate must never disagree with the real `ShotPlane`'s own resolved
## first hit — read the actual plane back, don't re-derive the ray math
## (docs/00's own standing rule for spatial systems, applied to a boolean
## predicate instead of a screen-space transform).
##
## **tb68 Pass D: the self-exclusion list was the pre-`BR36.01` one, and this
## file's fixture is what hid it.** The oracle excluded
## `shooter.shell.all_parts()`; every production path — `ShotResolution`,
## `AimController`, `Overwatch`, `DamageResolver.body_of` — excludes
## `all_parts_with_joints()`, which is the list `BR36.01` established a
## shot-plane self-exclusion needs ("every region this body could produce").
## The two are **identical for a socket-less torso**, so the divergence could
## not surface here: `walk_with_joints` emits a joint only for an OCCUPIED
## socket, and this fixture has none. Put a real assembled shell through the
## same test and the plane resolves to the shooter's own `ammo_rack_joint`
## instead of the wall. An oracle that is not the production call is not
## reading the plane back, which is the one thing this test claims to do.
func test_has_clear_line_of_fire_matches_the_real_shotplanes_own_first_hit() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.place_blocker(Vector2i(2, 2), DataLibrary.get_part(&"wall"))

	var direction := Vector2(target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(shooter.cell.x, 0.0, shooter.cell.y),
		Vector3(direction.normalized().x, 0.0, direction.normalized().y),
		state
	)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	var real_hit: Region = ShotPlane.resolve_projectile(
		plane, aim_point, shooter.shell.all_parts_with_joints()
	)

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		real_hit != null and real_hit.body == target,
		"the predicate must agree with the real plane's own first hit, wall included"
	)
	assert_eq(real_hit.part.id, &"wall", "sanity: the real plane really does resolve to the wall")


## **The same parity claim, against a body that has joints at all** (tb68 Pass D).
##
## The test above cannot see the exclusion list it passes, because its shooter is a
## single socket-less torso and `all_parts()` and `all_parts_with_joints()` return
## the same array for it. This one puts the real assembled chaingunner on the board,
## so the shooter has 48 boxes and occupied sockets, and the joint regions the
## pre-`BR36.01` list omitted are actually present to be wrongly hit.
func test_the_parity_holds_for_a_shooter_whose_body_has_joints() -> void:
	var grid := Grid.new(5, 6)
	var shooter: Unit = RealUnit.build(self, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.place_blocker(Vector2i(2, 2), DataLibrary.get_part(&"wall"))

	var excluded: Array[Part] = shooter.shell.all_parts_with_joints()
	assert_gt(
		excluded.size(),
		shooter.shell.all_parts().size(),
		"sanity: a real shell has occupied sockets, so the two lists must differ here"
	)

	var direction := Vector2(target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(
		Vector3(shooter.cell.x, 0.0, shooter.cell.y),
		Vector3(direction.normalized().x, 0.0, direction.normalized().y),
		state
	)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	var real_hit: Region = ShotPlane.resolve_projectile(plane, aim_point, excluded)

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		real_hit != null and real_hit.body == target,
		"the predicate must agree with the real plane, for a body that has joints"
	)
	assert_eq(
		real_hit.part.id,
		&"wall",
		"the wall, not one of the shooter's own joint regions at point-blank range"
	)


## Regression: with nothing but open terrain, LOF and LOS must agree exactly
## (they're the same claim once no cover geometry is involved) — the AI's
## swap from LOS to LOF must not change behavior in the common open-field case.
func test_open_field_line_of_fire_matches_line_of_sight() -> void:
	var grid := Grid.new(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(0, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(9, 9))
	var state := CombatState.new(grid, [shooter, target])

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		LoS.has_los(grid, shooter.cell, target.cell)
	)


## taskblock-37 Pass A: `first_hit` builds its plane from `ShotPlane.
## elevation_for`, a real level delta rather than the old hardcoded-flat
## `Vector3(x, 0.0, y)` — a target on a raised cell must still be the shot's
## own first hit, not silently lost once the ray actually tilts.
func test_has_clear_line_of_fire_is_true_against_an_elevated_target() -> void:
	var grid := GridFixture.flat(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	GridFixture.place_floor(grid, Vector2i(2, 5), 3)
	var state := CombatState.new(grid, [shooter, target])

	assert_eq(target.level, 3, "the target must actually pick up the cell's own level at spawn")
	assert_true(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## tb35 Pass B (BR34.06/BR27.02): reconstructs the logged failure — a real
## target straight ahead, plus a wall several cells BEHIND the shooter
## (present in the plane on purpose, `ShotPlane.build`'s own doc comment).
## Unfloored, the rearward wall's negative depth sorted first and won every
## time; `_first_hit_excluding`'s floor must resolve forward instead.
func test_first_hit_never_resolves_to_a_wall_behind_the_shooter() -> void:
	var grid := Grid.new(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(5, 5))
	var target := _standing_unit(&"target", 0.5, Vector2i(5, 9))
	var state := CombatState.new(grid, [shooter, target])
	grid.place_blocker(Vector2i(5, 1), DataLibrary.get_part(&"wall"))

	var hit: Region = LineOfFire.first_hit(shooter, target, shooter.cell, state)

	assert_not_null(hit, "a wall behind the shooter must never eclipse a real forward target")
	assert_eq(hit.body, target)
	assert_true(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## tb35 Pass A3 (BR27.09): `cached_first_hit` must agree with the plain,
## uncached `first_hit` exactly — a memo is only worth adding if it can
## never change the answer, just how many times the answer gets computed.
func test_cached_first_hit_agrees_with_the_uncached_resolution() -> void:
	var grid := Grid.new(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 9))
	var state := CombatState.new(grid, [shooter, target])
	grid.place_blocker(Vector2i(2, 4), DataLibrary.get_part(&"wall"))

	var uncached: Region = LineOfFire.first_hit(shooter, target, shooter.cell, state)
	var cache: Dictionary = {}
	var cached: Region = LineOfFire.cached_first_hit(shooter, target, shooter.cell, state, cache)

	assert_eq(cached.part.id, uncached.part.id)
	assert_eq(cached.body, uncached.body)


## A second lookup for the same cell must reuse the memoized Region
## (identity, not just an equal-looking rebuild) rather than resolving
## again.
func test_cached_first_hit_reuses_the_same_region_on_a_repeat_lookup() -> void:
	var grid := Grid.new(10, 10)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 9))
	var state := CombatState.new(grid, [shooter, target])
	var cache: Dictionary = {}

	var first: Region = LineOfFire.cached_first_hit(shooter, target, shooter.cell, state, cache)
	var second: Region = LineOfFire.cached_first_hit(shooter, target, shooter.cell, state, cache)

	assert_eq(cache.size(), 1, "one cell queried, one memo entry")
	assert_true(first == second, "the second lookup must return the SAME Region, not a rebuilt one")


## `has_clear_line_of_fire` with a cache supplied must agree with the
## default (uncached) call for the same geometry.
func test_has_clear_line_of_fire_agrees_with_and_without_a_cache() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.place_blocker(Vector2i(2, 2), DataLibrary.get_part(&"wall"))
	var cache: Dictionary = {}

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state, cache)
	)
