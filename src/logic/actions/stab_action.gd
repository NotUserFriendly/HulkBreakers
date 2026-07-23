class_name StabAction
extends CombatAction

## taskblock-25 Pass B (docs/PLAN.md "Phase M — Melee"): a stab — a point
## payload, the first of the three melee payload types (Pass C adds slash/
## hold). Structurally a sibling of `AttackAction`, not a subclass of it
## (same posture `BurstAction` already established) — the two share
## exactly what's been factored out (`ShotResolution.resolve_and_log_point`,
## `DamageResolver`, `ShotPlane`, `RangeModel`, `Dartboard`), never a
## second, parallel resolution path (docs/PLAN.md: "melee is not a
## parallel resolver").
##
## The one real difference from `AttackAction.is_legal`: legality is
## reach-gated (`MeleeReach.in_reach`, a real 3D distance) instead of
## range/LoS-gated — a strike doesn't check `RangeModel`/`LoS` at all, the
## same way a shot never checks reach. `apply()` otherwise reuses the
## ranged accuracy pipeline UNCHANGED (tb34 Pass A: `ShotScatter.for_shot`,
## same as every other consumer) — melee's own tight dartboard is
## "point-blank range through the existing curve," never a special rule
## (docs/PLAN.md Pass B).

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
	var provides_a_stab: bool = (
		weapon != null
		and weapon.provides_actions.any(
			func(id: StringName) -> bool: return id in ActionCatalog.MELEE_ACTION_IDS
		)
	)
	if (
		weapon == null
		or weapon.hp <= 0
		or WoundEffects.is_disabled_by_wounds(weapon)
		or not provides_a_stab
	):
		return false
	if actual.ap < weapon.ap_cost:
		return false

	if not state.grid.in_bounds(target_cell):
		return false
	var target: Unit = _unit_at(state, target_cell)
	if target == null:
		return false
	if not MeleeReach.in_reach(actual.shell, weapon, MeleeReach.distance_3d(actual, target)):
		return false

	var manipulators: Array[Part] = []
	for part: Part in actual.shell.operable_parts():
		if part != weapon:
			manipulators.append(part)
	return PartGraph.can_operate(weapon, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var weapon: Part = actual.shell.find_part(weapon_id)
	actual.ap -= weapon.ap_cost

	if actual.cell != target_cell:
		FaceAction.face_for_free(
			state, actual, FaceAction.orientation_toward(actual.cell, target_cell)
		)

	if state.is_preview:
		# Same posture as AttackAction: RESOLUTION alone decides whether the
		# strike actually lands.
		return

	var target: Unit = _unit_at(state, target_cell)
	# taskblock-26 Pass A2 (re-fix): anchor the plane on the real muzzle
	# position, not the shooter's bare cell center — see AttackAction's own
	# doc comment for why.
	var muzzle: Vector3 = UnitGeometry.shouldered_muzzle_point(actual, weapon)
	var origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
	# taskblock-27 Pass A1: `direction` must share `origin`'s own muzzle
	# anchor — see AttackAction's own doc comment.
	var direction := Vector2(target_cell) - origin
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + aim_offset
	var muzzle_hit: Region = ShotPlane.self_obstruction(plane, muzzle.y, actual.shell.all_parts())
	if muzzle_hit != null and not (muzzle_hit.body is Unit):
		aim_point = Vector2(0.0, muzzle.y) + aim_offset
	var resolved_scatter: Array[Ring] = ShotScatter.for_shot(
		actual, weapon, target_cell, state, extra_sources
	)
	var points: Array[Vector2] = Dartboard.sample(
		aim_point, resolved_scatter, state.rng, weapon.burst
	)

	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, extra_sources).current
	var bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, extra_sources).current
	# taskblock-25 Pass D: the spherecast radius — "a pointed weapon is fat
	# compared to a bullet." 0.0 for an unauthored weapon_def, same as
	# every other melee number this action reads.
	var stab_width: float = weapon.weapon_def.stab_width if weapon.weapon_def != null else 0.0

	for point: Vector2 in points:
		ShotResolution.resolve_and_log_point(
			state,
			actual,
			origin,
			direction,
			point,
			damage,
			crit_chance,
			bonus_pen,
			mission,
			false,
			RangeModel.max_range(weapon),
			muzzle.y,
			DamageResolver.DEFLECT_MODE_SLIDE,
			stab_width
		)

	if target.alive and target.shell.living_parts().is_empty():
		state.kill_unit(target)

	state.log_action("StabAction: unit %d stabbed %s at %s" % [actual.id, weapon_id, target_cell])


func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for candidate: Unit in state.units:
		if candidate.alive and candidate.cell == cell:
			return candidate
	return null


func describe() -> String:
	return "StabAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]


## Same convention as AttackAction/BurstAction.speed().
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
