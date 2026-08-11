class_name MissionState
extends RefCounted

## docs/07: insert -> explore/fight -> gather resources or hit objective ->
## EXIT. Exit is either extract() (bank everything gathered) or
## terminate() (the mission's own haul is lost — matrices are never lost
## on any path, so every one of them still comes home).

## The authored victory modes. Open vocabulary — a new mode is a new value here and a new branch
## in `BoutRunner`, never a new enum.
const VICTORY_EXTRACTION := &"extraction"
const VICTORY_CONTEST := &"contest"

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
## taskblock-21 Pass D: "team-coded extraction cells — blue extracts at
## blue's cells, red at red's." squad_id -> Array[Vector2i], a NEW, purely
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

## **How this bout is allowed to end.** tb64 Pass E. An open `StringName`, not an enum, because
## it is harness configuration rather than an engine state — a later mode is a new value and no
## code edit (CLAUDE.md).
##
## - `&"extraction"` (the default, and every campaign mission) — unchanged: a mission ends when
##   the player extracts, terminates, or is stranded. `docs/00`'s pillar.
## - `&"contest"` — **a team that can no longer contest has lost**, and the bout ends
##   `DEBUG_ENDED`. Not "deathmatch": the name overstates it.
##
## **The mode is the instrument.** Under `contest`, `BR63.04`'s all-chaingun roster would have
## ended immediately as a loss rather than running 31 silent turns to the turn cap, because a
## unit that can be offered no shot is not contesting. Every AI measurement before this ran in a
## mode where *leaving* wins, which is why 31 turns of silence read as a slow bout.
var victory_mode: StringName = VICTORY_EXTRACTION

## Which squad won, when `outcome` is `DEBUG_ENDED` and exactly one team could still contest.
## `-1` when nobody did (every team out at once — a real tie, not an error).
var debug_winner_squad_id: int = -1
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


## taskblock-22 Pass A1: "the ENTIRE squad must be off the board before
## EXTRACTED fires." A squad is ready once every one of its own units is
## no longer an active participant (`alive == false`) AND at least one of
## them actually got there via `extracted == true` — the second half is
## what tells a clean extraction apart from a total wipe (every unit dead,
## none extracted), which is `is_stranded()`'s own, separate, involuntary
## ending. A unit that died along the way is a real casualty, not a block:
## it simply can't ALSO be the reason this returns false, since dead units
## are already excluded from "still active."
func squad_ready_to_extract(squad_id: int) -> bool:
	var any_extracted := false
	for unit: Unit in combat_state.units:
		if unit.squad_id != squad_id:
			continue
		if unit.alive and not unit.extracted:
			return false
		if unit.extracted:
			any_extracted = true
	return any_extracted


## taskblock-22 Pass A: one unit actually leaving the board via either
## extraction path (`ExtractAction`'s own fast, AP-costed action for a
## non-player squad; `EndTurnAction`'s own hold-check for the player
## squad) — shared so neither path re-derives "how a unit leaves" on its
## own. Marks the unit itself (never touches the mission's own haul or
## roster on its own — that's still a whole-mission event, `extract()`
## below) and only calls `extract()` once `squad_ready_to_extract` agrees
## the unit's own squad is the player's AND every one of its own squadmates
## is accounted for.
func extract_unit(unit: Unit) -> void:
	unit.extracted = true
	# tb64 Pass G (`BR63.03`): **through `kill_unit`, not by hand.** This set `alive = false` and
	# cleared the cell itself — the same two lines `CombatState.kill_unit` runs under a comment
	# calling itself *"the one place a unit's alive flag flips to false"*. What it did not copy is
	# the third thing that function does: **advance the turn when the unit leaving is the current
	# one.** So an extracted unit stayed `_current_unit_id`, and the turn never ended.
	#
	# That is `BR51.04`/`BR51.05` exactly, reintroduced through a second door — the bug those
	# entries fixed was a stranded `_current_unit_id` pointing at someone who was gone, and
	# `SelectionController.select` requires `unit == current_unit()`, so it also takes selection
	# down with it. Extraction is not death, but at the level of board state it is the identical
	# event: off the board, out of the order, cell freed.
	combat_state.kill_unit(unit)
	combat_state.combat_log.emit(
		LogEvent.new(
			combat_state.round_number,
			Enums.Phase.RESOLUTION,
			unit.id,
			&"extract",
			{},
			"unit %d extracted" % unit.id
		)
	)
	if unit.squad_id == player_squad_id and squad_ready_to_extract(player_squad_id):
		extract()


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


## **Can this squad still bring fire on anything?** tb64 Pass E — the three terminating
## conditions the block names, and they collapse to one predicate rather than three checks:
##
## - **no living units** — every unit `alive == false`;
## - **no units on the board** (the whole team fled or extracted) — `extract_unit` sets
##   `alive = false`, so an extracted unit is already excluded by the same test;
## - **no unit with a usable weapon** — `UtilityContext.can_contest`, which asks whether the
##   unit's own tier has an action its weapon can execute, not merely whether a weapon works.
##
## **The third is the diagnostic**, and it is the one a "has a functional weapon" test would
## miss: a `GRUNT` holding a chaingun had a perfectly working gun and nothing to select with it.
func team_can_contest(squad_id: int) -> bool:
	for unit: Unit in combat_state.units:
		if unit.squad_id == squad_id:
			if UtilityContext.can_contest(unit):
				return true
	return false


## Every squad_id with at least one unit on this board, in ascending order.
func squad_ids() -> Array[int]:
	var ids: Array[int] = []
	for unit: Unit in combat_state.units:
		if not ids.has(unit.squad_id):
			ids.append(unit.squad_id)
	ids.sort()
	return ids


## Ends a `contest`-mode bout. `winner` is the one squad still able to contest, or `-1` for none.
##
## **Discards and returns exactly as the other endings do**, so a harness bout leaves the run
## state in the same shape a real mission would — a mode that ended differently *and* cleaned up
## differently would be two behaviours to keep in step.
func debug_end(winner: int) -> void:
	debug_winner_squad_id = winner
	combat_state.combat_log.emit(
		LogEvent.new(
			combat_state.round_number,
			Enums.Phase.RESOLUTION,
			-1,
			&"debug_end",
			{"mode": victory_mode, "winner_squad_id": winner},
			(
				"bout ended (contest): squad %d is the only team that can still contest" % winner
				if winner >= 0
				else "bout ended (contest): no team can still contest"
			)
		)
	)
	_discard_and_return(Enums.MissionOutcome.DEBUG_ENDED)


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
