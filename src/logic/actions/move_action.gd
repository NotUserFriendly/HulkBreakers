class_name MoveAction
extends CombatAction

## A full path (inclusive of the unit's current cell). Movement spends MP per
## tile; when MP runs short the unit burns 1 AP for +mp_per_ap MP, repeating
## while AP remains (Appendix E). Fails (is_legal == false) if AP runs out
## before the path completes.

var unit: Unit
var path: Array[Vector2i]


func _init(p_unit: Unit, p_path: Array[Vector2i]) -> void:
	unit = p_unit
	path = p_path


## Actions never trust a bare Unit reference across states (docs/09): a
## preview's units are independent clones sharing `unit.id`, not the same
## object, so every read/write below goes through the unit `state` itself
## actually holds.
func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive:
		return false
	if state.current_unit() != actual:
		return false
	if path.size() < 2 or path[0] != actual.cell:
		return false

	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var sim_ap: int = actual.ap
	var sim_mp: float = actual.mp
	var per_ap: float = actual.mp_per_ap()

	for i in range(1, path.size()):
		if Grid.distance_chebyshev(path[i - 1], path[i]) != 1:
			return false
		var step_cost: float = pf.move_cost(path[i])
		if step_cost < 0.0:
			return false
		while sim_mp < step_cost:
			if sim_ap <= 0:
				return false
			sim_ap -= 1
			sim_mp += per_ap
		sim_mp -= step_cost

	return true


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var pf := Pathfinder.new(state.grid, state.terrain_costs)
	var per_ap: float = actual.mp_per_ap()

	for i in range(1, path.size()):
		var step_cost: float = pf.move_cost(path[i])
		while actual.mp < step_cost:
			actual.ap -= 1
			actual.mp += per_ap
		actual.mp -= step_cost
		state.grid.set_occupant_id(actual.cell, -1)
		actual.cell = path[i]
		state.grid.set_occupant_id(actual.cell, actual.id)

	# runNotes.md: "a character's facing after movement should update to
	# face away from where they started" — free, same primitive
	# AttackAction's own free-with-action facing uses, so a queued move
	# updates the previewed wedge exactly like every other facing change.
	# Known consequence, confirmed by direct A/B testing, not yet resolved
	# (flagged rather than hacked around, CLAUDE.md's own rule): a unit
	# that stops moving because it's already in weapon range now keeps
	# whatever orientation its last step left it with, rather than a
	# constant default — for at least one scripted integration scenario
	# (test_full_mission.gd) this happens to freeze the last defender
	# facing its best armor at the attackers, stalemating the mission past
	# its turn cap. The mission AI has no facing awareness at all (it never
	# queues a FaceAction); making combat AI account for its own defensive
	# facing is a real follow-up, not something to invent unasked here.
	FaceAction.face_for_free(
		state,
		actual,
		FaceAction.orientation_toward(path[0], path[path.size() - 1]),
		&"free_with_move"
	)

	var text: String = "MoveAction: unit %d moved to %s" % [actual.id, actual.cell]
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"move",
				{"path": path, "destination": actual.cell},
				text
			)
		)


func describe() -> String:
	return "MoveAction(unit=%d, path=%s)" % [unit.id, path]
