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
## taskblock-21 Pass D: "team-coded extraction tiles — blue extracts at
## blue's tiles, red at red's." squad_id -> Array[Vector2i], a NEW, purely
## additive field — `extraction_cells` above stays exactly what it always
## was (the single-player, squad-0-only mission path; nothing here changes
## its own meaning). Empty ({}) for every mission that isn't a two-team
## bout; `BoutSetup.build_bout` is the one thing that populates it, for
## BOTH squads at once. `ExtractAction.is_legal` reads this first, falling
## back to `extraction_cells` only when a unit's own squad has no entry
## here at all.
var team_extraction_cells: Dictionary = {}  # int squad_id -> Array[Vector2i]
## docs/00 taskblock02 Pass E: how this mission actually ended. Never set
## by "the enemy squad is dead" — that was never an ending. UNDECIDED
## (still in progress) until extract()/terminate()/strand() sets it.
var outcome: Enums.MissionOutcome = Enums.MissionOutcome.UNDECIDED
## Which squad_id is the player's — `is_stranded()`'s own definition of
## "no player matrix can act." Convention throughout the codebase (deep
## strike, BattleScene) is squad 0; a flagged default, not hardcoded logic.
var player_squad_id: int = 0


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
	outcome = Enums.MissionOutcome.EXTRACTED


## The mission's own haul is discarded, not banked — "you lose the bodies
## and the loot, keep the matrices, and save the time" (docs/00). Every
## matrix still comes home regardless. The player's own choice — never
## the "lose" button (docs/07).
func terminate() -> void:
	_discard_and_return(Enums.MissionOutcome.TERMINATED)


## docs/00 taskblock02 Pass E: no player matrix can act. Involuntary, and
## explicitly **not** a loss — matrices persist exactly as they do on
## every other path, only the label differs (`docs/00`: "the roguelike
## rule is absolute"). Mechanically identical to terminate() (the mission's
## own haul is lost either way); the distinct outcome is what a run-summary
## screen would actually show the player.
func strand() -> void:
	_discard_and_return(Enums.MissionOutcome.STRANDED)


func _discard_and_return(ending: Enums.MissionOutcome) -> void:
	gathered_resources.clear()
	gathered_items.clear()
	_return_every_matrix()
	outcome = ending


## True once no living unit on the player's own squad remains — the one
## real, involuntary ending (docs/00), never "the enemy squad is down"
## (that was deleted, not renamed: docs/09-era CombatState.is_over() no
## longer exists at all).
func is_stranded() -> bool:
	for unit: Unit in combat_state.units:
		if unit.squad_id == player_squad_id and unit.alive:
			return false
	return true


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
