class_name WeaponDef
extends Resource

## taskblock-13 Pass A: gun-model stats that had nowhere to live — embedded
## on a weapon `Part` (`Part.weapon_def`), null for every non-weapon part so
## it carries no dead weapon fields. A plain sub-resource, same posture as
## `Box`/`Ring` (embedded on the owning Part's own `.tres`, not an
## independently id-addressed DataLibrary type the way `AmmoDef`/
## `MaterialEntry` are) — a gun model's own tunables are authored once,
## alongside that one gun, never shared or looked up by key the way a
## material is.
##
## `provides_actions` is deliberately NOT a field here even though the
## taskblock's own sketch lists one: `ActionCatalog` already reads
## `Part.provides_actions` directly (taskblock-07's provider model) and a
## second, unread copy on this sub-resource would just be a second source
## of truth nothing consumes — SHOOT/BURST go on the weapon Part's own
## `provides_actions`, the existing mechanism, unchanged.

## Barrel mult — from the reference gun table (0.8, 1.0, 0.9, 1.1). Feeds
## the shot's final damage as a MULTIPLY ModSource (WeaponResolver), so a
## sniper's 1.1 hits harder than a chaingun's 0.8 firing the same ammo.
@export var damage_multiplier: float = 1.0
## 0..1 — the gun's own steadiness (0.8, 0.85, 0.9, 0.95). Pass E: the
## spread pattern's own base size scales off this, never the dartboard.
@export var mechanical_accuracy: float = 1.0
@export var effective_range: float = 0.0
## Drives recoil (Pass D, dartboard widening) and spread (Pass E, pattern
## tightening) — both "longer barrel = better," sharing one curve shape.
@export var barrel_length: float = 1.0
## From the reference table (12, n/a, 3, n/a) — n/a guns leave this at the
## default 1 and simply never provide BURST.
@export var burst_size: int = 1
## taskblock-13 Pass C: "AP cost: authored per action; a burst costs more
## than a single shot." 0 (unset) means "no BURST authored" — every gun
## that actually provides BURST authors a real, higher-than-`ap_cost`
## value; flagged placeholder numbers (no balance figure was specified),
## ask before tuning.
@export var burst_ap_cost: int = 0
## Chamber (Pass B): legal iff `ammo.case_family == accepts_family` and
## `ammo.case_length <= max_case_length`.
@export var accepts_family: StringName = &""
@export var max_case_length: float = 0.0
