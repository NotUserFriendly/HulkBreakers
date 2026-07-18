class_name AmmoDef
extends Resource

## taskblock-10 Pass D: damage lives on ammo, not the gun. Fields straight
## from the reference ammo table (9mm/5.56/7.62/12ga) — the gun itself only
## ever multiplies `damage` (`Part.damage_multiplier`, once the weapon side
## of this model lands; not built here).

@export var id: StringName = &""
@export var display_name: String = ""
@export var damage: float = 0.0
## The DT discount this round's payload carries — penetration only, never
## the deflect/stop-dead angle decision (docs/03). Can be negative (a
## shotgun's buckshot): armor gets HARDER to beat, not easier.
@export var bonus_pen: float = 0.0
## 1 = single (a slug collapses to pure dartboard); >1 = a spread pattern
## — the future two-scatter model's concern, not built here.
@export var projectile_num: int = 1
## Open vocabulary: &"" (none), &"BURN", &"BLEED". HOOK ONLY — nothing
## consumes this yet; a resolved hit only records it (a later block).
@export var stack_type: StringName = &""
## Decimal, deliberately — HOOK ONLY, same status as `stack_type`.
@export var stacks_inflicted: float = 0.0
## The future barrel-length curve's anchor (`Part.damage_multiplier` will
## read from a curve keyed on the delta to a gun's real barrel length,
## once that lands). 0.0 here is an unauthored placeholder, not "no
## curve" — no per-ammo values were specified for this field yet; ask
## before tuning.
@export var ideal_barrel_length: float = 0.0

## taskblock-13 Pass B: the compatibility class — "these are meant to
## share a chamber," the designer's own lever, not a real-world caliber
## database. Chambers into a `WeaponDef` iff `case_family` matches its
## `accepts_family` AND `case_length` fits under its `max_case_length`.
## Diameter is deliberately NOT a field: in the shipping fiction, caliber
## lives in `display_name`/`case_family` alone (e.g. two differently
## "sized" fictional rounds can share one family on purpose — a mini-
## grenade that drops into a regular gun just declares that gun's
## family). Adding a width/shoulder field was considered and rejected as
## gun-nerdery that doesn't survive the rename to fictional ammo.
@export var case_family: StringName = &""
## The one continuous fit dimension — same family, too long, won't
## chamber. Abstract length units, consistent within a family only (no
## real-world unit is implied).
@export var case_length: float = 0.0
