class_name MeleeReach
extends RefCounted

## taskblock-25 Pass A (docs/PLAN.md "Phase M — Melee"): reach = shell +
## weapon, and the two play different roles. `weapon_length` is FREE reach
## — consumed first, no lean, no exposure. `shell_reach` is the EXPOSURE
## BUDGET spent leaning to close whatever the weapon alone doesn't cover;
## every bit of lean spent is torso moved past cover. Pure distance math
## only — nothing here mutates a Unit or checks overwatch (see
## `MeleeDelivery` for that).


## The weapon's own free reach, or 0.0 for an unarmed strike / a weapon
## with no authored `WeaponDef` (a bare-fisted punch leans on shell_reach
## alone).
static func weapon_length(weapon: Part) -> float:
	if weapon == null or weapon.weapon_def == null:
		return 0.0
	return weapon.weapon_def.weapon_length


## Total reach a striker threatens without stepping into a new cell —
## `weapon_length` (free) plus `shell.shell_reach` (leanable).
static func total_reach(shell: Shell, weapon: Part) -> float:
	return weapon_length(weapon) + shell.shell_reach


## How much lean a strike at `distance` needs to spend, after the weapon's
## own free length is subtracted first. 0.0 when the weapon alone already
## covers `distance` — no lean, no exposure. Not clamped to any shell's
## `shell_reach`: a result exceeding it means `distance` is beyond
## `total_reach()` altogether (the caller's step-in case, see
## `MeleeDelivery.find_step_in_cell`), not a partial lean.
static func lean_needed(weapon: Part, distance: float) -> float:
	return maxf(0.0, distance - weapon_length(weapon))


## True if `distance` is closeable from the current cell at all (weapon
## length plus the full leanable `shell_reach` covers it) — false means a
## real step-in is required.
static func in_reach(shell: Shell, weapon: Part, distance: float) -> bool:
	return distance <= total_reach(shell, weapon)
