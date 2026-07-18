class_name RecoilResolver
extends RefCounted

## taskblock-13 Pass D: "recoil widens the dartboard on successive shots
## within a single activation" — `Part.recoil` (dead since it was added)
## is gone; recoil is now COMPUTED, never authored, from the ammo's own
## damage and the gun's own barrel length:
##
##   recoil = base_recoil(ammo.damage) / barrel_factor(WeaponDef.barrel_length)
##
## Applied cumulatively: pull 1 (recoil_step 0) is on-target; pull 2
## (step 1) is widened by one recoil step, pull 3 (step 2) by two, and so
## on — resets to 0 at the start of the next activation (BurstAction's own
## loop counter, never carried across activations). Widens the DARTBOARD
## (aim error) only — the mechanical spread pattern (Pass E) never reads
## this at all, same "keep the two scatters cleanly separate" rule
## Dartboard/SpreadPattern already split on.

## Flagged placeholder — no concrete number was ever specified, only the
## formula's shape ("higher-damage round -> more recoil"). Ask before
## tuning.
const RECOIL_PER_DAMAGE := 0.015


## The base recoil amount a round of this damage imparts, before the
## gun's own barrel divides it down.
static func base_recoil(ammo_damage: float) -> float:
	return ammo_damage * RECOIL_PER_DAMAGE


## `weapon`'s own recoil-per-step, given whatever `ammo_damage` its
## currently-resolved round carries (the same resolved `damage` value
## `AttackAction`/`BurstAction` already compute via `WeaponResolver`, not
## a raw field read). A weapon with no `WeaponDef` (shouldn't happen —
## nothing without one can BURST) falls back to an unscaled barrel_length
## of 1.0 rather than crashing. This is the pure formula only — docs/08
## routes it through `WeaponResolver.resolve_recoil_step` as a real
## StatValue before anything ever acts on it, same pipeline every other
## weapon-derived number uses.
static func step_amount(weapon: Part, ammo_damage: float) -> float:
	var barrel_length: float = weapon.weapon_def.barrel_length if weapon.weapon_def != null else 1.0
	return base_recoil(ammo_damage) / BarrelFactor.value(barrel_length)


## Scales every ring's own radius up by `(1.0 + resolved_step * recoil_step)`.
## `resolved_step` here is already the RESOLVED value (docs/08 provenance
## included) — this function itself is pure array math, not a stat
## resolve. `recoil_step == 0` (the first pull of an activation) returns
## an unchanged copy, never the same array instance (callers may hold
## onto the un-widened resolved scatter independently).
static func widen(scatter: Array[Ring], resolved_step: float, recoil_step: int) -> Array[Ring]:
	if recoil_step <= 0:
		return scatter.duplicate()
	var factor: float = 1.0 + resolved_step * recoil_step
	var widened: Array[Ring] = []
	for ring: Ring in scatter:
		widened.append(Ring.new(ring.radius * factor, ring.weight))
	return widened
