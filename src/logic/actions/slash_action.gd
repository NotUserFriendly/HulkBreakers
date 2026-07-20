class_name SlashAction
extends CombatAction

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): a slash — a LINE
## payload (horizontal/45°/vertical, `MeleeLine.sample`), `weapon_def.
## slash_length` long, centered on the ordinary aim point — "hits
## everything along it... more damage." Structurally a sibling of
## `StabAction`/`AttackAction` (same posture `BurstAction` already
## established), sharing `ShotResolution.resolve_and_log_point`/
## `DamageResolver`/`ShotPlane` verbatim. Each point along the line
## resolves with `DEFLECT_MODE_NONE` — a deflected point along a swing
## doesn't ricochet or slide, it just contributes nothing and the NEXT
## point further along the line still fires (docs/PLAN.md: "hits
## everything along it").

var unit: Unit
var weapon_id: StringName
var target_cell: Vector2i
var orientation: StringName
var aim_offset: Vector2
var extra_sources: Array[ModSource]
var mission: MissionState


func _init(
	p_unit: Unit,
	p_weapon_id: StringName,
	p_target_cell: Vector2i,
	p_orientation: StringName = &"horizontal",
	p_aim_offset: Vector2 = Vector2.ZERO,
	p_extra_sources: Array[ModSource] = [],
	p_mission: MissionState = null
) -> void:
	unit = p_unit
	weapon_id = p_weapon_id
	target_cell = p_target_cell
	orientation = p_orientation
	aim_offset = p_aim_offset
	extra_sources = p_extra_sources
	mission = p_mission


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false

	var weapon: Part = actual.shell.find_part(weapon_id)
	var provides_a_slash: bool = (
		weapon != null
		and weapon.provides_actions.any(
			func(id: StringName) -> bool: return id in ActionCatalog.SLASH_ACTION_IDS
		)
	)
	if (
		weapon == null
		or weapon.hp <= 0
		or WoundEffects.is_disabled_by_wounds(weapon)
		or not provides_a_slash
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
		return

	var target: Unit = _unit_at(state, target_cell)
	# taskblock-26 Pass A2 (re-fix): anchor the plane on the real muzzle
	# position, not the shooter's bare cell center — see AttackAction's own
	# doc comment for why.
	var muzzle: Vector3 = UnitGeometry.shouldered_muzzle_point(actual, weapon)
	var origin := Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE
	var direction := Vector2(target_cell - actual.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + aim_offset
	var slash_length: float = weapon.weapon_def.slash_length if weapon.weapon_def != null else 0.0
	var points: Array[Vector2] = MeleeLine.sample(aim_point, slash_length, orientation)

	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, extra_sources).current
	var bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, extra_sources).current

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
			DamageResolver.DEFLECT_MODE_NONE
		)

	if target.alive and target.shell.living_parts().is_empty():
		state.kill_unit(target)

	state.log_action(
		(
			"SlashAction: unit %d slashed %s (%s) at %s"
			% [actual.id, weapon_id, orientation, target_cell]
		)
	)


func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for candidate: Unit in state.units:
		if candidate.alive and candidate.cell == cell:
			return candidate
	return null


func describe() -> String:
	return "SlashAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]


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
