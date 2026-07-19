class_name BurstAction
extends CombatAction

## taskblock-13 Pass C: BURST — `WeaponDef.burst_size` independent
## trigger-pulls in one activation, each its own dartboard roll (never
## the same static distribution sampled N times the way `Part.burst`/
## `AttackAction` do today — see `weapon.burst`'s own doc comment). This
## is distinct from a shotgun's multi-PROJECTILE spread (one pull, N
## pellets, `SpreadPattern`/`AmmoDef.projectile_num`) — a burst is N
## PULLS, each of which can itself be a multi-pellet pull.
##
## Structurally a sibling of `AttackAction`, not a subclass of it — the
## two share only what's been factored out (`ShotResolution`'s
## resolve-and-log loop), never AttackAction's own single-pull `apply()`.

var unit: Unit
var weapon_id: StringName
var target_cell: Vector2i
var aim_offset: Vector2
var extra_sources: Array[ModSource]
var mission: MissionState


func _init(
	p_unit: Unit,
	p_weapon_id: StringName,
	p_target_cell: Vector2i,
	p_aim_offset: Vector2 = Vector2.ZERO,
	p_extra_sources: Array[ModSource] = [],
	p_mission: MissionState = null
) -> void:
	unit = p_unit
	weapon_id = p_weapon_id
	target_cell = p_target_cell
	aim_offset = p_aim_offset
	extra_sources = p_extra_sources
	mission = p_mission


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false

	var weapon: Part = actual.shell.find_part(weapon_id)
	if weapon == null or weapon.hp <= 0 or weapon.weapon_def == null:
		return false
	if WoundEffects.is_disabled_by_wounds(weapon) or weapon.weapon_def.burst_size <= 1:
		return false
	if actual.ap < _ap_cost(weapon) or Suppression.blocks_weapon(state, actual, weapon):
		return false

	if not state.grid.in_bounds(target_cell):
		return false
	var target: Unit = _unit_at(state, target_cell)
	if target == null:
		return false

	var range_cells: int = Grid.distance_chebyshev(actual.cell, target_cell)
	if not RangeModel.is_in_max_range(weapon, range_cells):
		return false
	if RangeModel.blocks_min_range(weapon, range_cells):
		return false
	if not LoS.has_los(state.grid, actual.cell, target_cell):
		return false

	var manipulators: Array[Part] = []
	for part: Part in actual.shell.operable_parts():
		if part != weapon:
			manipulators.append(part)
	return PartGraph.can_operate(weapon, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var weapon: Part = actual.shell.find_part(weapon_id)
	actual.ap -= _ap_cost(weapon)

	if actual.cell != target_cell:
		FaceAction.face_for_free(
			state, actual, FaceAction.orientation_toward(actual.cell, target_cell)
		)

	if state.is_preview:
		# Same posture as AttackAction: RESOLUTION alone decides whether any
		# round in the burst actually lands.
		return

	var target: Unit = _unit_at(state, target_cell)
	var origin := Vector2(actual.cell.x, actual.cell.y)
	var direction := Vector2(target_cell - actual.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + aim_offset
	var range_cells: int = Grid.distance_chebyshev(actual.cell, target_cell)
	var radius_multiplier: float = RangeModel.dartboard_radius_scale(weapon, range_cells)
	var is_dud: bool = RangeModel.is_dud(weapon, range_cells)

	# docs/08: the same resolved numbers a tooltip would show, never a raw
	# Part field read directly — identical convention to AttackAction.
	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, extra_sources).current
	var bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, extra_sources).current
	var ammo: AmmoDef = DataLibrary.get_ammo(weapon.ammo_id) if weapon.ammo_id != &"" else null
	var burst_size: int = weapon.weapon_def.burst_size
	# taskblock-13 Pass D: recoil's own per-step amount, resolved ONCE per
	# activation (it depends only on the resolved damage/barrel_length,
	# neither of which changes pull to pull) — RecoilResolver.widen then
	# scales it by however many steps a given pull has accumulated.
	var recoil_step: float = (
		WeaponResolver.resolve_recoil_step(weapon, damage, extra_sources).current
	)

	# "make sure the log doesn't drown — one summary event per burst,
	# detail per impact" (taskblock-13 Pass C, explicit) — the one
	# deliberate exception to this codebase's otherwise-universal "every
	# individual state change is its own event, never a summary" rule
	# (see FRAGMENT/DETONATE/subtree_dropped, all of which reject exactly
	# this shape): a burst can throw hundreds of rays (3 pulls x 9
	# buckshot pellets and up), where FRAGMENT/DETONATE never scale past a
	# handful. Every individual impact still gets its own full event below
	# — nothing about "detail per impact" is suppressed, only a marker for
	# "a burst started" is added on top.
	state.combat_log.emit(
		LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			actual.id,
			&"burst_fired",
			{"weapon": weapon_id, "round_count": burst_size},
			"%s fires a %d-round burst at %s" % [weapon_id, burst_size, target_cell]
		)
	)

	# taskblock-19 Pass H: "diagnose against a real burst" found no actual
	# pull-dropping bug — is_legal()/apply() have always read the same
	# weapon.weapon_def.burst_size (verified against the original
	# taskblock-13 commit). The loop below genuinely runs `burst_size`
	# times, every time; what varies pull to pull is whether that pull's
	# own dartboard roll actually LANDS on anything — a real, expected
	# miss when a wide/outer-weighted scatter (the real chaingun's own
	# authored rings, say) rolls outside every hittable region, same as
	# any single AttackAction shot can miss. `&"burst_pull"` makes this
	# directly observable instead of inferred from `impact` event counts
	# alone: one event per pull, unconditionally (proves execution —
	# exactly `burst_size` of these must exist), each carrying
	# `landed_so_far` (proves how many of the pulls SO FAR actually hit,
	# not just fired).
	var landed_so_far := 0
	for pull in range(burst_size):
		# taskblock-13 Pass D: pull 0 is on-target; every pull after it
		# widens the DARTBOARD (never the mechanical spread pattern below)
		# by one more cumulative recoil step — resets to 0 automatically
		# next activation, since `pull` is this loop's own local counter,
		# never carried on the weapon/unit between calls.
		var resolved_scatter: Array[Ring] = Dartboard.resolve_scatter(
			weapon, extra_sources, radius_multiplier
		)
		var widened_scatter: Array[Ring] = RecoilResolver.widen(resolved_scatter, recoil_step, pull)
		var pull_point: Vector2 = Dartboard.sample(aim_point, widened_scatter, state.rng, 1)[0]
		var pellet_points: Array[Vector2] = SpreadPattern.sample(
			pull_point, weapon, ammo, state.rng
		)
		var pull_hit := false
		for point: Vector2 in pellet_points:
			var landed: bool = ShotResolution.resolve_and_log_point(
				state,
				actual,
				origin,
				direction,
				point,
				damage,
				crit_chance,
				bonus_pen,
				mission,
				is_dud,
				RangeModel.max_range(weapon)
			)
			pull_hit = pull_hit or landed
		if pull_hit:
			landed_so_far += 1
		# `apply()` returns early on a preview (above) before this loop is
		# ever reached — every event here is real, never gated on
		# `is_preview` the way `_log_impact`'s own calls are.
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"burst_pull",
				{
					"pull_index": pull,
					"burst_size": burst_size,
					"hit": pull_hit,
					"landed_so_far": landed_so_far
				},
				(
					"pull %d/%d: %s (%d/%d landed so far)"
					% [pull + 1, burst_size, "hit" if pull_hit else "miss", landed_so_far, pull + 1]
				)
			)
		)

	# Phase 6 placeholder, same as AttackAction: no living parts left
	# disables the unit — Phase 7's real matrix-ejection rule supersedes.
	if target.alive and target.shell.living_parts().is_empty():
		state.kill_unit(target)

	state.log_action(
		(
			"BurstAction: unit %d fired %s (%d rounds) at %s"
			% [actual.id, weapon_id, burst_size, target_cell]
		)
	)


func _ap_cost(weapon: Part) -> int:
	if weapon.weapon_def != null and weapon.weapon_def.burst_ap_cost > 0:
		return weapon.weapon_def.burst_ap_cost
	return weapon.ap_cost


func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for candidate: Unit in state.units:
		if candidate.alive and candidate.cell == cell:
			return candidate
	return null


func describe() -> String:
	return "BurstAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]


## Same convention as AttackAction.speed().
func speed(state: CombatState) -> float:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null:
		return super.speed(state)
	var weapon: Part = actual.shell.find_part(weapon_id)
	if weapon == null:
		return super.speed(state)
	return weapon.speed


func unit_id() -> int:
	return unit.id
