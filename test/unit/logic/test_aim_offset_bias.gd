extends GutTest

## taskblock-51 (`BR51.01`): **does the reticle's frame agree with the resolver's?**
##
## The supervisor reports sniper and chaingun shots landing *consistently left* of the aim
## point, with a fixed aim camera sitting back and right of the shooter. A consistent,
## directional error is a transform that has not been undone — not a scatter roll.
##
## The two frames that have to agree:
##
## - **The reticle** places `reticle_offset` as `aim_point_from_ray(...) - center_of(plane)`,
##   where `aim_point_from_ray` works in a plane anchored on the shooter and target
##   **cells**.
## - **The resolver** rebuilds `center_of(plane) + aim_offset`, where the plane is projected
##   from the shooter's **actual firing geometry**.
##
## If those two planes share axes but not origins, offset zero means two different points
## and every shot inherits the same lateral shift. This measures that directly rather than
## inferring it: it aims a ray at the target's own true centre and asks what the reticle
## maths thinks the offset is. **Zero is correct; anything else is the bias, and its sign
## says which way.**

const WIDTH := 16
const ROWS := 16


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _armed(cell: Vector2i, squad: int) -> Unit:
	return DeepStrike.assemble_reference_humanoid(Matrix.new(), cell, squad)


## The lateral component of the offset the reticle would record for a ray that already
## points exactly at the target's own resolved centre. **It should be zero.**
func _bias_for(shooter_cell: Vector2i, target_cell: Vector2i) -> float:
	var shooter: Unit = _armed(shooter_cell, 0)
	var target: Unit = _armed(target_cell, 1)
	var state := CombatState.new(GridFixture.flat(WIDTH, ROWS), [shooter, target])
	var weapon: Part = ActionCatalog.provider_for(shooter, &"shoot")
	if weapon == null:
		return NAN

	# Exactly what `AttackAction` does: origin and direction both anchored on the real
	# muzzle. taskblock-27 Pass A1 fixed this mismatch *inside* the action.
	var muzzle: Vector3 = UnitGeometry.muzzle_point(shooter, weapon)
	var origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
	var direction := Vector2(target_cell) - origin
	var elevation: Dictionary = ShotPlane.elevation_for(
		origin, muzzle.y, shooter.cell, target_cell, state.grid
	)
	var plane: Array[Region] = ShotPlane.build(elevation.origin, elevation.direction, state)
	var center: Vector2 = ShotPlane.center_of(plane, target)

	# And exactly what the reticle does: a plane anchored on the shooter and target CELLS.
	# A ray aimed at the resolver's own dead centre should read back as offset zero.
	var world_center: Vector3 = AimPlaneGeometry.world_point(shooter_cell, target_cell, center)
	# **Offset back along the fire line**, not along a fixed world axis: a shot travelling
	# down the X axis made a `(0, 6, 6)` offset parallel to the aim plane, and
	# `aim_point_from_ray` correctly returned null — a NaN that read as a missing
	# measurement rather than as a bad ray. Backing off toward the shooter is non-parallel
	# by construction for every geometry.
	var back: Vector3 = (
		Vector3(shooter_cell.x - target_cell.x, 0.0, shooter_cell.y - target_cell.y).normalized()
	)
	var ray_origin: Vector3 = world_center + back * 4.0 + Vector3(0.0, 4.0, 0.0)
	var ray_dir: Vector3 = (world_center - ray_origin).normalized()
	var hit: Variant = AimPlaneGeometry.aim_point_from_ray(
		shooter_cell, target_cell, ray_origin, ray_dir
	)
	if hit == null:
		return NAN
	return ((hit as Vector2) - center).x


## **The measurement.** Reported for several geometries, because a bias that only appears
## on one axis is a different defect from one that appears on all of them — and a straight
## shot down a row shares a coordinate at every step, which hides exactly this class of
## error.
func test_the_reticle_and_the_resolver_agree_on_dead_centre() -> void:
	var cases: Array[Array] = [
		[Vector2i(2, 8), Vector2i(10, 8)],
		[Vector2i(8, 2), Vector2i(8, 10)],
		[Vector2i(2, 2), Vector2i(9, 9)],
		[Vector2i(10, 3), Vector2i(3, 10)],
	]
	var worst := 0.0
	for case: Array in cases:
		var bias: float = _bias_for(case[0] as Vector2i, case[1] as Vector2i)
		gut.p("shooter %s -> target %s: lateral bias %.4f" % [case[0], case[1], bias])
		assert_false(is_nan(bias), "%s -> %s produced no measurement at all" % [case[0], case[1]])
		if not is_nan(bias):
			worst = maxf(worst, absf(bias))
	assert_lt(
		worst,
		0.01,
		(
			"the reticle's dead centre is not the resolver's dead centre — worst lateral "
			+ "bias %.4f cells. A player aiming at centre mass fires that far off." % worst
		)
	)
