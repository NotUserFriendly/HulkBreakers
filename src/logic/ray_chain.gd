class_name RayChain
extends RefCounted

## taskblock-52 Pass B: **one projectile's whole life, marched through the actual
## world instead of resolved against a 2D silhouette of it.**
##
## ```
## A = muzzle point          (not the unit's cell centre)
## B = the aimed point       (from the dartboard, or a raycast if nothing was clicked)
## march A -> B, first hit wins
## solve the angle of incidence against the struck surface
## -> deflect / penetrate / stop_dead   (docs/03, unchanged)
## if it continues:  C = march from B along the solved direction
##                   then C becomes B, B becomes A, repeat
## ```
##
## ## What is genuinely different, and what is deliberately identical
##
## **Different:** the angle of incidence is native. `DamageResolver.resolve_impact`
## has always been written against a real surface angle and, under the plane, got
## an approximation — a `Region` is an axis-aligned box of projected corners, and
## nothing about the struck face's real orientation survives projection.
## `RayHit.normal` is the face the slab test actually clipped against.
##
## **Different:** the round diverges from the gun. The plane tested every
## candidate at a *constant* lateral offset, so a scattered round was modelled as
## a ray parallel to the shooter-to-target line, translated sideways by the whole
## dartboard displacement — muzzle included. taskblock-52 Pass A measured the
## consequence: at a wide enough offset the modelled flight began outside the
## building and met nothing, which is the whole of `BR34.05`'s wide-offset half.
## Marching A to B cannot express that, because A is the muzzle.
##
## **Identical:** the outcome vocabulary, the DT and crit arithmetic, the
## destruction consequences, and every log event. This changes *how* an outcome
## is decided, never what the outcomes are — `resolve_impact`,
## `apply_damage_to_part`, `resolve_destruction_consequences` and
## `resolve_joint_hit`'s effects are all reached through `DamageResolver`
## itself, not reimplemented here.
##
## ## A penetration continues the same ray; a deflection starts a new one
##
## Both are the same call with a different direction, so there is no branch only
## one of them exercises. That is the property the plane could not have: building
## a plane for a post-deflection heading was the expensive path, so the
## continuation was faked, which is what a decorative fixed-range bounce tracer
## and a `STOP_DEAD` drawn past its own hit point both were.

## The chain's own bound. An unbounded recursion between two parallel walls is
## the obvious pathology, and a cap that fires silently is a cap nobody can find
## afterwards — every hit of it emits `&"ray_chain_capped"`.
##
## Counts **segments**, not deflections: a penetration cascade through many
## layers is as capable of running long as a bounce is. Sized to comfortably
## exceed `DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH`'s own reach through
## ordinary geometry; a flagged, tunable bound, not a balance number.
const DEFAULT_MAX_SEGMENTS := 24

## How far past a hit the next segment starts, so a continuing round does not
## immediately re-strike the face it just cleared. Well below any real geometry;
## the alternative is an identity exclusion, which is wrong here because a round
## penetrating a hollow shell genuinely must strike that same part again on the
## way out (`Part.hollow`, taskblock-20 Pass C4).
const SURFACE_NUDGE := 0.0001


## Marches one projectile from `from` toward `toward` and returns every impact it
## produced, in order. `toward` is a world **point** — B — not a direction: the
## dartboard picks a point, and the muzzle-to-point line is the shot.
##
## `exclude_parts` applies to the first segment only, exactly as
## `DamageResolver.resolve_shot`'s does and for the same reason.
static func resolve(
	state: CombatState,
	from: Vector3,
	toward: Vector3,
	damage: float,
	crit_chance: float,
	table: MaterialTable,
	rng: RandomNumberGenerator,
	exclude_parts: Array[Part] = [],
	bonus_pen: float = 0.0,
	deflect_mode: StringName = DamageResolver.DEFLECT_MODE_RICOCHET,
	max_segments: int = DEFAULT_MAX_SEGMENTS,
	damage_floor: float = DamageResolver.DEFAULT_DAMAGE_FLOOR,
	crit_bonus_multiplier: float = DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER
) -> Array[ImpactResult]:
	var results: Array[ImpactResult] = []
	var direction: Vector3 = (toward - from).normalized()
	if direction.is_zero_approx():
		return results

	# One crit roll per projectile flight, held through however many layers this
	# same round penetrates — the same rule `resolve_shot` applies, read from the
	# same helper rather than rolled a second way here.
	var crit: Dictionary = DamageResolver.roll_crit(crit_chance, rng)

	var origin: Vector3 = from
	var current_damage: float = damage
	var skip_parts: Array[Part] = exclude_parts
	var segments := 0
	# taskblock-20 Pass C4's hollow bookkeeping, carried across segments: a round
	# that punched into a shell and cannot punch out lodges there.
	var inside_hollow_part: Part = null

	while segments < max_segments:
		segments += 1
		var hit: RayHit = RayCaster.cast(
			state, origin, direction, skip_parts, INF, state.combat_log
		)
		skip_parts = []
		if hit == null:
			break

		var region: Region = hit.to_region()
		var impact: ImpactResult = _resolve_one(
			state,
			hit,
			region,
			origin,
			hit.point,
			direction,
			current_damage,
			crit,
			table,
			bonus_pen,
			crit_bonus_multiplier
		)
		results.append(impact)

		if hit.socket != null:
			# A joint hit always consumes the round — there is no penetrating a
			# connection (taskblock-09 D), so the chain ends here whatever the
			# joint did.
			return results

		match impact.outcome:
			Enums.Outcome.PENETRATE:
				var spill: float = maxf(0.0, impact.part_damage - impact.effective_dt)
				if region.part.hollow:
					inside_hollow_part = region.part
					if spill <= 0.0:
						# Punched in and cannot punch out — it stops in the cavity.
						DamageResolver.inflict_lodged_wound_if_inside(inside_hollow_part, impact)
						return results
					# The far face is its own strike, at its own depth — the second
					# `Region` the plane emits for a hollow part (taskblock-20 C3).
					var exit_impact: ImpactResult = _resolve_one(
						state,
						hit,
						hit.to_exit_region(),
						origin,
						hit.exit_point,
						direction,
						spill,
						crit,
						table,
						bonus_pen,
						crit_bonus_multiplier
					)
					results.append(exit_impact)
					inside_hollow_part = null
					spill = maxf(0.0, exit_impact.part_damage - exit_impact.effective_dt)
					if exit_impact.outcome != Enums.Outcome.PENETRATE or spill <= 0.0:
						return results
				elif spill <= 0.0:
					DamageResolver.inflict_lodged_wound_if_inside(inside_hollow_part, impact)
					return results
				current_damage = spill
				# The same ray, continuing: the origin advances past the box's own
				# **exit** face, direction untouched. A round does not bend because
				# it punched through something — and it does not strike the same
				# plate twice, which resuming past the *entry* face made it do.
				origin = hit.exit_point + direction * SURFACE_NUDGE
			Enums.Outcome.STOP_DEAD:
				DamageResolver.inflict_lodged_wound_if_inside(inside_hollow_part, impact)
				return results
			Enums.Outcome.DEFLECT:
				if deflect_mode != DamageResolver.DEFLECT_MODE_RICOCHET:
					# Slide and none are melee responses (taskblock-25 Pass C) and
					# are not re-implemented on this path; a chain resolving a
					# stab ends at the deflection rather than inventing a second
					# answer to a question the plane already answers.
					return results
				var next_damage: float = current_damage * impact.retained_fraction
				if next_damage < damage_floor:
					return results
				current_damage = next_damage
				direction = _reflect(direction, hit.normal)
				origin = hit.point + direction * SURFACE_NUDGE
				# It bounced clear of the whole body, not merely off one part —
				# otherwise the new origin, sitting right where it left,
				# immediately re-strikes a sibling at point-blank range.
				skip_parts = DamageResolver.body_of(region.part, state)
			_:
				return results

	if segments >= max_segments:
		_log_cap(state, origin, direction, segments)
	if inside_hollow_part != null and not results.is_empty():
		DamageResolver.inflict_lodged_wound_if_inside(inside_hollow_part, results[-1])
	return results


## One impact, built through `DamageResolver` rather than beside it. The bypass
## branch (an armoured crit resolving against whatever is behind) is the same
## decision `resolve_shot` makes, read from the same helper.
## `at` is where this particular strike landed — `hit.point` for an ordinary one,
## `hit.exit_point` for a `hollow` part's far face. Passed rather than read off
## `hit`, because one `RayHit` produces two strikes at two different places and
## stamping both with the entry point put a hollow part's exit impact at its own
## near face (found by a test that asserted the two x coordinates differed).
static func _resolve_one(
	state: CombatState,
	hit: RayHit,
	region: Region,
	origin: Vector3,
	at: Vector3,
	direction: Vector3,
	current_damage: float,
	crit: Dictionary,
	table: MaterialTable,
	bonus_pen: float,
	crit_bonus_multiplier: float
) -> ImpactResult:
	var ground := Vector2(direction.x, direction.z)
	var vertical: float = 0.0 if ground.is_zero_approx() else direction.y / ground.length()
	var shot_dir: Vector2 = (
		ground.normalized() if not ground.is_zero_approx() else Vector2(1.0, 0.0)
	)

	if hit.socket != null:
		var joint_hit: ImpactResult = DamageResolver.resolve_joint_hit(
			region, current_damage, shot_dir, crit, state
		)
		_stamp(joint_hit, origin, at)
		return joint_hit

	var material: MaterialEntry = table.get_entry(region.part.material)
	var effects: Dictionary = DamageResolver.crit_effects(
		crit.is_crit,
		crit.is_double_crit,
		maxf(0.0, material.dt_at(region.thickness) - bonus_pen) > 0.0
	)
	if effects.bypass:
		var bypass := ImpactResult.new()
		bypass.region = region
		bypass.incoming_dir = shot_dir
		bypass.incoming_vertical = vertical
		bypass.is_crit = crit.is_crit
		bypass.is_double_crit = crit.is_double_crit
		bypass.bypassed_armor = true
		bypass.outcome = Enums.Outcome.PENETRATE
		bypass.part_damage = 0.0
		_stamp(bypass, origin, at)
		return bypass

	var applied: float = current_damage * (crit_bonus_multiplier if effects.bonus else 1.0)
	var impact: ImpactResult = DamageResolver.resolve_impact(
		shot_dir, applied, region, table, bonus_pen, vertical
	)
	impact.is_crit = crit.is_crit
	impact.is_double_crit = crit.is_double_crit
	_stamp(impact, origin, at)

	if impact.outcome == Enums.Outcome.PENETRATE or impact.outcome == Enums.Outcome.STOP_DEAD:
		impact.destroyed_part = DamageResolver.apply_damage_to_part(region.part, impact.part_damage)
		if impact.destroyed_part:
			DamageResolver.resolve_destruction_consequences(impact, region, state)
	return impact


## The flat coordinates every `ImpactResult` already carries, filled from real 3D
## points rather than reconstructed from a depth and a lateral offset. `origin_x`
## / `hit_x` stay cell-space to match every existing consumer of these fields
## (`ShotResolution.log_impact_result`, the tracer the view draws from it).
static func _stamp(impact: ImpactResult, origin: Vector3, at: Vector3) -> void:
	impact.origin = Vector2(origin.x, origin.z) / UnitGeometry.CELL_SIZE
	impact.origin_height = origin.y
	impact.hit_point = Vector2(at.x, at.z) / UnitGeometry.CELL_SIZE
	impact.hit_height = at.y


## Mirror `direction` in the struck face. Kept here rather than read off
## `ImpactResult.reflected_dir` because that field is a ground heading plus a
## separate vertical slope — the plane's own decomposition, needed because a
## plane has no third axis. A chain has the real 3D vectors and should not
## round-trip them through a representation that exists to work around their
## absence.
static func _reflect(direction: Vector3, normal: Vector3) -> Vector3:
	if normal.is_zero_approx():
		return direction
	return (direction - 2.0 * direction.dot(normal) * normal).normalized()


static func _log_cap(
	state: CombatState, origin: Vector3, direction: Vector3, segments: int
) -> void:
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					-1,
					&"ray_chain_capped",
					{
						"segments": segments,
						"x": origin.x,
						"y": origin.y,
						"z": origin.z,
						"dir_x": direction.x,
						"dir_y": direction.y,
						"dir_z": direction.z,
					},
					(
						"ray chain hit its %d-segment cap at (%.2f, %.2f, %.2f)"
						% [segments, origin.x, origin.y, origin.z]
					)
				)
			)
		)
	)
