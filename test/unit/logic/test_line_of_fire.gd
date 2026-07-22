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
	grid.blockers[Vector2i(2, 2)] = DataLibrary.get_part(&"wall")

	assert_false(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))


## The predicate must never disagree with the real `ShotPlane`'s own resolved
## first hit — read the actual plane back, don't re-derive the ray math
## (docs/00's own standing rule for spatial systems, applied to a boolean
## predicate instead of a screen-space transform).
func test_has_clear_line_of_fire_matches_the_real_shotplanes_own_first_hit() -> void:
	var grid := Grid.new(5, 6)
	var shooter := _standing_unit(&"shooter", 0.5, Vector2i(2, 0))
	var target := _standing_unit(&"target", 0.5, Vector2i(2, 5))
	var state := CombatState.new(grid, [shooter, target])
	grid.blockers[Vector2i(2, 2)] = DataLibrary.get_part(&"wall")

	var direction := Vector2(target.cell - shooter.cell)
	var plane: Array[Region] = ShotPlane.build(
		Vector2(shooter.cell.x, shooter.cell.y), direction.normalized(), state
	)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target)
	var real_hit: Region = ShotPlane.resolve_projectile(plane, aim_point, shooter.shell.all_parts())

	assert_eq(
		LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state),
		real_hit != null and real_hit.body == target,
		"the predicate must agree with the real plane's own first hit, wall included"
	)
	assert_eq(real_hit.part.id, &"wall", "sanity: the real plane really does resolve to the wall")


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
	assert_true(LineOfFire.has_clear_line_of_fire(shooter, target, shooter.cell, state))
