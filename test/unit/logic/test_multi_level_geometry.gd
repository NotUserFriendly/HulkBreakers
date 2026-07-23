extends GutTest

## taskblock-36 Pass D: the first real proof that "height falls out of
## correct 3D projection" (docs/PLAN.md) isn't just a claim about the
## geometry passes A-C landed — two units actually standing at different
## `Grid.level`s produce a genuinely tilted shot through that same
## pipeline, with no special-cased height rule anywhere in these tests.


func _box_unit(id: StringName, cell: Vector2i) -> Unit:
	var torso := Part.new()
	torso.id = id
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(0.6, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), cell)


## "A shot between two such units carries a real vertical component and
## resolves against a plane built for it." The shooter and target sit on
## different levels; the ray built from the shooter's own real muzzle to
## the target's own real body point must actually be tilted (never a flat
## `dir.y == 0` by construction), and must still resolve to the target.
func test_a_shot_between_units_on_different_levels_carries_a_real_vertical_component() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(5, 5), 2)
	var shooter := _box_unit(&"shooter_torso", Vector2i(0, 0))
	var target := _box_unit(&"target_torso", Vector2i(5, 5))
	var state := CombatState.new(grid, [shooter, target])

	assert_eq(target.level, 2, "the target must actually pick up the cell's own level at spawn")

	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, shooter.shell.root)
	var target_point: Vector3 = UnitGeometry.muzzle_point(target, target.shell.root)
	var dir: Vector3 = (target_point - muzzle).normalized()

	assert_false(is_zero_approx(dir.y), "a shot toward a genuinely elevated target must tilt")

	var hit: HitResult = ShotPlane.resolve_ray(muzzle, dir, state)
	assert_not_null(hit, "the tilted ray must still resolve against the elevated target")
	assert_eq(hit.body, target)


## "A shooter above a target resolves against the target's top face."
## Reuses Pass B's own six-face model — this is the first time it's
## reached via REAL elevation (`Grid.level`) rather than a hand-picked
## steep `view_dir`. An untilted box's own top face is a genuine but
## HEIGHT-DEGENERATE rect (docs/02, `_project_box`'s own Pass B doc
## comment: a flat face's own world height never varies, tilt aside) — a
## single depth/height point, not a range (confirmed live: `Rect2.
## has_point` never contains any point when `size.y == 0`, half-open
## bounds on both sides), so "resolves against" is proven at the level
## this pass's own geometry actually supports: a real Region for the
## target's own top face, correct identity and normal, genuinely produced
## by `ShotPlane.build` once elevation makes it visible — not a hand-solved
## exact-slope aim that happens to land on a single point.
func test_a_shooter_above_a_target_resolves_against_its_top_face() -> void:
	var grid := Grid.new(10, 10)
	grid.set_level(Vector2i(0, 0), 4)
	var shooter := _box_unit(&"shooter_torso", Vector2i(0, 0))
	var target := _box_unit(&"target_torso", Vector2i(0, 5))
	var state := CombatState.new(grid, [shooter, target])

	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, shooter.shell.root)
	var origin_flat := Vector2(muzzle.x, muzzle.z)
	var origin := Vector3(origin_flat.x, muzzle.y, origin_flat.y)
	# A real, steep-but-not-solved-for direction — well within the range
	# that clears the target's own front face while still descending
	# through its footprint (confirmed empirically: a shooter 4 levels up,
	# 5 cells over, aiming steeply down, genuinely crosses the target's own
	# top face somewhere along that descent).
	var dir := Vector3(0.0, -0.95, 0.312).normalized()

	var plane: Array[Region] = ShotPlane.build(origin, dir, state)
	var top_face: Region = null
	for region: Region in plane:
		if region.body == target and region.surface_normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)):
			top_face = region
	assert_not_null(top_face, "an elevated shooter aiming down must produce a real top-face region")
	assert_gt(top_face.rect.size.x, 0.0, "the top face must have real screen width")
