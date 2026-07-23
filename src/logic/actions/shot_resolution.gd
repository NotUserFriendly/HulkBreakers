class_name ShotResolution
extends RefCounted

## taskblock-13 Pass C: the impact-resolve-and-log loop `AttackAction`
## originally owned alone (one `DamageResolver.resolve_shot` call, then a
## ~160-line cascade of part_destroyed/detonate/fragment/matrix_ejected/
## surrogate_ejected/surrogate_demoted/subtree_dropped event logging),
## factored out so `BurstAction` (N independent pulls, not one) can share
## it byte-for-byte instead of duplicating that cascade. `mission` is
## passed explicitly by each caller — salvage crediting only, no shared
## mutable state between them.


## Resolves one shot landing at `point` and logs every consequence to
## `state.combat_log` — side effects only, exactly what AttackAction's
## own per-point loop body used to do inline. Returns true iff this point
## actually landed at least one impact (taskblock-19 Pass H: BurstAction
## uses this to report each pull's own real outcome — a dartboard roll
## that lands in empty space, hitting nothing, is a genuine miss, not a
## dropped pull, and callers that want to tell the two apart need this
## back rather than re-deriving it).
##
## `is_dud` (taskblock-19 Pass C2): true when this shot fired under a
## dud-capable weapon's own `min_range` — the damage cascade runs
## identically (see `RangeModel.is_dud`'s own doc comment: no separate
## payload system exists to suppress), only the log entry differs, so a
## future payload/AoE system has a real flag to check.
## taskblock-21 Pass F: `max_range` — the weapon's own authored
## `RangeModel.max_range` if the caller has one, 0.0 (unauthored) otherwise
## — is ONLY consulted on a genuine miss, to know how far the void tracer
## below should draw. It plays no part in whether anything was actually
## hit; that's still `DamageResolver.resolve_shot` alone, unchanged.
## taskblock-23 Pass C: `origin_height` is this shot's own real muzzle
## height (e.g. `UnitGeometry.shouldered_muzzle_point(...).y`) — stamped
## onto the first hop's own `ImpactResult.origin_height` so a real 3D
## tracer (Pass D) has it, same real-height convention `resolve_shot`'s
## own ricochet hops already carry for free.
## taskblock-37 Pass A: `vertical_slope` is this FIRST hop's own real rise
## per unit of ground distance (`ShotPlane.elevation_for`'s own return,
## the same quantity every production firing action now computes) —
## appended last, not inserted alongside `origin_height` above, so no
## existing positional caller shifts. `0.0` (every caller before this
## pass) reduces to the exact old flat-shot behavior. `point_depth` is
## the depth `point` (the dartboard's own aim point, generally anchored on
## the target via `ShotPlane.center_of`/`depth_of`) is itself anchored at
## — needed so `DamageResolver._find_next` tests OTHER candidates along a
## tilted ray relative to the AIM point's own depth, not depth zero (see
## its own doc comment). `0.0` (every caller before this pass, and every
## ricochet still) is exactly right when there's no real tilt to correct
## for, or when the point is already anchored at depth zero by
## construction.
static func resolve_and_log_point(
	state: CombatState,
	attacker: Unit,
	origin: Vector2,
	direction: Vector2,
	point: Vector2,
	damage: float,
	crit_chance: float,
	bonus_pen: float,
	mission: MissionState,
	is_dud: bool = false,
	max_range: float = 0.0,
	origin_height: float = 0.0,
	deflect_mode: StringName = DamageResolver.DEFLECT_MODE_RICOCHET,
	radius: float = 0.0,
	vertical_slope: float = 0.0,
	point_depth: float = 0.0
) -> bool:
	var results: Array[ImpactResult] = DamageResolver.resolve_shot(
		origin,
		direction,
		point,
		damage,
		crit_chance,
		state,
		state.material_table,
		state.rng,
		0,
		DamageResolver.DEFAULT_MAX_RICOCHET_DEPTH,
		DamageResolver.DEFAULT_DAMAGE_FLOOR,
		DamageResolver.DEFAULT_CRIT_BONUS_MULTIPLIER,
		attacker.shell.all_parts(),
		bonus_pen,
		vertical_slope,
		origin_height,
		deflect_mode,
		radius,
		point_depth
	)
	for result: ImpactResult in results:
		log_impact_result(state, attacker, result, mission, is_dud, max_range)
	if results.is_empty():
		log_miss_result(state, attacker, origin, direction, point, max_range, origin_height)
	return not results.is_empty()


## taskblock-21 Pass F: "every fired shot draws its ray, hit or miss — the
## ray still travels to somewhere." A genuinely EMPTY `results` here can
## only mean the round's own dartboard point landed nowhere ANY region in
## the whole shot plane covers — every wall/cover object is already its
## own `Region` (`ShotPlane.build`'s own blockers loop), so a real "hit a
## wall" always comes back as a normal `ImpactResult` above, never an
## empty list. An empty list is always the void: nothing physical was
## there to stop it. Mirrors `resolve_shot`'s own `muzzle_to_impact` math
## (`dir * depth + perp * point.x`) with `depth` set to the weapon's own
## `max_range` when authored, or the map's own longest side otherwise (a
## flagged "far enough to draw off-board" fallback, not a tuned number —
## an unauthored weapon has no real range cap to draw to at all).
## taskblock-23 Pass C/D: `origin_height` is this shot's own real muzzle
## height (same convention `resolve_and_log_point`'s own doc comment
## already established) — logged alongside `origin_x/y` so the view can
## draw a miss's own tracer from its real 3D muzzle, not a re-derived
## approximation. `end_height` is the void ray's own height — a miss
## can't ricochet or penetrate, so it travels dead level at the shot's own
## aimed height (`point.y`) the whole way, same flat assumption
## `resolve_shot`'s own first hop always makes.
##
## taskblock-28 Pass C: made public (was `_log_miss`) — the companion fix
## to BR27.02's own visibility gap. `data` already carried this shot's
## real geometry (taskblock-22/23); what was actually missing was a way
## to SEE it without inspecting `data` by hand, since `LogEvent._to_string()`
## renders only `text` — so `text` itself now carries the same numbers, and
## this is exposed so a caller other than `resolve_and_log_point` (namely
## `Overwatch._fire`, which used to hand-roll its own, geometry-less
## `&"impact"` event) can log through the one real path instead of a
## second, parallel one.
static func log_miss_result(
	state: CombatState,
	attacker: Unit,
	origin: Vector2,
	direction: Vector2,
	point: Vector2,
	max_range: float,
	origin_height: float = 0.0
) -> void:
	var dir: Vector2 = direction.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var void_range: float = (
		max_range if max_range > 0.0 else maxf(state.grid.width, state.grid.rows)
	)
	var end: Vector2 = origin + dir * void_range + perp * point.x
	(
		state
		. combat_log
		. emit(
			(
				LogEvent
				. new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker.id,
					&"miss",
					{
						"origin_x": origin.x,
						"origin_y": origin.y,
						"origin_height": origin_height,
						"end_x": end.x,
						"end_y": end.y,
						"end_height": point.y,
					},
					(
						"missed — origin (%.2f, %.2f)@%.2f -> ray ends (%.2f, %.2f)@%.2f"
						% [origin.x, origin.y, origin_height, end.x, end.y, point.y]
					)
				)
			)
		)
	)


## taskblock-28 Pass C: made public (was `_log_impact`) — see
## `log_miss_result`'s own doc comment for why.
static func log_impact_result(
	state: CombatState,
	attacker: Unit,
	result: ImpactResult,
	mission: MissionState,
	is_dud: bool = false,
	max_range: float = 0.0
) -> void:
	var outcome_name: String = (
		"BYPASS" if result.bypassed_armor else Enums.Outcome.keys()[result.outcome]
	)
	# taskblock-28 Pass C: the geometry suffix is the whole point of this
	# pass — a backward-travelling shot (BR27.02's own class of bug) is
	# now readable in `out/combat.log` text directly, not only in `data`
	# (which already carried origin_x/y/height + hit_x/y/height since
	# taskblock-22/23 — `LogEvent._to_string()` just never rendered it).
	var text: String = (
		"%s on %s [origin (%.2f, %.2f)@%.2f -> hit (%.2f, %.2f)@%.2f]"
		% [
			outcome_name,
			result.region.part.id,
			result.origin.x,
			result.origin.y,
			result.origin_height,
			result.hit_point.x,
			result.hit_point.y,
			result.hit_height,
		]
	)
	# docs/09 "if it changed the world, it's in the log": which UNIT actually
	# took the hit (not just which part) — a ricochet can tag a third party,
	# so this is never assumed to be the shooter's own original target.
	# -1 for cover/terrain, which has no unit id.
	var target_unit_id: int = result.region.body.id if result.region.body is Unit else -1
	# taskblock-22 Pass D: "the player reads the path" — origin_x/y and
	# hit_x/y are THIS hop's own real muzzle and landing point (same flat
	# cell-space coords the &"miss" event already carries), so the view can
	# draw every ricochet segment from the logged hop sequence directly,
	# never re-derived from a target's own current position.
	# taskblock-23 Pass C/D: origin_height/hit_height are the missing third
	# coordinate — real world height, not ground-plane — so a real 3D
	# tracer no longer has to guess or pin every hop to one height.
	var data: Dictionary = {
		"outcome": result.outcome,
		"part": result.region.part.id,
		"target_unit_id": target_unit_id,
		"damage": result.part_damage,
		"bypassed_armor": result.bypassed_armor,
		"is_crit": result.is_crit,
		"is_double_crit": result.is_double_crit,
		"is_dud": is_dud,
		"origin_x": result.origin.x,
		"origin_y": result.origin.y,
		"origin_height": result.origin_height,
		"hit_x": result.hit_point.x,
		"hit_y": result.hit_point.y,
		"hit_height": result.hit_height,
	}
	# taskblock-26 Pass A1: "the bounced secondary ray is computed, logged,
	# never drawn." `ImpactResult.reflected_dir`/`reflected_vertical` were
	# always computed by `resolve_impact` for a DEFLECT, but never made it
	# into the log data — a ricochet that then finds nothing to hit (an
	# empty `resolve_shot` recursion) produces NO further event at all, so
	# the view had nothing to draw even when it wanted to. Stamped here,
	# unconditionally on every DEFLECT, the same "void" convention
	# `log_miss_result` already uses for a shot that never hits anything — so the
	# reflected direction is always drawable regardless of whether a real
	# ricochet hop follows it.
	if result.outcome == Enums.Outcome.DEFLECT:
		var void_range: float = (
			max_range if max_range > 0.0 else maxf(state.grid.width, state.grid.rows)
		)
		var deflect_end: Vector2 = result.hit_point + result.reflected_dir * void_range
		data["deflect_end_x"] = deflect_end.x
		data["deflect_end_y"] = deflect_end.y
		data["deflect_end_height"] = result.hit_height + result.reflected_vertical * void_range
	var event := LogEvent.new(
		state.round_number, Enums.Phase.RESOLUTION, attacker.id, &"impact", data, text
	)
	state.combat_log.emit(event)

	# taskblock-20 Pass C4: "if it changed the world, it's in the log" — a
	# lodged wound doesn't require the part to be destroyed (the round can
	# floor well short of that), so this is checked independent of
	# `destroyed_part` below, not nested inside it.
	if result.wound_inflicted != &"":
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"wound_inflicted",
				{"part": result.region.part.id, "wound": result.wound_inflicted},
				"%s on %s" % [result.wound_inflicted, result.region.part.id]
			)
		)

	if result.destroyed_part:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"part_destroyed",
				{"part": result.region.part.id},
				"%s" % result.region.part.id
			)
		)
		_credit_salvage(state, attacker, result.region.part, mission)
		# taskblock-09 A1/A2: "if it changed the world, it's in the log" —
		# is_mangled/is_disabled are real, visible state changes (a
		# quartered DT, a dead weapon), not just bookkeeping alongside
		# part_destroyed.
		if result.region.part.is_mangled:
			state.combat_log.emit(
				LogEvent.new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker.id,
					&"part_mangled",
					{"part": result.region.part.id},
					"%s" % result.region.part.id
				)
			)
		if result.region.part.is_disabled:
			state.combat_log.emit(
				LogEvent.new(
					state.round_number,
					Enums.Phase.RESOLUTION,
					attacker.id,
					&"part_disabled",
					{"part": result.region.part.id},
					"%s" % result.region.part.id
				)
			)
	# taskblock-09 A3: renamed from "cook_off" — DETONATE, not cook-off.
	for detonated: Unit in result.detonated_units:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"detonate",
				{"source_part": result.region.part.id, "unit": detonated.id},
				"%s hit unit %d" % [result.region.part.id, detonated.id]
			)
		)
	# taskblock-09 A4: each fragment ray is its own full impact — same
	# logging path, recursively, so a fragment that itself penetrates/
	# deflects/ricochets is logged exactly like any other projectile.
	for fragment_result: ImpactResult in result.fragment_hits:
		log_impact_result(state, attacker, fragment_result, mission, false, max_range)
	if result.meltdown_armed:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"meltdown_armed",
				{"part": result.region.part.id},
				"%s" % result.region.part.id
			)
		)
	if result.ejected_matrix != null:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"matrix_ejected",
				{"host_part": result.region.part.id, "matrix": result.ejected_matrix.id},
				"%s from %s" % [result.ejected_matrix.id, result.region.part.id]
			)
		)
	# docs/04 taskblock02 Pass D1: the shell root destroyed while hosting an
	# ATTACHED surrogate (not a bare matrix) drops the whole surrogate,
	# matrix and all — distinct from matrix_ejected above, never both on
	# the same impact (DamageResolver.eject_surrogate_if_needed only fires
	# when eject_matrix_if_needed didn't).
	if result.ejected_surrogate != null:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"surrogate_ejected",
				{"host_part": result.region.part.id, "surrogate": result.ejected_surrogate.id},
				"%s from %s" % [result.ejected_surrogate.id, result.region.part.id]
			)
		)
	if result.demoted_unit != null:
		var cause: String = (
			"matrix_ejected" if result.ejected_matrix != null else "surrogate_ejected"
		)
		var demotion_data: Dictionary = {
			"from": result.demoted_tier_before.id,
			"to": result.demoted_unit.surrogate_tier.id,
			"cause": cause,
		}
		var demotion_text: String = (
			"unit %d %s -> %s (%s)"
			% [
				result.demoted_unit.id,
				result.demoted_tier_before.id,
				result.demoted_unit.surrogate_tier.id,
				cause,
			]
		)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				result.demoted_unit.id,
				&"surrogate_demoted",
				demotion_data,
				demotion_text
			)
		)
	# taskblock-09 C/D: a severed joint drops its whole intact subtree at
	# once — one event per part in it, never a summary, matching docs/09's
	# "if it changed the world, it's in the log." This is the ONLY producer
	# of `dropped_subtree` now (destroyed_part above is a wholly separate,
	# mutually exclusive path — MANGLE/DISABLE/DETONATE/FRAGMENT/MELTDOWN
	# never detach), so nothing here was credited/logged earlier the way a
	# destroyed part's own salvage already was above.
	for dropped: Part in result.dropped_subtree:
		_credit_salvage(state, attacker, dropped, mission)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"subtree_dropped",
				{"part": dropped.id},
				"%s" % dropped.id
			)
		)


## docs/10 taskblock04 C3: "cut it apart or destroy it, get the resources...
## this is where docs/07's harvest loop finally touches the board." A
## no-op with no mission context (a standalone battle) or on a part with
## nothing to salvage (everything that isn't a field object) — the same
## MissionState.gather_resource() a real GatherAction call already uses,
## never a separate crediting path.
static func _credit_salvage(
	state: CombatState, attacker: Unit, destroyed: Part, mission: MissionState
) -> void:
	if mission == null or destroyed.salvage_yield.is_empty():
		return
	for resource_id: StringName in destroyed.salvage_yield:
		var amount: int = int(destroyed.salvage_yield[resource_id])
		mission.gather_resource(resource_id, amount)
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				attacker.id,
				&"salvage_credited",
				{"part": destroyed.id, "resource": resource_id, "amount": amount},
				"%d %s from %s" % [amount, resource_id, destroyed.id]
			)
		)
