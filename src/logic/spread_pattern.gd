class_name SpreadPattern
extends RefCounted

## taskblock-13 Pass C/E: the gun's own MECHANICAL multi-projectile
## pattern (a shotgun's pellets, `AmmoDef.projectile_num`) — deliberately
## a SEPARATE scatter from `Dartboard`'s aim-error roll (docs: "keep the
## two scatters cleanly separate — the whole point of the taskblock-10
## split"). One pull's dartboard roll picks a CENTER; this samples
## `ammo.projectile_num` points around THAT center, mechanical, not aim
## error — a burst's later, recoil-widened pulls still throw the same
## TIGHT pellet spread around wherever each pull's own aim error landed.

## Flagged placeholder — no concrete pattern-size number was ever
## specified, only the shape of the formula (docs: "pattern_size =
## base_pattern(mechanical_accuracy) / barrel_factor(barrel_length)").
## Ask before tuning.
const BASE_PATTERN_RADIUS := 0.15


## `ammo == null` or a single-projectile round (`projectile_num <= 1`)
## collapses to exactly `center` — "a slug collapses to pure dartboard"
## (AmmoDef's own doc comment), no mechanical scatter at all.
static func sample(
	center: Vector2, weapon: Part, ammo: AmmoDef, rng: RandomNumberGenerator
) -> Array[Vector2]:
	if ammo == null or ammo.projectile_num <= 1:
		return [center]
	var radius: float = pattern_radius(weapon)
	var points: Array[Vector2] = []
	for i in range(ammo.projectile_num):
		# Uniform-in-area, same convention as Dartboard.sample.
		var r: float = sqrt(rng.randf()) * radius
		var theta: float = rng.randf_range(0.0, TAU)
		points.append(center + Vector2(r * cos(theta), r * sin(theta)))
	return points


## "pattern_size = base_pattern(mechanical_accuracy) /
## barrel_factor(barrel_length)" (taskblock-13 Pass E, verbatim) — a
## steadier gun throws a tighter pattern before barrel length even
## enters it; a longer barrel then tightens it further, sharing
## `BarrelFactor` with `RecoilResolver` (docs: "both are 'longer barrel =
## better,' sharing the curve keeps them coherent"). A WeaponDef-less
## weapon (shouldn't happen — projectile_num > 1 implies a real gun)
## falls back to the unscaled base radius rather than crashing.
## tb34 Pass B: made public (was `_pattern_radius`) — the aim view's own
## pellet-spread circle (`AimController.pellet_circle_radius`) reads the
## exact same resolved size `sample()` itself scatters around, never a
## second, re-derived pattern number.
static func pattern_radius(weapon: Part) -> float:
	if weapon.weapon_def == null:
		return BASE_PATTERN_RADIUS
	var base: float = BASE_PATTERN_RADIUS * (1.0 - weapon.weapon_def.mechanical_accuracy)
	return base / BarrelFactor.value(weapon.weapon_def.barrel_length)
