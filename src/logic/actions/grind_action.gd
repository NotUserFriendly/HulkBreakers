class_name GrindAction
extends CombatAction

## taskblock-25 Pass C (docs/PLAN.md "Phase M — Melee"): the "hold" payload
## — "grab + grind a saw into a joint... many tiny hits in sequence,
## continuing if it gets through cladding... no deflect — binary: chew
## through or nothing." Named `GrindAction`, not `HoldAction`: that class
## name is already taken (taskblock-19 Pass F's "defer to the next ally"
## turn action) — this still provides/is armed as action id `&"hold"`, the
## taskblock's own payload name, only the GDScript class avoids the
## collision.
##
## `weapon.burst` (the same field a ranged weapon already uses for "how
## many pulls in one activation") doubles as the hit count here — the same
## underlying concept, no new field. Each hit resolves through the exact
## same `ShotResolution.resolve_and_log_point`/`DamageResolver` pipeline
## every other melee payload does, `DEFLECT_MODE_NONE` (a non-penetrating
## hit just stops, never bounces or slides), at the SAME point every time
## (a grind doesn't scatter — it's grabbed on).
##
## "Stacked bonus-pen, raw/linear, uncapped. Each tiny hit adds bonus-pen
## (3 hits × 2 pen = 6 effective)" — hit `i` (1-indexed) resolves with
## `base_bonus_pen * i`, so the round genuinely bites in deeper each pass;
## `DamageResolver.resolve_shot`'s own existing PENETRATE cascade (spill
## damage carrying into whatever's behind a destroyed layer) already gives
## "continues if it gets through cladding" for free within a single hit —
## nothing new needed there.

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
	var provides_a_hold: bool = (
		weapon != null
		and weapon.provides_actions.any(
			func(id: StringName) -> bool: return id in ActionCatalog.GRIND_ACTION_IDS
		)
	)
	if (
		weapon == null
		or weapon.hp <= 0
		or WoundEffects.is_disabled_by_wounds(weapon)
		or not provides_a_hold
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
	var origin := Vector2(actual.cell.x, actual.cell.y)
	var direction := Vector2(target_cell - actual.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + aim_offset

	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, extra_sources).current
	var base_bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, extra_sources).current
	var muzzle: Vector3 = UnitGeometry.shouldered_muzzle_point(actual, weapon)
	var hit_count: int = maxi(1, weapon.burst)

	for i in range(1, hit_count + 1):
		ShotResolution.resolve_and_log_point(
			state,
			actual,
			origin,
			direction,
			aim_point,
			damage,
			crit_chance,
			base_bonus_pen * float(i),
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
			"GrindAction: unit %d held %s (%d hits) on %s"
			% [actual.id, weapon_id, hit_count, target_cell]
		)
	)


func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for candidate: Unit in state.units:
		if candidate.alive and candidate.cell == cell:
			return candidate
	return null


func describe() -> String:
	return "GrindAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]


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
