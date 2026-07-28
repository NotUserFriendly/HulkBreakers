class_name UtilityContext
extends RefCounted

## **The seam that publishes what a candidate is worth knowing about.** `docs/11`
## has the model; this is the only file in the planner that knows what a grid, a
## weapon or a line of fire is.
##
## `UtilityScorer.score` consumes a flat `{input_id: 0.0–1.0}` dictionary and
## `preconditions_hold` a flat `{predicate: bool}` one. Nothing in the scorer knows
## where either comes from, which is what makes a new consideration an entry
## published here plus a `.tres`, never a branch in the scorer.
##
## ## Cheap answers here, canonical answers at the executor
##
## Line of fire is a bit test against one `VisibilityField` per target per turn.
## The field over-includes by design (`docs/11`), so a shoot candidate it waves
## through may still be blocked — and is caught by `ActionQueue.enqueue`, which
## validates against a preview with the queued move already replayed onto it. The
## planner proposes from a cheap answer and the executor refuses from the canonical
## one; that is the one-resolver rule working, not being worked around.
##
## The same posture covers `_move_economy`, which ranks candidates on chebyshev
## distance rather than real path cost. A true cost needs a pathfind per candidate,
## which is the class of work this design exists to remove, and the proxy only ever
## orders candidates against each other — never decides whether a move is
## affordable.
##
## **Normalisation constants below are flagged, not tuned.** They turn unbounded
## game quantities into 0–1 and put ordinary map distances somewhere useful in the
## range; behaviour is authored in the profile weights.

# --- the published vocabulary ------------------------------------------------
#
# Open `StringName`s (CLAUDE.md). A `.tres` naming one that is not published here
# reads as 0.0 and therefore VETOES, which is deliberately loud — see
# `ConsiderationDef.input_id`.

## 1.0 when a shot from this cell to the target could possibly be clear.
const INPUT_LINE_OF_FIRE := &"line_of_fire"
## 1.0 when the weapon's own range model accepts the distance from this cell.
const INPUT_IN_WEAPON_RANGE := &"in_weapon_range"
## 1.0 exactly at the preferred standoff, falling off in both directions — so one
## input drives advancing when too far and retreating when too close.
const INPUT_STANDOFF_MATCH := &"standoff_match"
## 1.0 when something is interposed between this cell and the target.
const INPUT_COVER := &"cover"
## 0.5 for no change, 1.0 for standing on the target, 0.0 for retreating far.
const INPUT_CLOSES_DISTANCE := &"closes_distance"
## 1.0 for staying put, falling as the move gets longer.
const INPUT_MOVE_ECONOMY := &"move_economy"
## Shell condition, 1.0 undamaged. Inverted by a curve to mean "how hurt am I".
const INPUT_OWN_INTEGRITY := &"own_integrity"

## One further input per authored batch objective, named `objective_<id>`
## (`BatchObjective.input_id_for`). **Not constants here, because the objective
## vocabulary is the `.tres` set** — a fifth objective publishes a fifth input with
## no code edit.
##
## **Dormant publishes 1.0 for every one of them.** A neutral vector, not a zero
## vector: zeroes would veto through the product and every batchless unit — which
## is every unit until a batch is assigned by hand — would stop acting entirely.
## That is what makes the dormancy claim literal rather than approximate.

## Some attached weapon can actually fire right now.
const PRED_HAS_WEAPON := &"has_weapon"
## This unit knows of a living enemy at all — which a `MINDLESS` unit stops doing
## the moment line of sight breaks (`WorldView.MEMORY_TIERS`).
const PRED_ENEMY_KNOWN := &"enemy_known"
## The candidate is somewhere other than where the unit already stands.
const PRED_CELL_IS_ELSEWHERE := &"cell_is_elsewhere"
## The candidate IS where the unit already stands.
const PRED_CELL_IS_CURRENT := &"cell_is_current"
const PRED_WEAPON_REACHES := &"weapon_reaches"
## The cheap, over-inclusive line-of-fire gate — false is conclusive.
const PRED_LOF_POSSIBLE := &"lof_possible"
## Its explicit inverse, published because **preconditions are an all-must-hold
## list with no negation** — an action that wants "only when I canNOT shoot from
## here" has no way to say so otherwise, and adding negation to the precondition
## grammar would be a much larger change than publishing one more boolean.
const PRED_LOF_BLOCKED := &"lof_blocked"
const PRED_CELL_IS_COVERED := &"cell_is_covered"
## Some other living unit exists to defer to, which is `HoldAction`'s own
## legality requirement. Published so a hold that could never be enqueued is never
## even offered, rather than winning and then silently failing.
const PRED_CAN_DEFER_TURN := &"can_defer_turn"

# --- the mission ------------------------------------------------------------
#
# **A combat-only action pool cannot finish a mission**, and measuring is what made
# that concrete: the planner completed 0% of bouts on its first head-to-head,
# because completion means EXTRACTED and nothing in a combat pool can gather an
# objective or walk to an extraction tile. A missing action, not a worse planner.
#
# The retired planner answered this with a non-combat branch above the combat ones.
# Here it is four `.tres` rows over the inputs below — the architecture's own claim
# ("preconditions and a consideration set, not new machinery") being cashed.
#
# **Precedence needs no branch.** Every combat action requires `enemy_known`, so
# with nothing in sight the mission actions are the only ones offered; with an
# enemy in sight both compete and the authored weights decide. A hard "combat
# first" ordering becomes a weight.
#
# **These gate on `is_player_squad`, and that is half of a known hole** — see
# `BR45.03`: a non-player squad with nothing in sight fails every gate in the pool
# and idles. `docs/11` names the failure mode.

## Some objective is still open.
const PRED_OBJECTIVE_OPEN := &"objective_open"
## Every objective is complete, so the job now is to leave.
const PRED_OBJECTIVE_DONE := &"objective_done"
## The candidate cell IS the resource node.
const PRED_CELL_IS_OBJECTIVE := &"cell_is_objective"
## This unit belongs to the squad the mission is scored for. The old planner
## returned early for every other squad and this reproduces that: an enemy bot has
## no business walking to the player's extraction zone.
const PRED_IS_PLAYER_SQUAD := &"is_player_squad"
## 0.5 for no change, 1.0 for standing on the resource node.
const INPUT_CLOSES_TO_OBJECTIVE := &"closes_to_objective"
## 0.5 for no change, 1.0 for standing on the extraction tile.
const INPUT_CLOSES_TO_EXTRACTION := &"closes_to_extraction"

# --- normalisation constants -------------------------------------------------

## How many cells of deviation from the preferred standoff drives
## `standoff_match` from 1.0 to 0.0. Flagged, not tuned.
const STANDOFF_FALLOFF_CELLS := 8.0
## The standoff a unit pulls toward when its weapon authors no `effective_range`.
## Flagged, not tuned — and deliberately non-zero, so an unarmed-in-practice unit
## still has a preference rather than a flat field.
const DEFAULT_STANDOFF_CELLS := 5.0

var unit: Unit
var view: WorldView
## The mission this turn belongs to, or null for a bare combat test. Null publishes
## every mission predicate false, so a context with no mission simply never offers
## a mission action — the same "absent reads as false" posture every other
## precondition has.
var mission: MissionState = null
## The enemy this turn is planned against, or null when none is known.
var target: Unit = null
var weapon: Part = null
var weapon_id: StringName = &""

## Built once per turn from the target's cell — the inversion taskblock-44 Pass B
## landed and this block finally spends.
var field: VisibilityField = null
## Every cell the unit could stand on this turn, already culled toward the fight.
var candidate_cells: Array[Vector2i] = []

## Where the unit will be standing when the action under consideration happens —
## `unit.cell` for the first selection of a turn, and the chosen destination for
## every follow-up. **The unit itself is never moved**: TACTICS mutates nothing
## (`docs/09`), so a settled origin is two numbers on this context and the real
## position change stays where it belongs, in RESOLUTION replaying the queue.
var _origin: Vector2i = Vector2i.ZERO

var _standoff: float = DEFAULT_STANDOFF_CELLS
var _integrity: float = 1.0
var _current_distance: int = 0
var _move_budget: float = 1.0
var _can_defer: bool = false
var _has_weapon: bool = false
## The batch objective in force, or `BatchPlan.NO_OBJECTIVE` for a unit that is
## independent, unled, or of a tier with no blackboard.
var _objective: StringName = BatchPlan.NO_OBJECTIVE
## Where the mission's work is. `null` when there is no mission, no open objective,
## or no extraction tile defined for this unit's squad.
var _objective_cell: Variant = null
var _extraction_cell: Variant = null


## Gathers everything that is per-TURN rather than per-candidate, so the
## per-candidate work stays arithmetic and bit tests.
##
## **`units_visible_to` is the only unit knowledge read**, here and nowhere else in
## the planner — the chokepoint `test_world_view_seam.gd` keeps singular.
static func build(
	p_unit: Unit, p_view: WorldView, p_mission: MissionState = null
) -> UtilityContext:
	var context := UtilityContext.new()
	context.unit = p_unit
	context.view = p_view
	context.mission = p_mission
	context._objective_cell = context._resource_node_cell()
	context._extraction_cell = context._own_extraction_cell()
	var state: CombatState = p_view.canonical_state_for_resolvers()

	context._origin = p_unit.cell
	context._has_weapon = _has_functional_weapon(p_unit)
	context.weapon_id = _find_weapon_id(p_unit)
	context.weapon = (
		p_unit.shell.find_part(context.weapon_id) if context.weapon_id != &"" else null
	)
	context._integrity = _integrity_of(p_unit)
	context.target = context._nearest_known_enemy()
	context._can_defer = context._some_other_living_unit()

	context._move_budget = maxf(1.0, p_unit.mp_per_ap() * float(p_unit.ap))

	# taskblock-45 Pass D: candidate cells are computed whether or not an enemy is
	# known. **They used to be `[unit.cell]` with no target**, which quietly made it
	# impossible for a unit with nothing in sight to move anywhere at all — so it
	# could never walk to a resource node or an extraction tile, and the mission
	# actions the head-to-head added would have been offered a candidate set of
	# exactly one cell and never fired. A planner that can only move toward things
	# it can see cannot finish a mission.
	var needs_cells: bool = (
		context.target != null
		or context._objective_cell != null
		or context._extraction_cell != null
	)
	if not needs_cells:
		context.candidate_cells = [p_unit.cell]
		return context

	var pathfinder := Pathfinder.new(p_view.grid, p_unit.shell.can_climb())
	var reachable: Array[Vector2i] = pathfinder.reachable(p_unit.cell, context._move_budget)
	if not reachable.has(p_unit.cell):
		reachable.append(p_unit.cell)

	if context.target == null:
		# No enemy, so no rectangle to cull toward — the whole reachable set is the
		# candidate set. It is also the cheap case: no `VisibilityField`, no cover
		# walks, nothing but distance arithmetic per cell.
		context.candidate_cells = reachable
		return context

	context._standoff = standoff_for(context.weapon)
	context._current_distance = Grid.distance_chebyshev(p_unit.cell, context.target.cell)
	context.field = VisibilityField.build(state, context.target.cell)
	# taskblock-43 Pass B's rectangle carries forward: it is candidate-set geometry
	# with no planner state in it, so nothing about replacing the scorer invalidates
	# it.
	context.candidate_cells = EngagementRect.cull(
		p_unit, context.target, context._standoff, reachable
	)
	# **But the rectangle is drawn toward the ENEMY, and a unit has somewhere else
	# to be.** Culled alone, a unit that can see an enemy could not consider a
	# single cell toward its resource node or its extraction tile, because those sit
	# outside a box spanned by the unit and its target. It could fight or it could
	# travel, never both — so a bout where the two squads could see each other ran
	# to the turn cap with the objective untouched. Adding back only the cells that
	# genuinely make progress keeps the set small: at most one more per destination
	# per direction, not the whole reachable blob.
	context._add_mission_progress_cells(reachable)
	return context


## Where the unit is standing for scoring purposes — its own cell, or the
## destination it has already committed to this turn.
func origin() -> Vector2i:
	return _origin


## taskblock-45 Pass C: puts the batch's coarse call in force for the rest of this
## turn's scoring. A no-op vector when `objective` is empty, which is the dormant
## case and therefore the overwhelmingly common one.
func set_batch_objective(objective: StringName) -> void:
	_objective = objective


## Appends the reachable cells that close on a mission destination, so travelling
## stays available while an enemy is in sight. A no-op when there is no mission.
func _add_mission_progress_cells(reachable: Array[Vector2i]) -> void:
	for destination: Variant in [_objective_cell, _extraction_cell]:
		if destination == null:
			continue
		var to: Vector2i = destination
		var best: Variant = null
		var best_distance: int = Grid.distance_chebyshev(_origin, to)
		for cell: Vector2i in reachable:
			var distance: int = Grid.distance_chebyshev(cell, to)
			if distance < best_distance:
				best_distance = distance
				best = cell
		if best != null and not candidate_cells.has(best):
			candidate_cells.append(best)


## Re-bases the context on `cell`, for scoring what the unit does AFTER a move it
## has already committed to this turn — `docs/11`'s depth-1 "score post-move".
##
## It is why the planner can shoot after repositioning with no hardcoded "and then
## fire" branch: the same scorer is asked the same question from the new position.
## **Only geometry is re-based.** AP and legality are never simulated here;
## `ActionQueue.enqueue` owns those and is the only thing that can answer them
## against the queued move.
func settle_at(cell: Vector2i) -> void:
	_origin = cell
	candidate_cells = [cell]
	if target != null:
		_current_distance = Grid.distance_chebyshev(cell, target.cell)


## The 0–1 facts about standing at `cell`. One dictionary per candidate, scored
## against every action in the pool — which is what makes considerations *shared*
## rather than duplicated per action.
func inputs_for(cell: Vector2i) -> Dictionary:
	if target == null:
		var idle: Dictionary = {
			INPUT_OWN_INTEGRITY: _integrity,
			INPUT_MOVE_ECONOMY: _move_economy(cell),
		}
		idle.merge(_objective_inputs())
		idle.merge(_mission_inputs(cell))
		return idle
	var distance: int = Grid.distance_chebyshev(cell, target.cell)
	var inputs: Dictionary = {
		INPUT_LINE_OF_FIRE: 1.0 if _lof_possible(cell) else 0.0,
		INPUT_IN_WEAPON_RANGE: 1.0 if _weapon_reaches(distance) else 0.0,
		INPUT_STANDOFF_MATCH: _standoff_match(distance),
		INPUT_COVER: 1.0 if _is_covered(cell) else 0.0,
		INPUT_CLOSES_DISTANCE: _closes_distance(distance),
		INPUT_MOVE_ECONOMY: _move_economy(cell),
		INPUT_OWN_INTEGRITY: _integrity,
	}
	inputs.merge(_objective_inputs())
	inputs.merge(_mission_inputs(cell))
	return inputs


## How much standing at `cell` advances the mission's two destinations. Both are
## the same "0.5 means no change" shape as `closes_distance`, for the same reason:
## an input pinned to 0.0 would veto through the product, and "did not improve" is
## not a veto.
func _mission_inputs(cell: Vector2i) -> Dictionary:
	return {
		INPUT_CLOSES_TO_OBJECTIVE: _closes_to(cell, _objective_cell),
		INPUT_CLOSES_TO_EXTRACTION: _closes_to(cell, _extraction_cell),
	}


func _closes_to(cell: Vector2i, destination: Variant) -> float:
	if destination == null:
		return 0.0
	var to: Vector2i = destination
	var now: int = Grid.distance_chebyshev(cell, to)
	var was: int = Grid.distance_chebyshev(_origin, to)
	# **Already standing on it: staying is perfect, leaving is worthless.**
	#
	# This returned a flat 1.0 for every candidate when `was == 0`, which read as
	# "every cell on the board is a perfect approach" the moment a unit arrived. The
	# unit walked off its own extraction tile, walked back the next turn, and did it
	# again — two units alternating onto one tile for the whole turn cap, neither
	# ever standing still long enough for `EndTurnAction`'s hold to mature into an
	# extraction. Found by dumping the per-turn queue rather than by reading the
	# arithmetic, which had looked obviously right twice.
	if was <= 0:
		return 1.0 if now == 0 else 0.0
	return clampf(0.5 + 0.5 * float(was - now) / float(was), 0.0, 1.0)


## 1.0 for the objective in force and for EVERY objective when none is, 0.0 for the
## rest. See the note beside `INPUT_OWN_INTEGRITY` for why dormant is all-ones.
func _objective_inputs() -> Dictionary:
	var dormant: bool = _objective == BatchPlan.NO_OBJECTIVE
	var published: Dictionary = {}
	for objective: UtilityActionDef in DataLibrary.batch_objectives_pool():
		published[BatchObjective.input_id_for(objective.id)] = (
			1.0 if dormant or objective.id == _objective else 0.0
		)
	return published


## The booleans that decide whether an action is OFFERED at `cell` at all.
##
## Separate from the inputs above because "impossible" and "possible but
## unappealing" are different answers to "why didn't it do that", and the decision
## log has to keep them apart (`UtilityActionDef`).
func predicates_for(cell: Vector2i) -> Dictionary:
	var distance: int = Grid.distance_chebyshev(cell, target.cell) if target != null else 0
	return {
		PRED_HAS_WEAPON: _has_weapon,
		PRED_ENEMY_KNOWN: target != null,
		PRED_CELL_IS_ELSEWHERE: cell != _origin,
		PRED_CELL_IS_CURRENT: cell == _origin,
		PRED_WEAPON_REACHES: target != null and _weapon_reaches(distance),
		PRED_LOF_POSSIBLE: target != null and _lof_possible(cell),
		PRED_LOF_BLOCKED: target != null and not _lof_possible(cell),
		PRED_CELL_IS_COVERED: target != null and _is_covered(cell),
		PRED_CAN_DEFER_TURN: _can_defer,
		PRED_OBJECTIVE_OPEN: _objective_cell != null,
		PRED_OBJECTIVE_DONE: mission != null and not _has_open_objective(),
		PRED_CELL_IS_OBJECTIVE: _objective_cell != null and cell == _objective_cell,
		PRED_IS_PLAYER_SQUAD: mission != null and unit.squad_id == mission.player_squad_id,
	}


## The ids of every unit this context's observer is entitled to know about —
## recorded per decision, because a decision that looks wrong is often correct
## given a degraded world model and there is otherwise no way to tell that apart
## from a scoring bug.
func visible_unit_ids() -> Array:
	var ids: Array = []
	for other: Unit in view.units_visible_to(unit):
		if other != unit and other.alive:
			ids.append(other.id)
	return ids


# --- per-candidate facts -----------------------------------------------------


## **A bit test, not a cast.** `false` is conclusive; `true` is confirmed later by
## `ActionQueue.enqueue` against the real resolver.
func _lof_possible(cell: Vector2i) -> bool:
	return field == null or field.allows(cell)


func _weapon_reaches(distance: int) -> bool:
	if weapon == null:
		return false
	return (
		RangeModel.is_in_max_range(weapon, distance)
		and not RangeModel.blocks_min_range(weapon, distance)
	)


## Peaks at the preferred standoff and falls away in BOTH directions, so advancing
## when too far and retreating when too close are the same preference read from
## opposite sides rather than two behaviours.
func _standoff_match(distance: int) -> float:
	var deviation: float = absf(float(distance) - _standoff)
	return clampf(1.0 - deviation / STANDOFF_FALLOFF_CELLS, 0.0, 1.0)


## 0.5 means "no closer than I already am", which keeps a neutral candidate at the
## middle of the range rather than at an end — an input pinned to 0.0 would veto
## through the product, and "did not improve" is not a veto.
func _closes_distance(distance: int) -> float:
	if _current_distance <= 0:
		return 0.5
	var gained: float = float(_current_distance - distance) / float(_current_distance)
	return clampf(0.5 + 0.5 * gained, 0.0, 1.0)


## Chebyshev distance against the turn's movement budget — a deliberate PROXY for
## real path cost. The true cost needs a pathfind per candidate, which is the class
## of per-candidate work this block exists to remove; the proxy only ever ranks
## candidates against each other and is never shown to a player or used to decide
## whether a move is affordable (`ActionQueue.enqueue` owns that).
func _move_economy(cell: Vector2i) -> float:
	var steps: float = float(Grid.distance_chebyshev(_origin, cell))
	return clampf(1.0 - steps / _move_budget, 0.0, 1.0)


func _is_covered(cell: Vector2i) -> bool:
	return Cover.is_covered_from(cell, target.cell, view, unit)


# --- per-turn facts ----------------------------------------------------------


## The nearest living enemy this unit is entitled to know about. **The tier gate
## does its work here**: for a `MINDLESS` observer `units_visible_to` returns only
## what is currently in sight, so an enemy that has broken line of sight simply
## stops existing and the unit plans an empty board.
func _nearest_known_enemy() -> Unit:
	var best: Unit = null
	var best_distance: int = 0
	for candidate: Unit in view.units_visible_to(unit):
		if candidate.squad_id == unit.squad_id or not candidate.alive:
			continue
		var distance: int = Grid.distance_chebyshev(unit.cell, candidate.cell)
		# Strict `<` with a lowest-id-wins fallback: ties on distance are common on
		# open ground and iteration order must not be what decides them
		# (`UtilityScorer`'s own tiebreak rule, applied to target choice).
		if best == null or distance < best_distance:
			best = candidate
			best_distance = distance
		elif distance == best_distance and candidate.id < best.id:
			best = candidate
	return best


func _some_other_living_unit() -> bool:
	for other: Unit in view.units_visible_to(unit):
		if other != unit and other.alive:
			return true
	return false


func _has_open_objective() -> bool:
	if mission == null:
		return false
	for objective: StringName in mission.objectives:
		if objective not in mission.completed_objectives:
			return true
	return false


## The resource node this mission still wants gathered, or null when there is no
## mission, nothing open, or no node authored. The old planner read
## `resource_nodes.keys()[0]` and this deliberately reads the same one — picking a
## different node would be a behaviour change smuggled in as a rewrite.
func _resource_node_cell() -> Variant:
	if not _has_open_objective() or mission.resource_nodes.is_empty():
		return null
	return mission.resource_nodes.keys()[0]


## This unit's own extraction tile. `team_extraction_cells` first, falling back to
## the squad-agnostic `extraction_cells` for the player's own squad ONLY — the same
## asymmetry the retired planner's flee branch documented, and for the same reason: an enemy squad
## with no team-coded entry has no defined extraction tile, and sending it to the
## player's landing point would never be correct.
func _own_extraction_cell() -> Variant:
	if mission == null:
		return null
	var cells: Array = mission.team_extraction_cells.get(unit.squad_id, [])
	if cells.is_empty() and unit.squad_id == mission.player_squad_id:
		cells = mission.extraction_cells
	if cells.is_empty():
		return null
	var best: Vector2i = cells[0]
	for cell: Vector2i in cells:
		if Grid.distance_chebyshev(unit.cell, cell) < Grid.distance_chebyshev(unit.cell, best):
			best = cell
	return best


## The weapon's own authored `effective_range` when present — a real, concrete
## number beats a flagged guess — else the flagged default.
##
## Public because `EngagementRect.cull` takes the same distance and must be given
## the identical answer: two places deciding what "the standoff" is would let the
## candidate set and the scorer disagree about which cells matter. It is the
## successor to the retired planner's own `_target_distance`, minus the
## per-playstyle preferred range that dissolved into the profile weights.
static func standoff_for(weapon: Part) -> float:
	if weapon != null and weapon.weapon_def != null and weapon.weapon_def.effective_range > 0.0:
		return weapon.weapon_def.effective_range
	return DEFAULT_STANDOFF_CELLS


## Total surviving hp across the shell as a fraction of its built maximum.
##
## A flagged proxy for "how hurt am I", not a health bar: `docs/04` makes condition
## a ladder of tiers rather than a scalar, and this deliberately does not pretend
## otherwise — it only has to rank a hurt unit below a fresh one consistently.
static func _integrity_of(unit: Unit) -> float:
	var current: float = 0.0
	var maximum: float = 0.0
	for part: Part in unit.shell.all_parts():
		current += maxf(0.0, float(part.hp))
		maximum += maxf(0.0, float(part.max_hp))
	return clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 1.0


## True only if some attached weapon can ACTUALLY fire right now — `WeaponRows`'
## own `active` computation (hp, wounds, and a real operable manipulator), never a
## re-derived "does a weapon-ish part merely exist" check.
static func _has_functional_weapon(unit: Unit) -> bool:
	for row: WeaponRow in WeaponRows.build(unit):
		if row.active:
			return true
	return false


static func _find_weapon_id(unit: Unit) -> StringName:
	for part: Part in unit.shell.living_parts():
		if part.damage > 0.0:
			return part.id
	return &""
