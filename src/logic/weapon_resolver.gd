class_name WeaponResolver
extends RefCounted

## docs/08: "the description and the damage come from the same code."
## Every weapon-derived number an attack actually uses, and every number a
## tooltip shows, resolves through here — the same pattern Dartboard
## already uses for scatter (Phase 4). Nothing may read weapon.damage or
## weapon.crit_chance directly to compute an outcome; this is the one
## place that's allowed to.


static func resolve_damage(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	return StatResolver.resolve(&"damage", _context(weapon.damage, weapon, extra_sources))


static func resolve_crit_chance(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	return StatResolver.resolve(&"crit_chance", _context(weapon.crit_chance, weapon, extra_sources))


## taskblock-09 F: `Part.bonus_pen`'s own status is the same flagged
## weapon-level placeholder `damage` carries (Pass G) — taskblock-10 moves
## it onto AmmoDef — but until then it's read through here like every
## other weapon-derived number, never `weapon.bonus_pen` directly.
static func resolve_bonus_pen(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	return StatResolver.resolve(&"bonus_pen", _context(weapon.bonus_pen, weapon, extra_sources))


static func _context(base: float, weapon: Part, extra_sources: Array[ModSource]) -> ResolverContext:
	var context := ResolverContext.new()
	context.base = base
	context.parts = [weapon]
	context.extra_sources = extra_sources
	return context
