class_name WeaponResolver
extends RefCounted

## docs/08: "the description and the damage come from the same code."
## Every weapon-derived number an attack actually uses, and every number a
## tooltip shows, resolves through here — the same pattern Dartboard
## already uses for scatter (Phase 4). Nothing may read weapon.damage or
## weapon.crit_chance directly to compute an outcome; this is the one
## place that's allowed to.


## taskblock-13 Pass A: `WeaponDef.damage_multiplier` ("barrel mult," the
## reference table's 0.8/1.0/0.9/1.1) rides in as one more MULTIPLY
## ModSource — same provenance pipeline as everything else here, never a
## raw `weapon.damage * weapon.weapon_def.damage_multiplier` off to the
## side. Always appended when a WeaponDef is present (even at 1.0 — a
## drill-down should show "barrel: x1.0" for a neutral gun the same way it
## shows a real multiplier), never for a part with no WeaponDef at all.
static func resolve_damage(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	var sources: Array[ModSource] = extra_sources.duplicate()
	if weapon.weapon_def != null:
		sources.append(
			ModSource.new(
				"Barrel",
				Enums.ModSourceKind.PART,
				Enums.ModOp.MULTIPLY,
				weapon.weapon_def.damage_multiplier
			)
		)
	return StatResolver.resolve(&"damage", _context(weapon.damage, weapon, sources))


static func resolve_crit_chance(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	return StatResolver.resolve(&"crit_chance", _context(weapon.crit_chance, weapon, extra_sources))


## taskblock-09 F/taskblock-10 E: `Part.bonus_pen`'s own status is the
## same flagged weapon-level placeholder `damage` carries (Pass G) —
## `AmmoDef.bonus_pen` exists now (taskblock-10 Pass D) but no weapon Part
## references an AmmoDef yet, so nothing has moved. Until a weapon
## actually names its ammo, this stays the one live source, read through
## here like every other weapon-derived number, never `weapon.bonus_pen`
## directly.
static func resolve_bonus_pen(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	return StatResolver.resolve(&"bonus_pen", _context(weapon.bonus_pen, weapon, extra_sources))


static func _context(base: float, weapon: Part, extra_sources: Array[ModSource]) -> ResolverContext:
	var context := ResolverContext.new()
	context.base = base
	context.parts = [weapon]
	context.extra_sources = extra_sources
	return context
