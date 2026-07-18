class_name DamageResolver
extends RefCounted

## docs/03: armor is not more hitpoints. resolve_impact() decides penetrate /
## stop-dead / deflect from real geometry — never a roll. resolve_shot()
## orchestrates one projectile's whole life: penetration cascades through
## whatever's behind the plate, a deflection spawns a ricochet that travels
## the world and can hit anything, and the sim always terminates (ricochet
## depth cap + a damage floor).

const DEFAULT_MAX_RICOCHET_DEPTH := 2
const DEFAULT_DAMAGE_FLOOR := 1.0

## docs/03 specifies "bonus damage" on a crit but gives no multiplier. This
## is a flagged, tunable placeholder, not a design decision — ask before
## treating it as final.
const DEFAULT_CRIT_BONUS_MULTIPLIER := 1.5

## docs/10 taskblock04 C1/C2: marks a dropped assembly for the view layer
## (BoardView: lay it on its side, the same trick HitVolumeView already uses for
## a downed unit — taskblock03 G) — distinct from ordinary terrain cover,
## which stays upright. A plain tag, not a new Part field: the vocabulary
## is already open (`Part.tags`).
const DROPPED_TAG := &"DROPPED"


## Pure geometry, decided once for a single region: no roll. `incoming_dir`
## is the projectile's direction of travel; `region.surface_normal` comes
## free from BodyProjector — the box face that was actually hit.
static func resolve_impact(
	incoming_dir: Vector2, damage: float, region: Region, table: MaterialTable
) -> ImpactResult:
	var material: MaterialEntry = table.get_entry(region.part.material)
	var dir: Vector2 = incoming_dir.normalized()
	var normal_2d := Vector2(region.surface_normal.x, region.surface_normal.z)

	var result := ImpactResult.new()
	result.region = region
	result.incoming_dir = dir
	result.effective_dt = material.dt

	if damage >= material.dt:
		result.outcome = Enums.Outcome.PENETRATE
		result.part_damage = damage
		return result

	var incidence_deg: float = rad_to_deg(acos(clampf((-dir).dot(normal_2d), -1.0, 1.0)))
	if incidence_deg <= material.deflect_threshold_deg:
		result.outcome = Enums.Outcome.STOP_DEAD
		result.part_damage = damage
		return result

	result.outcome = Enums.Outcome.DEFLECT
	var reflected: Vector2 = (dir - 2.0 * dir.dot(normal_2d) * normal_2d).normalized()
	result.reflected_dir = reflected
	var deflection_deg: float = rad_to_deg(acos(clampf(dir.dot(reflected), -1.0, 1.0)))
	var t: float = clampf(deflection_deg / table.max_bend_deg, 0.0, 1.0)
	result.retained_fraction = lerp(table.retain_at_zero_bend, table.retain_at_max_bend, t)
	return result


## Subtracts `amount` (rounded up, so any positive damage always registers)
## from `part.hp`. Returns true if this destroyed the part.
static func apply_damage_to_part(part: Part, amount: float) -> bool:
	part.hp = maxi(0, part.hp - int(ceil(amount)))
	return part.hp <= 0


## taskblock-09 C1: a joint has HP only, no failure modes — subtracts from
## the SOCKET's own runtime joint_hp, never a part's hp (a completely
## separate pool from `apply_damage_to_part`, docs/03's "two independent
## HP pools per limb"). Returns true if this severed it.
static func apply_damage_to_joint(socket: Socket, amount: float) -> bool:
	socket.joint_hp = maxi(0, socket.joint_hp - int(ceil(amount)))
	return socket.joint_hp <= 0


## taskblock-09 C1/C2: severing a joint drops whatever it held as ONE
## intact assembly, rooted at the child, sockets still populated (docs/01's
## "borrow it as-is" rule) — never split at an inner mangled part the way
## the deleted BREAK mode once did. This is now the ONLY path from body to
## ground: part failure (Pass A) never detaches, only a severed joint does.
## Returns the dropped root part, or null if the socket was already empty.
static func sever_joint(socket: Socket, owner: Unit, state: CombatState) -> Part:
	var dropped: Part = socket.occupant
	if dropped == null:
		return null
	socket.occupant = null
	_register_dropped(dropped, owner, state)
	return dropped


## taskblock-09 A3 (docs/03): renamed from "cook-off," same mechanic. A
## failed DETONATE part with detonate_damage > 0 explodes: every living
## unit within detonate_radius (Chebyshev) of its cell takes that damage
## to their shell's root part. Returns the units it hit. No longer gated
## by the VOLATILE tag — that's a descriptor now, open vocabulary; the
## trigger is failure_mode == DETONATE, enforced by this file's own single
## caller, `resolve_part_failure`.
static func detonate(part: Part, state: CombatState) -> Array[Unit]:
	var affected: Array[Unit] = []
	if part.detonate_damage <= 0.0:
		return affected
	var center: Vector2i = _locate_cell(part, state)
	if center.x < 0:
		return affected
	for unit: Unit in state.units:
		if unit.alive and Grid.distance_chebyshev(unit.cell, center) <= int(part.detonate_radius):
			apply_damage_to_part(unit.shell.root, part.detonate_damage)
			affected.append(unit)
	return affected


## taskblock-09 A4: a failed FRAGMENT part sprays `fragment_count` rays in
## even directions from its own cell, each one a full resolve_shot flight
## (so a fragment can itself penetrate/deflect/ricochet, terminating the
## same way every other projectile does — depth cap + damage floor still
## apply on its own recursive calls). taskblock-10's real ammo/spread
## machinery replaces the even-direction spread; until then this is the
## taskblock's own literal words: "K rays in even directions."
static func _fragment(part: Part, state: CombatState) -> Array[ImpactResult]:
	var hits: Array[ImpactResult] = []
	if part.fragment_count <= 0 or part.fragment_damage <= 0.0:
		return hits
	var center: Vector2i = _locate_cell(part, state)
	if center.x < 0:
		return hits
	var origin := Vector2(center.x, center.y)
	for i in range(part.fragment_count):
		var angle: float = TAU * float(i) / float(part.fragment_count)
		var direction := Vector2(cos(angle), sin(angle))
		hits.append_array(
			resolve_shot(
				origin,
				direction,
				Vector2.ZERO,
				part.fragment_damage,
				0.0,
				state,
				state.material_table,
				state.rng
			)
		)
	return hits


## taskblock-09 A0: dispatches to exactly what `part.failure_mode` says
## happens at 0 HP — never stacked (a part has ONE failure_mode). Mutates
## `part` (is_mangled/is_disabled/meltdown_countdown) and populates
## `impact` with whatever that mode's own consequences were, for logging
## (docs/09: "if it changed the world, it's in the log"). The one caller,
## `_resolve_destruction_consequences`, only ever reaches this once per
## actual destroying hit, so DETONATE/FRAGMENT firing exactly once is a
## property of the call site, not a guard here.
static func resolve_part_failure(part: Part, state: CombatState, impact: ImpactResult) -> void:
	match part.failure_mode:
		&"MANGLE":
			part.is_mangled = true
		&"DISABLE":
			part.is_disabled = true
		&"DETONATE":
			impact.detonated_units = detonate(part, state)
		&"FRAGMENT":
			impact.fragment_hits = _fragment(part, state)
		&"MELTDOWN":
			if part.meltdown_countdown >= 0:
				# Already counting down and destroyed again (taskblock-09
				# A4): detonate now rather than waiting out the rest of the
				# clock.
				part.meltdown_countdown = -1
				impact.detonated_units = detonate(part, state)
			elif part.meltdown_turns <= 0:
				# No countdown authored: behaves like an instant DETONATE.
				impact.detonated_units = detonate(part, state)
			else:
				part.meltdown_countdown = part.meltdown_turns
				impact.meltdown_armed = true


## taskblock-09 A4: ticks every part's own live MELTDOWN countdown down by
## one — called once per the owning unit's own turn start
## (CombatState._start_turn, the same seam LifeSupport.tick already uses).
## Walks `all_parts()`, not `living_parts()`: a counting-down part already
## has hp <= 0 (it failed to get here) and would otherwise be invisible to
## this tick. Returns one entry per part that actually detonated THIS
## tick, `{"part": Part, "units": Array[Unit]}`, so the caller can log it
## (this file stays a pure logic layer, no direct combat_log coupling).
static func tick_meltdowns(unit: Unit, state: CombatState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for part: Part in unit.shell.all_parts():
		if part.meltdown_countdown < 0:
			continue
		part.meltdown_countdown -= 1
		if part.meltdown_countdown <= 0:
			part.meltdown_countdown = -1
			events.append({"part": part, "units": detonate(part, state)})
	return events


static func _locate_cell(part: Part, state: CombatState) -> Vector2i:
	for unit: Unit in state.units:
		if part in unit.shell.all_parts():
			return unit.cell
	for cell: Vector2i in state.grid.blockers:
		if state.grid.blockers[cell] == part:
			return cell
	return Vector2i(-1, -1)


## Destroying the part hosting a unit's Matrix ejects it as a loose field
## item (docs/01: "destroy that part -> eject") and demotes the unit's
## surrogate one rung (docs/04: "a torso chewed to SPINAL still functions"
## — the body degrades, the matrix does not). The unit itself goes
## unpiloted (alive false) — matrices are never lost, but an ejected one
## leaves its shell behind. Returns the ejected Matrix, or null if `part`
## wasn't hosting one belonging to a real unit.
static func eject_matrix_if_needed(part: Part, state: CombatState) -> Matrix:
	if part.hp > 0 or not part.hosts_matrix() or part.hosted_matrix == null:
		return null
	var owner: Unit = _owning_unit(part, state)
	if owner == null:
		return null

	var ejected: Matrix = part.hosted_matrix
	part.hosted_matrix = null
	if not state.grid.field_items.has(owner.cell):
		state.grid.field_items[owner.cell] = []
	state.grid.field_items[owner.cell].append(ejected)

	owner.demote_surrogate(SurrogateLadder.default_ladder())
	state.kill_unit(owner)
	return ejected


static func _owning_unit(part: Part, state: CombatState) -> Unit:
	for unit: Unit in state.units:
		if part in unit.shell.all_parts():
			return unit
	return null


## docs/04 taskblock02 Pass D1: destroying the shell root that hosts an
## ATTACHED surrogate (not a bare matrix — `eject_matrix_if_needed` already
## covers that direct, bot-style case) drops the whole surrogate, matrix
## and all, as one intact field item. The root has no parent within itself
## to "drop from" the normal subtree way (the root destroyed IS the unit),
## so this is `eject_matrix_if_needed`'s shape one level down: the shell
## was what protected the surrogate, and losing it exposes what's left.
## Returns the ejected surrogate Part, or null if `part` isn't a destroyed
## root hosting one.
static func eject_surrogate_if_needed(part: Part, state: CombatState) -> Part:
	if part.hp > 0:
		return null
	var owner: Unit = _owning_unit(part, state)
	if owner == null or owner.shell.root != part:
		return null
	if part.hosts_matrix() and part.hosted_matrix != null:
		return null  # a bare matrix docked directly: eject_matrix_if_needed's job

	for socket: Socket in part.sockets:
		var occupant: Part = socket.occupant
		if occupant == null or not _hosts_matrix_somewhere(occupant):
			continue
		socket.occupant = null
		if not state.grid.field_items.has(owner.cell):
			state.grid.field_items[owner.cell] = []
		state.grid.field_items[owner.cell].append(occupant)
		owner.demote_surrogate(SurrogateLadder.default_ladder())
		state.kill_unit(owner)
		return occupant
	return null


static func _hosts_matrix_somewhere(part: Part) -> bool:
	for candidate: Part in PartGraph.walk(part):
		if candidate.hosts_matrix() and candidate.hosted_matrix != null:
			return true
	return false


## taskblock-09 C2: "BREAK is gone — severing is the only 'drops off.'"
## Destroying a PART (this file's own hp<=0 path) never detaches anything
## anymore — MANGLE/DISABLE stay attached, DETONATE/FRAGMENT/MELTDOWN are
## consumed in place (`resolve_part_failure`). The only way a part leaves
## the body now is a SEVERED JOINT (`sever_joint`, above — Pass D wires an
## actual shot at the socket into it, `resolve_ray` isn't built yet). This
## used to be `drop_subtree_if_destroyed`, keyed on the destroyed part's
## own hp; deleted rather than adapted, per the taskblock's own framing —
## the docs/01 "blow a shoulder off, the subtree drops intact" rule still
## holds, it's just read off the shoulder's own JOINT now, never the
## part's hp. This helper is the one piece of the old mechanism that
## survives unchanged: `sever_joint` reuses it verbatim for field-item/
## blocker registration.
static func _register_dropped(part: Part, owner: Unit, state: CombatState) -> void:
	if not state.grid.field_items.has(owner.cell):
		state.grid.field_items[owner.cell] = []
	state.grid.field_items[owner.cell].append(part)

	if not state.grid.blockers.has(owner.cell):
		if not DROPPED_TAG in part.tags:
			part.tags.append(DROPPED_TAG)
		state.grid.blockers[owner.cell] = part


## Every consequence of a part actually reaching 0 hp, gathered onto one
## ImpactResult: its own failure_mode (taskblock-09 A0), matrix ejection
## (plus the demotion it always carries — docs/04). `demoted_tier_before`
## is captured ahead of eject_matrix_if_needed() since that call is what
## changes it. No subtree drop here anymore (taskblock-09 C2): a
## destroyed PART never detaches on its own hp reaching 0 — only a
## severed JOINT does, a wholly separate hit (Pass D), never reached from
## this function.
static func _resolve_destruction_consequences(
	impact: ImpactResult, region: Region, state: CombatState
) -> void:
	resolve_part_failure(region.part, state, impact)
	var owner: Unit = _owning_unit(region.part, state)
	var tier_before: SurrogateTier = owner.surrogate_tier if owner != null else null
	impact.ejected_matrix = eject_matrix_if_needed(region.part, state)
	impact.ejected_surrogate = eject_surrogate_if_needed(region.part, state)
	if impact.ejected_matrix != null or impact.ejected_surrogate != null:
		impact.demoted_unit = owner
		impact.demoted_tier_before = tier_before


## Every part sharing a body with `part` (its whole unit, if any — otherwise
## just itself). A ricochet's new origin sits right where it just left, so
## excluding only the one part it bounced off still lets it immediately
## re-hit a sibling part of the same body at point-blank range; excluding
## the whole body for that first lookup is what "it bounced clear" means.
static func _body_of(part: Part, state: CombatState) -> Array[Part]:
	for unit: Unit in state.units:
		if part in unit.shell.all_parts():
			return unit.shell.all_parts()
	return [part]


static func _roll_crit(crit_chance: float, rng: RandomNumberGenerator) -> Dictionary:
	var is_crit: bool = rng.randf() < crit_chance
	var is_double_crit := false
	if is_crit:
		is_double_crit = rng.randf() < maxf(0.0, crit_chance - 1.0)
	return {"is_crit": is_crit, "is_double_crit": is_double_crit}


## docs/03: armored + crit -> bypass DT and resolve against whatever's
## behind; unarmored + crit -> bonus damage instead. A double crit always
## applies both — bypassing if armored, and bonus damage regardless.
static func _crit_effects(is_crit: bool, is_double_crit: bool, armored: bool) -> Dictionary:
	if is_double_crit:
		return {"bypass": armored, "bonus": true}
	if is_crit:
		return {"bypass": armored, "bonus": not armored}
	return {"bypass": false, "bonus": false}


## Resolves one projectile's entire path: builds the shot plane, walks it
## nearest-first from `point`, cascades through penetrations, and — on a
## deflect within budget — recurses into a fresh shot plane built from the
## ricochet's new origin and direction. Terminates via `max_ricochet_depth`
## and `damage_floor` (docs/03: "the sim must always terminate").
##
## `exclude_parts` skips those parts on this call's very first lookup only —
## set on a ricochet's recursive call to the whole body it just deflected
## off of (see _body_of), since a ricochet's new origin sits right where it
## bounced and would otherwise immediately re-resolve to a sibling part of
## that same body at point-blank range.
static func resolve_shot(
	origin: Vector2,
	direction: Vector2,
	point: Vector2,
	damage: float,
	crit_chance: float,
	state: CombatState,
	table: MaterialTable,
	rng: RandomNumberGenerator,
	ricochet_depth: int = 0,
	max_ricochet_depth: int = DEFAULT_MAX_RICOCHET_DEPTH,
	damage_floor: float = DEFAULT_DAMAGE_FLOOR,
	crit_bonus_multiplier: float = DEFAULT_CRIT_BONUS_MULTIPLIER,
	exclude_parts: Array[Part] = []
) -> Array[ImpactResult]:
	var results: Array[ImpactResult] = []
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var plane: Array[Region] = ShotPlane.build(origin, dir, state)

	# One crit roll per projectile flight: it stays in effect through
	# however many layers this same round penetrates or bypasses. A
	# ricochet is a new projectile (docs/03) and rolls its own on the
	# recursive call below.
	var crit: Dictionary = _roll_crit(crit_chance, rng)

	var start: int = 0
	var skip_parts: Array[Part] = exclude_parts
	# Every projectile in a burst shares the nominal `dir` used to build the
	# plane, but scatter puts each one at a different point — a different
	# muzzle-to-impact ray, not just a different landing spot. Derived once
	# per flight, from the first surface this round actually reaches, and
	# reused unchanged through whatever it goes on to penetrate (a round
	# doesn't bend just because it punched through).
	var shot_dir: Vector2 = dir
	var shot_dir_ready := false
	# taskblock-09 B: what's left of this round after however many layers
	# it has already spilled through — the plate always eats the FULL
	# current amount (armor is never spared), but what continues past it is
	# `current_damage - effective_dt`, floored at 0. Distinct from the
	# outer `damage` parameter, which stays this whole flight's nominal
	# value for crit bookkeeping and is never itself reduced.
	var current_damage: float = damage
	while start < plane.size():
		var found_index: int = _find_next(plane, start, point, skip_parts)
		skip_parts = []  # the exclusion applies only to this call's first hit
		if found_index == -1:
			break
		var region: Region = plane[found_index]
		start = found_index + 1

		if not shot_dir_ready:
			var muzzle_to_impact: Vector2 = dir * region.depth + perp * point.x
			shot_dir = muzzle_to_impact.normalized()
			shot_dir_ready = true

		var material: MaterialEntry = table.get_entry(region.part.material)
		var effects: Dictionary = _crit_effects(
			crit.is_crit, crit.is_double_crit, material.dt > 0.0
		)

		if effects.bypass:
			var bypass_result := ImpactResult.new()
			bypass_result.region = region
			bypass_result.incoming_dir = shot_dir
			bypass_result.is_crit = crit.is_crit
			bypass_result.is_double_crit = crit.is_double_crit
			bypass_result.bypassed_armor = true
			results.append(bypass_result)
			continue

		var applied_damage: float = current_damage * (
			crit_bonus_multiplier if effects.bonus else 1.0
		)
		var impact: ImpactResult = resolve_impact(shot_dir, applied_damage, region, table)
		impact.is_crit = crit.is_crit
		impact.is_double_crit = crit.is_double_crit
		results.append(impact)

		match impact.outcome:
			Enums.Outcome.PENETRATE:
				impact.destroyed_part = apply_damage_to_part(region.part, impact.part_damage)
				if impact.destroyed_part:
					_resolve_destruction_consequences(impact, region, state)
				# taskblock-09 B: the plate ate the full part_damage above
				# regardless — what carries on to the next layer is only the
				# spill, and a spill of exactly 0 means this round stops here,
				# same as if nothing were left of the plane to check.
				var spill: float = maxf(0.0, impact.part_damage - impact.effective_dt)
				if spill <= 0.0:
					return results
				current_damage = spill
				continue
			Enums.Outcome.STOP_DEAD:
				impact.destroyed_part = apply_damage_to_part(region.part, impact.part_damage)
				if impact.destroyed_part:
					_resolve_destruction_consequences(impact, region, state)
				return results
			Enums.Outcome.DEFLECT:
				var next_damage: float = current_damage * impact.retained_fraction
				if ricochet_depth < max_ricochet_depth and next_damage >= damage_floor:
					var world_hit: Vector2 = origin + dir * region.depth + perp * point.x
					results.append_array(
						resolve_shot(
							world_hit,
							impact.reflected_dir,
							Vector2(0.0, point.y),
							next_damage,
							crit_chance,
							state,
							table,
							rng,
							ricochet_depth + 1,
							max_ricochet_depth,
							damage_floor,
							crit_bonus_multiplier,
							_body_of(region.part, state)
						)
					)
				return results
	return results


static func _find_next(
	plane: Array[Region], start: int, point: Vector2, exclude_parts: Array[Part] = []
) -> int:
	for i in range(start, plane.size()):
		if exclude_parts.has(plane[i].part):
			continue
		if plane[i].rect.has_point(point):
			return i
	return -1
