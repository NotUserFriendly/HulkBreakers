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

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): the three deflect
## RESPONSES `resolve_shot`'s own DEFLECT branch can take — same detection
## (`resolve_impact`, unchanged), different consequence per attack type.
## `&"ricochet"` (default) is every existing caller's behavior, byte-for-
## byte unchanged. `&"slide"` (stab): a point payload slides sideways to
## an adjacent point on the same surface instead of bouncing away at an
## angle. `&"none"` (hold/slash, per point): no deflect at all — chews
## through or does nothing, the round just stops right there. A flagged
## placeholder, not a tuned number: how far "adjacent" actually is.
const DEFLECT_MODE_RICOCHET := &"ricochet"
const DEFLECT_MODE_SLIDE := &"slide"
const DEFLECT_MODE_NONE := &"none"
const _SLIDE_NUDGE := 0.1

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
## taskblock-09 E: reads `material.dt_at(region.thickness)` — a lookup
## table, not the old flat `material.dt`. taskblock-09 F: `bonus_pen` is a
## flat DT discount applied first (can be negative — buckshot raises the
## bar instead of lowering it — `maxf(0.0, ...)` only floors a POSITIVE
## pen from pushing DT negative); taskblock-09 E1 then quarters whatever
## that combined number comes out to for an already-mangled part — same
## material, structurally worse, not a thinner one or an easier target to
## punch through. The incidence/deflect branch below never reads
## `effective_dt` itself — but taskblock-20 Pass E gives `bonus_pen` a
## second job there too, widening (or narrowing) the stop-dead-eligible
## incidence window instead.
## taskblock-23 Pass C: `incoming_vertical` is this shot's own real vertical
## slope (rise per unit of ground distance travelled) -- 0.0 for an
## ordinary flat shot (every first hop today), nonzero only after a
## previous DEFLECT gave it one. Together with `incoming_dir` (still the
## ground-plane heading) this reconstructs the real 3D incoming direction,
## tested against the region's own real 3D `surface_normal` (Pass A: no
## longer forced flat) -- the old `normal_2d := Vector2(surface_normal.x,
## surface_normal.z)` silently discarded a tilted part's real vertical
## tilt the moment Pass A started retaining it, even for an ordinary flat
## shot against a tilted face.
static func resolve_impact(
	incoming_dir: Vector2,
	damage: float,
	region: Region,
	table: MaterialTable,
	bonus_pen: float = 0.0,
	incoming_vertical: float = 0.0
) -> ImpactResult:
	var material: MaterialEntry = table.get_entry(region.part.material)
	var dir: Vector2 = incoming_dir.normalized()
	var dir3d: Vector3 = Vector3(dir.x, incoming_vertical, dir.y).normalized()
	var normal3d: Vector3 = region.surface_normal

	var result := ImpactResult.new()
	result.region = region
	result.incoming_dir = dir
	result.incoming_vertical = incoming_vertical
	var effective_dt: float = maxf(0.0, material.dt_at(region.thickness) - bonus_pen)
	if region.part.is_mangled:
		effective_dt *= 0.25
	result.effective_dt = effective_dt

	if damage >= effective_dt:
		result.outcome = Enums.Outcome.PENETRATE
		result.part_damage = damage
		return result

	# taskblock-20 Pass C3: `abs(...)`, not `(-dir).dot(...)` — incidence
	# against a flat surface is direction-agnostic (a plate hit square-on
	# reads 0 whichever side it's struck from). Every region used to face
	# the shooter by construction (BodyProjector dropped away-facing faces
	# outright), so `-dir` and the surface normal always pointed the same
	# way and this was equivalent; a `hollow` part's own EXIT face — hit
	# from the inside, its normal pointing the same way as `dir` — is the
	# first region that actually needs the general form.
	var incidence_deg: float = rad_to_deg(acos(clampf(absf(dir3d.dot(normal3d)), -1.0, 1.0)))
	# taskblock-20 Pass E: a high-pen round bites in and stop-deads at angles
	# that would otherwise skip off — the deflect/stop-dead boundary widens
	# with `bonus_pen` (can narrow it too: a negative bonus_pen, e.g.
	# buckshot, makes armor HARDER to bite into, same as it already does for
	# penetration above). Clamped to [0, 90]: incidence itself never leaves
	# that range (docs/02), and "no universal safe angle" means there's no
	# reason to cap the widening short of it either.
	var effective_deflect_threshold_deg: float = clampf(
		material.deflect_threshold_deg + bonus_pen * table.deflect_threshold_bonus_pen_scale,
		0.0,
		90.0
	)
	if incidence_deg <= effective_deflect_threshold_deg:
		result.outcome = Enums.Outcome.STOP_DEAD
		result.part_damage = damage
		return result

	result.outcome = Enums.Outcome.DEFLECT
	var reflected3d: Vector3 = (dir3d - 2.0 * dir3d.dot(normal3d) * normal3d).normalized()
	var reflected_ground := Vector2(reflected3d.x, reflected3d.z)
	if reflected_ground.is_zero_approx():
		# A reflection with no horizontal component left at all (bounced
		# dead straight up/down): keep the flight's own ground heading so a
		# recursive ShotPlane.build still has a real direction to build
		# from, flat (vertical_slope 0.0) the same way a first hop always
		# is -- max_ricochet_depth still bounds this either way.
		result.reflected_dir = dir
		result.reflected_vertical = 0.0
	else:
		result.reflected_dir = reflected_ground.normalized()
		result.reflected_vertical = reflected3d.y / reflected_ground.length()
	var deflection_deg: float = rad_to_deg(acos(clampf(dir3d.dot(reflected3d), -1.0, 1.0)))
	var t: float = clampf(deflection_deg / table.max_bend_deg, 0.0, 1.0)
	result.retained_fraction = lerp(table.retain_at_zero_bend, table.retain_at_max_bend, t)
	return result


## taskblock-25 Pass C: stab's own DEFLECT response — "slides sideways
## along the surface to an adjacent point, not an angular bounce." Retries
## ONCE (never chains into a second slide, even if the nudged point itself
## also deflects) against a point nudged laterally by `_SLIDE_NUDGE`,
## re-searched from the front of the SAME already-built plane (a lateral
## nudge can reveal something nearer OR farther, never assumed to be
## "behind" in the original depth order). Appends whatever that adjacent
## point resolves to (PENETRATE/STOP_DEAD apply damage and destruction
## consequences the same way the main loop does; a second DEFLECT or
## nothing found at all just ends the strike here) directly onto `results`
## — this is the terminal step for a slide, the caller always returns
## right after.
static func _resolve_slide(
	plane: Array[Region],
	point: Vector2,
	region_height: float,
	vertical_slope: float,
	shot_dir: Vector2,
	current_damage: float,
	table: MaterialTable,
	bonus_pen: float,
	crit: Dictionary,
	origin: Vector2,
	dir: Vector2,
	perp: Vector2,
	origin_height: float,
	state: CombatState,
	results: Array[ImpactResult]
) -> void:
	var nudged_point := Vector2(point.x + _SLIDE_NUDGE, region_height)
	var slid_index: int = _find_next(plane, 0, nudged_point, [], vertical_slope)
	if slid_index == -1:
		return
	var slid_region: Region = plane[slid_index]
	var slid_impact: ImpactResult = resolve_impact(
		shot_dir, current_damage, slid_region, table, bonus_pen, vertical_slope
	)
	slid_impact.is_crit = crit.is_crit
	slid_impact.is_double_crit = crit.is_double_crit
	slid_impact.origin = origin
	slid_impact.hit_point = origin + dir * slid_region.depth + perp * nudged_point.x
	slid_impact.origin_height = origin_height
	slid_impact.hit_height = region_height + vertical_slope * slid_region.depth
	results.append(slid_impact)
	match slid_impact.outcome:
		Enums.Outcome.PENETRATE, Enums.Outcome.STOP_DEAD:
			slid_impact.destroyed_part = apply_damage_to_part(
				slid_region.part, slid_impact.part_damage
			)
			if slid_impact.destroyed_part:
				_resolve_destruction_consequences(slid_impact, slid_region, state)
		_:
			pass  # a second DEFLECT (or anything else) — one slide only, ends here.


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
## `cell` — not a `Unit` — since a socket's own connection can belong to a
## bare field-object tree just as easily as a piloted unit (docs/10: a
## dropped assembly is still a real socket graph, joints and all).
## Returns the dropped root part, or null if the socket was already empty.
static func sever_joint(socket: Socket, cell: Vector2i, state: CombatState) -> Part:
	var dropped: Part = socket.occupant
	if dropped == null:
		return null
	socket.occupant = null
	_register_dropped(dropped, cell, state)
	return dropped


## taskblock-09 D: `region.body`, not `_locate_cell` — the joint's own
## body is already known exactly (ShotPlane.build sets it), and unlike
## `_locate_cell` (which only matches a blocker dict's own root value
## directly), this must resolve correctly even when the joint belongs to a
## non-root part several levels deep in a field-object's own tree.
static func _cell_of_body(body: Variant, state: CombatState) -> Vector2i:
	if body is Unit:
		return (body as Unit).cell
	for cell: Vector2i in state.grid.blockers:
		if state.grid.blockers[cell] == body:
			return cell
	return Vector2i(-1, -1)


## taskblock-09 D: a JOINT region never goes through the material/DT
## decision a part region does — a connection has no material. The shot's
## whole current damage lands on the socket's own joint_hp
## (`apply_damage_to_joint`); if that severs it, the intact subtree drops
## via `sever_joint`, reusing Pass C's own mechanism verbatim. A joint hit
## always consumes the round — there's no concept of "penetrating" a
## connection, so the cascade stops here regardless of outcome (the
## default `Enums.Outcome.STOP_DEAD` ImpactResult already carries — the
## shot stopped here, whether or not the joint gave way).
static func _resolve_joint_hit(
	region: Region, damage: float, shot_dir: Vector2, crit: Dictionary, state: CombatState
) -> ImpactResult:
	var impact := ImpactResult.new()
	impact.region = region
	impact.incoming_dir = shot_dir
	impact.is_crit = crit.is_crit
	impact.is_double_crit = crit.is_double_crit
	impact.part_damage = damage
	if apply_damage_to_joint(region.socket, damage):
		var cell: Vector2i = _cell_of_body(region.body, state)
		if cell.x >= 0:
			var dropped: Part = sever_joint(region.socket, cell, state)
			if dropped != null:
				impact.dropped_subtree = PartGraph.walk(dropped)
	return impact


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


## taskblock-22 Pass C: "a wounded unit that shuts down may trigger its
## reactor's MELTDOWN if the reactor is in that state" — a shut-down unit
## never gets another turn (`CombatState._can_take_a_turn`), so a primed
## meltdown could otherwise never actually finish its own countdown
## (`tick_meltdowns` only ever runs at THIS unit's own turn start). Same
## shape/return as `tick_meltdowns` (one entry per part that detonated),
## reused by `ShutdownAction` for its own logging — every part with a
## LIVE countdown detonates immediately rather than waiting one it will
## never get.
static func trigger_primed_meltdowns(unit: Unit, state: CombatState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for part: Part in unit.shell.all_parts():
		if part.meltdown_countdown < 0:
			continue
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
## the body now is a SEVERED JOINT (`sever_joint`, above; Pass D wires an
## actual shot at the socket into it, in `resolve_shot`'s own JOINT
## branch). This used to be `drop_subtree_if_destroyed`, keyed on the
## destroyed part's own hp; deleted rather than adapted, per the
## taskblock's own framing — the docs/01 "blow a shoulder off, the subtree
## drops intact" rule still holds, it's just read off the shoulder's own
## JOINT now, never the part's hp. This helper is the one piece of the old
## mechanism that survives unchanged: `sever_joint` reuses it verbatim for
## field-item/blocker registration, keyed by cell rather than a Unit's own
## — the connection being severed may belong to a bare field-object tree,
## never piloted at all.
static func _register_dropped(part: Part, cell: Vector2i, state: CombatState) -> void:
	if not state.grid.field_items.has(cell):
		state.grid.field_items[cell] = []
	state.grid.field_items[cell].append(part)

	if not state.grid.blockers.has(cell):
		if not DROPPED_TAG in part.tags:
			part.tags.append(DROPPED_TAG)
		state.grid.blockers[cell] = part


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
##
## `bonus_pen` (taskblock-09 F) is this round's own DT discount — the same
## value for every layer it penetrates and for whatever ricochet it spawns
## (the same physical round, just traveling a new direction); a fragment's
## own recursive flight (`_fragment`, above) doesn't carry one of its own
## yet, so it stays at the 0.0 default there.
##
## taskblock-23 Pass C: `vertical_slope` is this flight's own real rise per
## unit of ground distance — 0.0 for an ordinary flat shot (every first
## hop today: `direction`/`point` stay ground-plane-heading and
## lateral/height-in-plane respectively, unchanged), nonzero only on a
## ricochet's own recursive call, carrying the PREVIOUS hop's real 3D
## reflection instead of silently flattening it back to one height.
## `origin_height` is this flight's own real starting height — the true
## muzzle's for a first hop (a caller with a real one, e.g. a shouldered
## weapon, passes it; 0.0 otherwise, same harmless default every other
## unset height on this codebase's ImpactResult already has), the previous
## hop's own real landing height for a ricochet (computed below, never a
## caller concern).
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
	exclude_parts: Array[Part] = [],
	bonus_pen: float = 0.0,
	vertical_slope: float = 0.0,
	origin_height: float = 0.0,
	deflect_mode: StringName = DEFLECT_MODE_RICOCHET
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
	# taskblock-20 Pass C4: the `hollow` part currently "open" — penetrated at
	# its near face, its far face not yet reached/cleared. Null whenever the
	# round is in open air or inside only solid parts. Set on a hollow part's
	# FIRST penetrate (entering), cleared on that SAME part's second
	# (exiting) — an intervening solid part's own hit never touches this.
	var inside_hollow_part: Part = null
	while start < plane.size():
		var found_index: int = _find_next(plane, start, point, skip_parts, vertical_slope)
		skip_parts = []  # the exclusion applies only to this call's first hit
		if found_index == -1:
			break
		var region: Region = plane[found_index]
		start = found_index + 1

		if not shot_dir_ready:
			var muzzle_to_impact: Vector2 = dir * region.depth + perp * point.x
			shot_dir = muzzle_to_impact.normalized()
			shot_dir_ready = true

		# taskblock-22 Pass D: this hop's own real muzzle (this call's own
		# `origin` — the true shooter for the first hop, the previous hop's
		# own deflection point for a ricochet) and where it actually landed —
		# same flat coords every ImpactResult below stamps itself with.
		var hop_hit_point: Vector2 = origin + dir * region.depth + perp * point.x
		# taskblock-23 Pass C: the real world height of THIS hit — constant
		# (== point.y) for a flat flight (vertical_slope 0.0, the same value
		# every hop already used before this pass), rising/falling with
		# depth for a tilted post-ricochet flight.
		var region_height: float = point.y + vertical_slope * region.depth

		if region.socket != null:
			var joint_hit: ImpactResult = _resolve_joint_hit(
				region, current_damage, shot_dir, crit, state
			)
			joint_hit.origin = origin
			joint_hit.hit_point = hop_hit_point
			joint_hit.origin_height = origin_height
			joint_hit.hit_height = region_height
			results.append(joint_hit)
			return results

		var material: MaterialEntry = table.get_entry(region.part.material)
		var effects: Dictionary = _crit_effects(
			crit.is_crit,
			crit.is_double_crit,
			maxf(0.0, material.dt_at(region.thickness) - bonus_pen) > 0.0
		)

		if effects.bypass:
			var bypass_result := ImpactResult.new()
			bypass_result.region = region
			bypass_result.incoming_dir = shot_dir
			bypass_result.is_crit = crit.is_crit
			bypass_result.is_double_crit = crit.is_double_crit
			bypass_result.bypassed_armor = true
			bypass_result.origin = origin
			bypass_result.hit_point = hop_hit_point
			bypass_result.origin_height = origin_height
			bypass_result.hit_height = region_height
			results.append(bypass_result)
			if region.part.hollow:
				if inside_hollow_part == region.part:
					inside_hollow_part = null
				else:
					inside_hollow_part = region.part
			continue

		var applied_damage: float = (
			current_damage * (crit_bonus_multiplier if effects.bonus else 1.0)
		)
		var impact: ImpactResult = resolve_impact(
			shot_dir, applied_damage, region, table, bonus_pen, vertical_slope
		)
		impact.is_crit = crit.is_crit
		impact.is_double_crit = crit.is_double_crit
		impact.origin = origin
		impact.hit_point = hop_hit_point
		impact.origin_height = origin_height
		impact.hit_height = region_height
		results.append(impact)

		match impact.outcome:
			Enums.Outcome.PENETRATE:
				impact.destroyed_part = apply_damage_to_part(region.part, impact.part_damage)
				if impact.destroyed_part:
					_resolve_destruction_consequences(impact, region, state)
				if region.part.hollow:
					if inside_hollow_part == region.part:
						inside_hollow_part = null  # cleared the far face: exited
					else:
						inside_hollow_part = region.part  # cleared the near face: entered
				# taskblock-09 B: the plate ate the full part_damage above
				# regardless — what carries on to the next layer is only the
				# spill, and a spill of exactly 0 means this round stops here,
				# same as if nothing were left of the plane to check.
				var spill: float = maxf(0.0, impact.part_damage - impact.effective_dt)
				if spill <= 0.0:
					_inflict_lodged_wound_if_inside(inside_hollow_part, impact)
					return results
				current_damage = spill
				continue
			Enums.Outcome.STOP_DEAD:
				impact.destroyed_part = apply_damage_to_part(region.part, impact.part_damage)
				if impact.destroyed_part:
					_resolve_destruction_consequences(impact, region, state)
				_inflict_lodged_wound_if_inside(inside_hollow_part, impact)
				return results
			Enums.Outcome.DEFLECT:
				if deflect_mode == DEFLECT_MODE_NONE:
					# Hold/slash, per point: no deflect at all — chews through
					# or does nothing, never bounces or slides.
					return results
				if deflect_mode == DEFLECT_MODE_SLIDE:
					_resolve_slide(
						plane,
						point,
						region_height,
						vertical_slope,
						shot_dir,
						current_damage,
						table,
						bonus_pen,
						crit,
						origin,
						dir,
						perp,
						origin_height,
						state,
						results
					)
					return results
				var next_damage: float = current_damage * impact.retained_fraction
				if ricochet_depth < max_ricochet_depth and next_damage >= damage_floor:
					var world_hit: Vector2 = origin + dir * region.depth + perp * point.x
					results.append_array(
						resolve_shot(
							world_hit,
							impact.reflected_dir,
							Vector2(0.0, region_height),
							next_damage,
							crit_chance,
							state,
							table,
							rng,
							ricochet_depth + 1,
							max_ricochet_depth,
							damage_floor,
							crit_bonus_multiplier,
							_body_of(region.part, state),
							bonus_pen,
							impact.reflected_vertical,
							region_height
						)
					)
				return results
	# taskblock-20 Pass C4: ran out of plane (no more regions at this exact
	# point) while still inside a hollow part's own shell — as good as
	# flooring there; the round has nowhere left to go either way.
	if inside_hollow_part != null and not results.is_empty():
		_inflict_lodged_wound_if_inside(inside_hollow_part, results[-1])
	return results


## taskblock-20 Pass C4: "a round strong enough to punch in but not out
## stops inside the cavity" — `&"lodged_bullet"` on whatever part the round
## was actually resolving against when it ran out of steam, a no-op when
## the round was never inside a hollow shell to begin with (the ordinary
## "just stopped" case) or already carries this exact wound.
static func _inflict_lodged_wound_if_inside(inside_hollow_part: Part, impact: ImpactResult) -> void:
	if inside_hollow_part == null:
		return
	var part: Part = impact.region.part
	if &"lodged_bullet" in part.wounds:
		return
	WoundEffects.inflict(part, &"lodged_bullet")
	impact.wound_inflicted = &"lodged_bullet"


## taskblock-23 Pass C: `vertical_slope` lets a tilted post-ricochet flight
## test each region at ITS OWN real height (`point.y` rising/falling with
## that region's own depth), instead of the one fixed height a flat shot
## (vertical_slope 0.0, every first hop) always correctly used before this
## pass — the exact height-per-depth relationship `ShotPlane.resolve_ray`
## gives a tilted ray, applied here to the plane-walking primitive instead
## of a single ray cast.
static func _find_next(
	plane: Array[Region],
	start: int,
	point: Vector2,
	exclude_parts: Array[Part] = [],
	vertical_slope: float = 0.0
) -> int:
	for i in range(start, plane.size()):
		if exclude_parts.has(plane[i].part):
			continue
		var height_here: float = point.y + vertical_slope * plane[i].depth
		if plane[i].rect.has_point(Vector2(point.x, height_here)):
			return i
	return -1
