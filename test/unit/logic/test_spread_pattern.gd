extends GutTest

## taskblock-13 Pass C/E: SpreadPattern — the gun's own MECHANICAL
## multi-projectile pattern, deliberately separate from Dartboard's
## aim-error scatter.


func _weapon(mechanical_accuracy: float, barrel_length: float) -> Part:
	var weapon := Part.new()
	weapon.id = &"test_gun"
	weapon.weapon_def = WeaponDef.new()
	weapon.weapon_def.mechanical_accuracy = mechanical_accuracy
	weapon.weapon_def.barrel_length = barrel_length
	return weapon


func _ammo(projectile_num: int) -> AmmoDef:
	var ammo := AmmoDef.new()
	ammo.id = &"test_ammo"
	ammo.projectile_num = projectile_num
	return ammo


## "a slug collapses to pure dartboard" — no ammo, or a single-projectile
## round, always returns exactly the center point.
func test_no_ammo_or_a_single_projectile_round_collapses_to_the_center() -> void:
	var weapon := _weapon(0.5, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var center := Vector2(2.0, 3.0)

	assert_eq(SpreadPattern.sample(center, weapon, null, rng), [center])
	assert_eq(SpreadPattern.sample(center, weapon, _ammo(1), rng), [center])


func test_a_multi_projectile_round_samples_exactly_projectile_num_points() -> void:
	var weapon := _weapon(0.5, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var points: Array[Vector2] = SpreadPattern.sample(Vector2.ZERO, weapon, _ammo(9), rng)

	assert_eq(points.size(), 9)


## "a longer barrel yields a tighter spread pattern for the same gun/ammo."
func test_longer_barrel_yields_a_tighter_pattern() -> void:
	var short_barrel := _weapon(0.5, 0.3)
	var long_barrel := _weapon(0.5, 3.0)
	var ammo := _ammo(200)  # large sample: compare actual spread, not luck
	var rng_short := RandomNumberGenerator.new()
	rng_short.seed = 7
	var rng_long := RandomNumberGenerator.new()
	rng_long.seed = 7

	var short_points: Array[Vector2] = SpreadPattern.sample(
		Vector2.ZERO, short_barrel, ammo, rng_short
	)
	var long_points: Array[Vector2] = SpreadPattern.sample(
		Vector2.ZERO, long_barrel, ammo, rng_long
	)

	var short_max: float = 0.0
	var long_max: float = 0.0
	for p: Vector2 in short_points:
		short_max = maxf(short_max, p.length())
	for p: Vector2 in long_points:
		long_max = maxf(long_max, p.length())

	assert_lt(long_max, short_max, "the long barrel's own pattern must not spread as far")


## "barrel length does not affect the dartboard" — SpreadPattern never
## touches Dartboard's own resolved Ring radii; proven by construction
## (SpreadPattern.sample takes no Ring array at all, only a center point
## and its own separate radius), asserted here as a behavioral guarantee:
## Dartboard.resolve_scatter is barrel-length-blind.
func test_barrel_length_never_changes_the_dartboard_rings() -> void:
	var short_barrel := _weapon(1.0, 0.3)
	var long_barrel := _weapon(1.0, 3.0)
	short_barrel.scatter = [Ring.new(0.2, 1.0)]
	long_barrel.scatter = [Ring.new(0.2, 1.0)]

	var short_rings: Array[Ring] = Dartboard.resolve_scatter(short_barrel)
	var long_rings: Array[Ring] = Dartboard.resolve_scatter(long_barrel)

	assert_almost_eq(short_rings[0].radius, long_rings[0].radius, 0.0001)


## "a single-projectile weapon is unaffected by pattern scaling" — however
## extreme mechanical_accuracy/barrel_length get, a slug (or no ammo at
## all) still always collapses to exactly the center.
func test_a_single_projectile_weapon_is_unaffected_by_pattern_scaling() -> void:
	var extreme := _weapon(0.0, 0.01)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var center := Vector2(5.0, -2.0)

	assert_eq(SpreadPattern.sample(center, extreme, _ammo(1), rng), [center])
