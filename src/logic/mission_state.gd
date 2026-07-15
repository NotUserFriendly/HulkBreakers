class_name MissionState
extends RefCounted

## docs/07: insert -> explore/fight -> gather resources or hit objective ->
## EXIT. Exit is either extract() (bank everything gathered) or
## terminate() (the mission's own haul is lost — matrices are never lost
## on any path, so every one of them still comes home).

var run_state: RunState
var combat_state: CombatState
var objectives: Array[StringName] = []  # open ids, e.g. &"gather_minerals"
var completed_objectives: Array[StringName] = []
var gathered_resources: Dictionary = {}  # this mission's own haul, not yet banked
var gathered_items: Array[Part] = []
## Vector2i -> {resource: StringName, amount: int, objective: StringName}.
## What GatherAction actually consumes (docs/07: "gather resources ... on
## the map") — `objective`, if non-empty, is completed the instant this
## node is gathered. Mission-scoped, not CombatState's — a TACTICS preview
## must never touch it (see GatherAction.apply).
var resource_nodes: Dictionary = {}
## Cells ExtractAction requires a unit stand on to call the mission (docs/07:
## "EXTRACT with loot").
var extraction_cells: Array[Vector2i] = []


func _init(p_run_state: RunState, p_combat_state: CombatState) -> void:
	run_state = p_run_state
	combat_state = p_combat_state


func complete_objective(id: StringName) -> void:
	if id in objectives and id not in completed_objectives:
		completed_objectives.append(id)


func gather_resource(id: StringName, amount: int) -> void:
	gathered_resources[id] = gathered_resources.get(id, 0) + amount


## Banks this mission's whole haul into the persistent run and returns
## every matrix to the roster. "Clean" (docs/04): nothing was lost, and
## nothing here needed to be.
func extract() -> void:
	for id: StringName in gathered_resources:
		run_state.add_resource(id, gathered_resources[id])
	run_state.stash.append_array(gathered_items)
	_return_every_matrix()
	gathered_resources.clear()
	gathered_items.clear()


## The mission's own haul is discarded, not banked — "you lose the bodies
## and the loot, keep the matrices, and save the time" (docs/00). Every
## matrix still comes home regardless.
func terminate() -> void:
	gathered_resources.clear()
	gathered_items.clear()
	_return_every_matrix()


func _return_every_matrix() -> void:
	for matrix: Matrix in _all_matrices():
		# The roster holds base identities (docs/04: "the Base Matrix stays
		# on the ship") — a link is just the field vessel it was written
		# into, and doesn't persist as its own roster entry.
		var base: Matrix = matrix.base if matrix.base != null else matrix
		if not run_state.roster.has(base):
			run_state.roster.append(base)


## Every matrix this mission ever had, piloting or merely carried —
## Unit.matrix is never cleared on ejection (docs/01/04), so it stays the
## authoritative reference to "whichever matrix this unit brought," body
## or no body.
func _all_matrices() -> Array[Matrix]:
	var matrices: Array[Matrix] = []
	for unit: Unit in combat_state.units:
		if unit.matrix != null and not matrices.has(unit.matrix):
			matrices.append(unit.matrix)
		if unit.held_matrix != null and not matrices.has(unit.held_matrix):
			matrices.append(unit.held_matrix)
	return matrices
