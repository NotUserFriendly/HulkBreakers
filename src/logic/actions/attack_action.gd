class_name AttackAction
extends CombatAction

## Aim point -> dartboard -> shot plane -> impact (docs/02/03, Phase 6).
## `unit` and `weapon_id` are resolved fresh from whatever `state` is passed
## (docs/09): a preview's shell is an independent clone, so a bare Part
## reference captured at construction would never match it (see
## Shell.find_part). Aims at the target unit's own frontmost region by
## default — center mass — offset by `aim_offset` if given; never picks a
## body part directly (docs/02: the dartboard picks a point, not a part).

var unit: Unit
var weapon_id: StringName
var target_cell: Vector2i
var aim_offset: Vector2
## Perk/ammo/stance modifiers on top of the weapon's own part-level mods
## (docs/08) — empty until those systems exist, but resolved through the same
## WeaponResolver call a tooltip would use, never a separate code path.
var extra_sources: Array[ModSource]
## docs/10 taskblock04 C3: "this is where docs/07's harvest loop finally
## touches the board" — null for a standalone battle with no mission
## context (BattleScene, most tests); when set, a destroyed field object's
## own `salvage_yield` is credited to it the same way GatherAction credits
## a resource node. Optional and last, like GatherAction's own `mission`
## but not required here — attacking happens with or without a mission.
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
	if weapon == null or weapon.hp <= 0:
		return false
	if actual.ap < weapon.ap_cost:
		return false
	if Suppression.blocks_weapon(state, actual, weapon):
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
	for part: Part in actual.shell.living_parts():
		if part != weapon:
			manipulators.append(part)
	return PartGraph.can_operate(weapon, manipulators)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var weapon: Part = actual.shell.find_part(weapon_id)
	actual.ap -= weapon.ap_cost

	# docs/10 taskblock02 F3: firing faces the shooter toward the target
	# for free, inside apply() same as AP spend — never a separate charge,
	# and never skipped just because this is a preview (a queued shot's
	# preview should show the shooter's final rotation too).
	if actual.cell != target_cell:
		FaceAction.face_for_free(
			state, actual, FaceAction.orientation_toward(actual.cell, target_cell)
		)

	if state.is_preview:
		# The one thing a preview must never resolve (docs/09): whether this
		# round actually hits and kills is exactly what RESOLUTION alone
		# gets to decide. AP is spent so a later queued move/attack still
		# previews correctly; the target is left exactly as it was.
		return

	var target: Unit = _unit_at(state, target_cell)
	var origin := Vector2(actual.cell.x, actual.cell.y)
	var direction := Vector2(target_cell - actual.cell)
	var plane: Array[Region] = ShotPlane.build(origin, direction.normalized(), state)
	var range_cells: int = Grid.distance_chebyshev(actual.cell, target_cell)

	var aim_point: Vector2 = ShotPlane.center_of(plane, target) + aim_offset
	var resolved_scatter: Array[Ring] = Dartboard.resolve_scatter(
		weapon, extra_sources, RangeModel.dartboard_radius_scale(weapon, range_cells)
	)
	var points: Array[Vector2] = Dartboard.sample(
		aim_point, resolved_scatter, state.rng, weapon.burst
	)

	# docs/08: the damage/crit/bonus_pen numbers used here must be the
	# exact same ones a tooltip built from WeaponResolver would show —
	# never a raw Part field read directly.
	var damage: float = WeaponResolver.resolve_damage(weapon, extra_sources).current
	var crit_chance: float = WeaponResolver.resolve_crit_chance(weapon, extra_sources).current
	var bonus_pen: float = WeaponResolver.resolve_bonus_pen(weapon, extra_sources).current
	# taskblock-19 Pass C2: fired anyway (is_legal() only lets a dud-
	# capable weapon reach here at all under min range) — same kinetic
	# cascade, just tagged so the log (and a future payload system) knows
	# nothing special armed.
	var is_dud: bool = RangeModel.is_dud(weapon, range_cells)

	for point: Vector2 in points:
		# The shooter's own body sits at the ray's own origin (depth <= 0)
		# and can otherwise satisfy `_find_next`'s point-containment check
		# just like the target can when the two happen to share a lateral
		# position — excluded on this first lookup only, the same mechanism
		# a ricochet uses to skip the body it just bounced off, so a shot
		# fired at a collinear target never reaches back into the shooter's
		# own chest.
		ShotResolution.resolve_and_log_point(
			state, actual, origin, direction, point, damage, crit_chance, bonus_pen, mission, is_dud
		)

	# Phase 6 placeholder: no living parts left disables the unit. Phase 7
	# (docs/04) replaces this with the real rule — destroying the specific
	# part hosting the Matrix ejects it — which fires strictly earlier than
	# "every part destroyed," so it supersedes rather than conflicts with
	# this conservative stand-in.
	if target.alive and target.shell.living_parts().is_empty():
		state.kill_unit(target)

	state.log_action(
		(
			"AttackAction: unit %d fired %s (burst %d) at %s"
			% [actual.id, weapon_id, weapon.burst, target_cell]
		)
	)


func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for candidate: Unit in state.units:
		if candidate.alive and candidate.cell == cell:
			return candidate
	return null


func describe() -> String:
	return "AttackAction(unit=%d, weapon=%s, target=%s)" % [unit.id, weapon_id, target_cell]


## docs/09 taskblock06 Pass E: reads the WEAPON's own speed, not a fixed
## per-action-type constant — "a fast weapon can out-speed an overwatch
## trigger," which only works if the number lives on the weapon Part
## itself. Falls back to the action's own neutral 0.0 (never a name
## match/hardcoded ladder) if the actual unit or weapon can't be found —
## the same "never crash, never silently invent" posture is_legal() uses.
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
