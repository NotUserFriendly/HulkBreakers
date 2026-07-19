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
## taskblock-19 Pass C: full accuracy (dartboard at its authored size) out
## to here. Was a dead field before this pass — nothing read it; the
## legality cutoff lived on the separate, now-removed `Part.weapon_max_range`
## instead, authored to the SAME number on every real gun (an unintentional
## duplicate, not a design choice). 0.0 = no accuracy band authored (a
## legacy/undecorated weapon fires at full accuracy out to `max_range`,
## same as before this pass).
@export var effective_range: float = 0.0
## taskblock-19 Pass C: beyond `effective_range`, degraded accuracy
## (`RangeModel.accuracy_multiplier`); beyond THIS, no shot at all — the
## sole legality cutoff, replacing `Part.weapon_max_range`. 0.0 = uncapped
## (fires at any range), the same convention the old field used.
@export var max_range: float = 0.0
## taskblock-19 Pass C2: below here, a discrete failure rather than a
## clean "can't fire" — see `min_range_failure`. 0.0 = no minimum.
@export var min_range: float = 0.0
## Open vocabulary (CLAUDE.md: content stays data, not an enum). `&"none"`
## (default): below `min_range` the weapon simply can't fire, same as
## being beyond `max_range`. `&"dud"`: the weapon fires anyway — no
## special payload effect (nothing to arm below min range), a plain
## kinetic hit — the first authored case; the vocabulary stays open for
## whatever a later payload type needs.
@export var min_range_failure: StringName = &"none"
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
## taskblock-19 Pass E: a long/two-handed weapon can't fire while its own
## wielder is adjacent to a living enemy (`Suppression.blocks_weapon`) —
## closing to melee range disarms a rifle. False (a short/pistol weapon,
## unaffected) is the default so every existing weapon keeps firing at
## adjacency exactly as before this pass.
@export var two_handed: bool = false
