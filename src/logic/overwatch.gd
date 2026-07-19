class_name Overwatch
extends RefCounted

## docs/09 taskblock06 Pass F2: the actual trigger. Checked at every cell
## step a queued MoveAction actually takes (via `check_trigger`, the
## Callable MoveAction.apply_stepwise's `mid_move_hook` seam — taskblock06
## Pass D — exists for): torso visible, in arc, in range. Not center-of-
## mass, not any-part — the torso specifically, so hugging cover that
## only lets your legs clear a crate does NOT trigger, for free, out of
## geometry (no code needed to special-case it).

## Flagged starting data (docs/09 taskblock06 F1), not a tuned design
## number: the unit's own facing +/- this many degrees.
const ARC_DEG := 45.0


## Fires every still-armed overwatcher (docs/09 taskblock06 D4: several
## can trigger off the same step) whose conditions are met against
## `mover`'s current cell — called once per cell `mover` actually steps
## onto, never re-checked against cells already passed (docs/09 taskblock06
## F2: "the trigger fires at the FIRST qualifying cell"). Returns `true`
## the instant any overwatcher fires — MoveAction.apply_stepwise's own
## `mid_move_hook` contract (docs/09 taskblock06 F2: "the mover freezes")
## reads a `true` result as an unconditional freeze at this cell, separate
## from and prior to Pass D's own MP/AP legality check.
static func check_trigger(state: CombatState, mover: Unit) -> bool:
	var triggered: bool = false
	for overwatcher: Unit in state.units.duplicate():
		if overwatcher == mover or not overwatcher.alive:
			continue
		var weapon: Part = _qualifying_weapon(state, overwatcher, mover)
		if weapon == null:
			continue
		_fire(state, overwatcher, weapon, mover)
		triggered = true
	return triggered


## taskblock-18 D1/D4: "the firing cell is NOT covered... discloses
## exposure — is it in a known overwatch arc, what can see it." Every
## still-armed, currently-alive overwatcher that WOULD trigger if `mover`
## stood at `candidate_cell` right now — asked in advance, nothing fired,
## nothing mutated. Real units (never clones) so a caller can safely hold
## onto the result. `candidate_cell == mover.cell` skips the speculative
## clone entirely (nothing hypothetical to ask).
static func would_trigger_at(
	state: CombatState, mover: Unit, candidate_cell: Vector2i
) -> Array[Unit]:
	if candidate_cell == mover.cell:
		var same_cell: Array[Unit] = []
		for overwatcher: Unit in _qualifying_overwatchers(state, mover):
			same_cell.append(state.find_unit(overwatcher.id))
		return same_cell
	var preview: CombatState = state.dup()
	var mover_clone: Unit = preview.find_unit(mover.id)
	if mover_clone == null:
		return []
	# Same "ask a speculative clone" pattern ActionQueue.preview() already
	# uses — never mutate the real state just to answer a hypothetical.
	preview.grid.set_occupant_id(mover_clone.cell, -1)
	mover_clone.cell = candidate_cell
	if preview.grid.in_bounds(candidate_cell):
		preview.grid.set_occupant_id(candidate_cell, mover_clone.id)
	var qualifying: Array[Unit] = _qualifying_overwatchers(preview, mover_clone)
	var real: Array[Unit] = []
	for overwatcher: Unit in qualifying:
		real.append(state.find_unit(overwatcher.id))
	return real


static func _qualifying_overwatchers(state: CombatState, mover: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for overwatcher: Unit in state.units:
		if overwatcher == mover or not overwatcher.alive:
			continue
		if _qualifying_weapon(state, overwatcher, mover) != null:
			result.append(overwatcher)
	return result


## The one qualifying predicate (docs/09 taskblock06 F1/F2: torso visible,
## in arc, in range) `check_trigger` (real, firing) and `would_trigger_at`
## (speculative, non-firing) both share, so they can never silently drift
## apart — returns the overwatcher's own qualifying weapon, or null.
static func _qualifying_weapon(state: CombatState, overwatcher: Unit, mover: Unit) -> Part:
	if overwatcher.overwatch_weapon_id == &"":
		return null
	var weapon: Part = overwatcher.shell.find_part(overwatcher.overwatch_weapon_id)
	if weapon == null or weapon.hp <= 0:
		return null
	if not _in_arc(overwatcher, mover):
		return null
	var range_cells: int = Grid.distance_chebyshev(overwatcher.cell, mover.cell)
	if weapon.weapon_max_range > 0.0 and range_cells > int(weapon.weapon_max_range):
		return null
	if not LoS.has_los(state.grid, overwatcher.cell, mover.cell):
		return null
	if not _torso_visible(state, overwatcher, mover, weapon):
		return null
	return weapon


## docs/09 taskblock06 F1: "arc: the unit's facing +/- 45 degrees."
## docs/09 taskblock07 Pass B1: BodyProjector.forward_for(), not
## WORLD_FORWARD.rotated() directly — that was the OTHER, mirrored
## rotation convention, silently checking the arc against the wrong side
## of an asymmetric-facing overwatcher.
static func _in_arc(overwatcher: Unit, mover: Unit) -> bool:
	var to_mover := Vector2(mover.cell - overwatcher.cell)
	if to_mover.is_zero_approx():
		return false
	var facing: Vector2 = BodyProjector.forward_for(overwatcher.orientation)
	var angle_deg: float = rad_to_deg(absf(facing.angle_to(to_mover)))
	return angle_deg <= ARC_DEG


## docs/09 taskblock06 F2: "something like torso visible... a dumb and
## easy way to check 'could overwatch theoretically kill this target.'"
## The torso's own region, at its own center, must be the FRONTMOST thing
## a real ray hits there — cover (or the mover's own limbs) sitting in
## front of it at that exact point means it doesn't qualify, even though
## the torso still has a region in the plane somewhere.
##
## docs/09 taskblock07 Pass A: "it's a visibility query, not a hit test,
## but it's still asking 'what does a shot from here hit first?' and must
## give the same answer as the shot" — routed through `ShotPlane.resolve_ray`
## now, cast from `overwatcher`'s own weapon muzzle, rather than a direct
## `resolve_projectile` lookup that could silently drift from what a real
## ray (or later, a real `intersect_ray`) would actually hit.
static func _torso_visible(
	state: CombatState, overwatcher: Unit, mover: Unit, weapon: Part
) -> bool:
	var torso: Part = mover.shell.root
	if torso == null or torso.hp <= 0:
		return false
	var direction := Vector2(mover.cell - overwatcher.cell)
	if direction.is_zero_approx():
		return false
	# Still built once, plane-space, purely to find the torso's own
	# rect-center as an aim point — the SAME coordinate convention
	# AimPlaneGeometry.ray_from_muzzle expects (anchored on this exact
	# shooter->target dead-ahead axis), never resolved against directly.
	var plane: Array[Region] = ShotPlane.build(
		Vector2(overwatcher.cell.x, overwatcher.cell.y), direction.normalized(), state
	)
	var torso_region: Region = _torso_region(plane, torso, mover)
	if torso_region == null:
		return false
	var muzzle: Vector3 = UnitGeometry.muzzle_point(overwatcher, weapon)
	var ray: Dictionary = AimPlaneGeometry.ray_from_muzzle(
		overwatcher.cell, mover.cell, torso_region.rect.get_center(), muzzle
	)
	if ray.is_empty():
		return false
	var resolved: HitResult = ShotPlane.resolve_ray(ray["origin"], ray["dir"], state)
	return resolved != null and resolved.part == torso and resolved.body == mover


static func _torso_region(plane: Array[Region], torso: Part, mover: Unit) -> Region:
	for region: Region in plane:
		if region.part == torso and region.body == mover:
			return region
	return null


## docs/09 taskblock06 F1/F2: "fires once, then spent" — a default burst
## at the torso, the same DamageResolver.resolve_shot cascade AttackAction
## itself uses (docs/08: never a separate, ad-hoc resolution path).
static func _fire(state: CombatState, overwatcher: Unit, weapon: Part, mover: Unit) -> void:
	overwatcher.overwatch_weapon_id = &""

	var origin := Vector2(overwatcher.cell.x, overwatcher.cell.y)
	var direction := Vector2(mover.cell - overwatcher.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var torso: Part = mover.shell.root
	var torso_region: Region = _torso_region(plane, torso, mover)
	var aim_point: Vector2 = (
		torso_region.rect.get_center()
		if torso_region != null
		else ShotPlane.center_of(plane, mover)
	)

	var damage: float = WeaponResolver.resolve_damage(weapon, []).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, []).current
	var bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, []).current
	var points: Array[Vector2] = Dartboard.sample(
		aim_point, Dartboard.resolve_scatter(weapon, []), state.rng, weapon.burst
	)

	var text: String = (
		"Overwatch: unit %d fired %s at unit %d" % [overwatcher.id, weapon.id, mover.id]
	)
	state.log_action(text)
	if not state.is_preview:
		(
			state
			. combat_log
			. emit(
				(
					LogEvent
					. new(
						state.round_number,
						Enums.Phase.RESOLUTION,
						overwatcher.id,
						&"overwatch_triggered",
						{"weapon": weapon.id, "target_unit_id": mover.id},
						# Overwatch fires out of turn order — the reacting unit is
						# never the one a `turn_start` header most recently named,
						# so both units stay explicit here rather than being
						# assumed from context the way an in-turn action can be.
						"unit %d fired %s at unit %d" % [overwatcher.id, weapon.id, mover.id]
					)
				)
			)
		)

	for point: Vector2 in points:
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
			overwatcher.shell.all_parts(),
			bonus_pen
		)
		if state.is_preview:
			continue
		for result: ImpactResult in results:
			var outcome_name: String = (
				"BYPASS" if result.bypassed_armor else Enums.Outcome.keys()[result.outcome]
			)
			(
				state
				. combat_log
				. emit(
					(
						LogEvent
						. new(
							state.round_number,
							Enums.Phase.RESOLUTION,
							overwatcher.id,
							&"impact",
							{
								"outcome": result.outcome,
								"part": result.region.part.id,
								"target_unit_id": mover.id,
								"damage": result.part_damage,
								"bypassed_armor": result.bypassed_armor,
								"is_crit": result.is_crit,
							},
							"%s on %s (overwatch)" % [outcome_name, result.region.part.id]
						)
					)
				)
			)

	if mover.alive and mover.shell.living_parts().is_empty():
		state.kill_unit(mover)
