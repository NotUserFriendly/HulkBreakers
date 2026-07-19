class_name RangeModel
extends RefCounted

## taskblock-19 Pass C: the range model, consolidated onto `WeaponDef`
## (`effective_range`/`max_range`/`min_range`/`min_range_failure`) —
## replacing the old, duplicated `Part.weapon_max_range` as the single
## source every legality check and the AI's own range-awareness reads.
## A weapon with no `WeaponDef` (or a `WeaponDef` that never authored
## these fields, still at their 0.0 defaults) is "unauthored" and behaves
## exactly as before this pass: uncapped range, full accuracy, no
## minimum — every function here treats 0.0 as "not set," never as a
## real zero-range weapon.

## taskblock-19 Pass C1: the floor a fully degraded (at-`max_range`) shot
## scales down to — flagged placeholder, not a tuned design number; only
## "a worse shot, not an impossible one" is specified.
const ACCURACY_FLOOR := 0.35


static func max_range(weapon: Part) -> float:
	if weapon == null or weapon.weapon_def == null:
		return 0.0
	return weapon.weapon_def.max_range


static func min_range(weapon: Part) -> float:
	if weapon == null or weapon.weapon_def == null:
		return 0.0
	return weapon.weapon_def.min_range


## The legality cutoff — replaces the old `weapon.weapon_max_range > 0.0
## and range_cells > int(weapon.weapon_max_range)` check verbatim, just
## reading `WeaponDef.max_range` instead. 0.0 (unauthored) is uncapped.
static func is_in_max_range(weapon: Part, range_cells: int) -> bool:
	var cap: float = max_range(weapon)
	return cap <= 0.0 or range_cells <= int(cap)


## taskblock-19 Pass C2: true when `range_cells` is under `min_range` AND
## the weapon has no dud fallback (`min_range_failure != &"dud"`) — the
## actual legality-blocking condition. A dud-capable weapon is never
## blocked by min range; it fires anyway (see `is_dud`).
static func blocks_min_range(weapon: Part, range_cells: int) -> bool:
	if weapon == null or weapon.weapon_def == null:
		return false
	var floor_range: float = weapon.weapon_def.min_range
	if floor_range <= 0.0 or float(range_cells) >= floor_range:
		return false
	return weapon.weapon_def.min_range_failure != &"dud"


## taskblock-19 Pass C2: true when this shot is firing under min range on
## a dud-capable weapon — legal (never blocked), but the caller should
## skip whatever special payload effect the round would otherwise carry
## and log it as a dud. No explosive/AoE payload system exists yet
## (flagged: this is the hook `min_range_failure` describes, not a
## worked-out detonation to suppress) — today a dud resolves through the
## exact same kinetic `DamageResolver.resolve_shot` cascade any hit does;
## only the legality and the log entry differ.
static func is_dud(weapon: Part, range_cells: int) -> bool:
	if weapon == null or weapon.weapon_def == null:
		return false
	var floor_range: float = weapon.weapon_def.min_range
	if floor_range <= 0.0 or float(range_cells) >= floor_range:
		return false
	return weapon.weapon_def.min_range_failure == &"dud"


## taskblock-19 Pass C1: "at or under effective_range: 1.0. Between
## effective and max: linear down to a floor. Beyond max: no shot" (the
## last case is `is_in_max_range`'s job, not this function's — callers
## that already gated on legality never ask this about an out-of-range
## shot, but it degrades gracefully to the floor rather than
## extrapolating past it if they do). An unauthored `effective_range`
## (0.0) means no accuracy band was ever authored for this weapon — full
## accuracy at any range, same as before this pass.
static func accuracy_multiplier(weapon: Part, range_cells: int) -> float:
	if weapon == null or weapon.weapon_def == null:
		return 1.0
	var effective: float = weapon.weapon_def.effective_range
	if effective <= 0.0:
		return 1.0
	var distance: float = float(range_cells)
	if distance <= effective:
		return 1.0
	var band_end: float = weapon.weapon_def.max_range
	if band_end <= effective:
		# No real band authored beyond effective (uncapped or degenerate
		# max_range) — nothing to degrade toward, stay at full accuracy.
		return 1.0
	if distance >= band_end:
		return ACCURACY_FLOOR
	var t: float = (distance - effective) / (band_end - effective)
	return lerp(1.0, ACCURACY_FLOOR, t)


## taskblock-19 Pass C1: "widens aim scatter" — `accuracy_multiplier`
## itself is the sub-1 ACCURACY fraction the spec describes (1.0 = full
## accuracy, `ACCURACY_FLOOR` = worst), which is the wrong sign to
## multiply a dartboard ring's RADIUS by directly (that would SHRINK it
## as accuracy worsens — backwards). This is the reciprocal: 1.0 at
## effective_range, growing past 1.0 out to `1.0 / ACCURACY_FLOOR` at
## max_range — the actual factor `Dartboard.resolve_scatter`'s own
## `radius_multiplier` parameter wants.
static func dartboard_radius_scale(weapon: Part, range_cells: int) -> float:
	return 1.0 / accuracy_multiplier(weapon, range_cells)
