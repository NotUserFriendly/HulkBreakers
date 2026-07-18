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


## taskblock-13 Pass D: recoil's own per-step dartboard-widening amount —
## `RecoilResolver.step_amount`'s pure formula (base_recoil(ammo_damage) /
## barrel_factor(barrel_length)) supplies the BASE, resolved through the
## same StatResolver pipeline every other weapon-derived number here
## uses (docs/08: "nothing may compute a final number outside this
## pipeline"), so a future perk/ammo modifier ("Spin Up... slightly less
## recoil," docs/08's own worked example) can adjust it with full
## provenance exactly like damage/crit_chance/bonus_pen already do.
static func resolve_recoil_step(
	weapon: Part, ammo_damage: float, extra_sources: Array[ModSource] = []
) -> StatValue:
	return StatResolver.resolve(
		&"recoil_step",
		_context(RecoilResolver.step_amount(weapon, ammo_damage), weapon, extra_sources)
	)


## taskblock-09 F/taskblock-10 E: `Part.bonus_pen`'s own status is the
## same flagged weapon-level placeholder `damage` carries (Pass G) —
## `AmmoDef.bonus_pen` exists (taskblock-10 Pass D) and a weapon Part CAN
## now name a chambered round (taskblock-13 Pass B's own `ammo_id`), but
## nothing here reads it yet — swapping this field's source to whatever's
## chambered is a still-later, unbuilt wiring pass, not this one. Until
## then this stays the live source, read through here like every other
## weapon-derived number, never `weapon.bonus_pen` directly.
static func resolve_bonus_pen(weapon: Part, extra_sources: Array[ModSource] = []) -> StatValue:
	return StatResolver.resolve(&"bonus_pen", _context(weapon.bonus_pen, weapon, extra_sources))


## taskblock-13 Pass B: "chambering is legal iff `ammo.case_family ==
## gun.accepts_family` AND `ammo.case_length <= gun.max_case_length`."
## Diameter is never consulted — see `AmmoDef.case_family`'s own header
## for why. Returns "" (legal) or a human-readable, NAMED rejection
## reason — an illegal cartridge is refused loudly, never silently
## dropped/ignored.
static func chamber_error(weapon: Part, ammo: AmmoDef) -> String:
	if weapon.weapon_def == null:
		return "%s has no chamber at all (not a weapon)" % weapon.id
	if ammo.case_family != weapon.weapon_def.accepts_family:
		return (
			"%s (%s) does not fit %s's chamber (%s)"
			% [ammo.id, ammo.case_family, weapon.id, weapon.weapon_def.accepts_family]
		)
	if ammo.case_length > weapon.weapon_def.max_case_length:
		return (
			"%s's case (%.2f) is too long for %s's chamber (max %.2f)"
			% [ammo.id, ammo.case_length, weapon.id, weapon.weapon_def.max_case_length]
		)
	return ""


## Chambers `ammo` into `weapon` (sets `weapon.ammo_id`) iff
## `chamber_error` finds nothing wrong; a rejected round never mutates
## the weapon. Returns the same "" (loaded) / named-reason string
## `chamber_error` does, so a caller can show the rejection verbatim.
static func try_chamber(weapon: Part, ammo: AmmoDef) -> String:
	var error: String = chamber_error(weapon, ammo)
	if error == "":
		weapon.ammo_id = ammo.id
	return error


static func _context(base: float, weapon: Part, extra_sources: Array[ModSource]) -> ResolverContext:
	var context := ResolverContext.new()
	context.base = base
	context.parts = [weapon]
	context.extra_sources = extra_sources
	return context
