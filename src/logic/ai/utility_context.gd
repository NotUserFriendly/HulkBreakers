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
##
## **Path distance, not straight-line** — see `_closes_distance`. A scalar
## as-the-crow-flies number is what made a unit walk into the wall between itself
## and its target and stay there (`BR32.10`).
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
## **The picked weapon can single-pull** — it provides one of `ActionCatalog.ATTACK_ACTION_IDS`.
##
## tb64: `has_weapon` asks whether *a* weapon works, never whether it can do the thing the
## action being offered would do. A chaingun provides `burst` only, so `shoot` passed every
## precondition, won the scoring, and was then refused by `AttackAction.is_legal` on the same
## fact — `UtilityPlanner._commit` returning silently. **The decision log showed a confident
## `shoot@(25,13)` and then nothing**, which is what made the failure invisible for a whole
## taskblock. An action offered where its executor cannot build is a lie told to the log.
const PRED_WEAPON_SINGLE_FIRE := &"weapon_single_fire"
## The picked weapon can fire a burst. The `burst`-side counterpart of the above, and what
## `suppress` should always have asked — it names `executor_id = burst` and never checked.
const PRED_WEAPON_BURSTS := &"weapon_bursts"
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
## tb62 Pass E: this cell carries a mag lift pad with a real partner to ride to. **A
## precondition rather than a consideration**, because a ride is not merely a bad idea where
## there is no lift — it is not a thing that can happen, and offering it would put a
## guaranteed refusal into every decision log on the board.
const PRED_CELL_HAS_MAG_LIFT := &"cell_has_mag_lift"
## Some other living unit exists to defer to, which is `HoldAction`'s own
## legality requirement. Published so a hold that could never be enqueued is never
## even offered, rather than winning and then silently failing.
const PRED_CAN_DEFER_TURN := &"can_defer_turn"

# --- search: what a unit does when it knows of nobody ------------------------
#
# taskblock-46 Pass C. **This is the hole `BR45.03` named.** Every combat action
# required `enemy_known` and every mission action `is_player_squad`, so a
# non-player squad that had seen nobody matched neither gate and was offered
# nothing at all — `nothing over 488 candidates`, turn after turn, until the other
# squad wandered into view. A squad that never moves never closes, and the bout
# runs to the cap.
#
# The fill is four ordinary utility actions, one per unit, selected by precondition
# rather than by a mode flag. `docs/11` names the failure mode in general: when
# adding a gated action, ask what a unit that fails every gate does instead.

## No living enemy is known — the explicit inverse of `enemy_known`, published for
## the same reason `lof_blocked` is: preconditions are an all-must-hold list with no
## negation, so "only when I know of nobody" has no other way to be said.
const PRED_ENEMY_UNKNOWN := &"enemy_unknown"
## `search_<behaviour>` — one per authored verb, derived from `Unit.search_behaviour`
## so the vocabulary follows the `.tres` set. Exactly one is ever true.
const PRED_SEARCH_PREFIX := "search_"
## How much of this turn's movement budget the candidate cell spends. 0.0 is
## standing still, 1.0 is the whole budget. **One input, three verbs**: roam reads
## it plainly, hunt through a quadratic that strongly prefers distance, putter
## inverted. That is the model earning its keep — three behaviours, no branches.
const INPUT_TRAVEL_FRACTION := &"travel_fraction"
## Progress toward the patrol point visited longest ago. Same 0.5-is-no-change shape
## as the other closing inputs.
const INPUT_CLOSES_TO_PATROL := &"closes_to_patrol"

## taskblock-46 follow-up: **how long since this unit was last near this cell** —
## 1.0 for ground it has no recent memory of, falling toward 0.0 for where it just
## came from.
##
## The fix for the memoryless-search oscillation. `ROAM` and `HUNT` score distance
## from where the unit stands, which says nothing about whether it has *been* there:
## the farthest cell from A is B and the farthest from B is A, so a unit with
## nothing in sight bounces between two cells for the rest of the mission. This is
## the same fact `patrol_visits` records, published for the verbs that have no route
## to hang it on.
const INPUT_UNVISITED := &"unvisited"
## taskblock-46 Pass E: how far this cell is off the target's own facing. 0.0 is
## squarely in front of it, 1.0 is directly behind.
##
## **Real geometry, not a proxy.** `Unit.orientation` is a continuous ground-plane
## angle (`docs/02` — facings were deleted, not refactored), so this is the angle
## between where the target is looking and where the candidate cell actually is.
## It is the whole content of `flank`: a shot from behind is the same shot, taken
## from somewhere the target is not attending to.
const INPUT_FLANK_ANGLE := &"flank_angle"
## The unit is NOT standing where the mission wants it — so searching is allowed.
##
## **Without this a unit wanders off its own extraction cell.** Once it has arrived,
## `seek_extraction` stops being offered (no candidate makes progress toward a place
## it is already at), which leaves searching as the best-scoring thing available and
## walks it straight back off. Standing still and letting the hold mature is the
## job, and the search verbs have to know that the job exists.
##
## Stated positively rather than as a negation because preconditions are an
## all-must-hold list — the same reason `enemy_unknown` and `lof_blocked` are
## published as their own predicates.
const PRED_FREE_TO_SEARCH := &"free_to_search"

# --- the mission ------------------------------------------------------------
#
# **A combat-only action pool cannot finish a mission**, and measuring is what made
# that concrete: the planner completed 0% of bouts on its first head-to-head,
# because completion means EXTRACTED and nothing in a combat pool can gather an
# objective or walk to an extraction cell. A missing action, not a worse planner.
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
## 0.5 for no change, 1.0 for standing on the extraction cell.
const INPUT_CLOSES_TO_EXTRACTION := &"closes_to_extraction"

## taskblock-46 Pass E: **how dangerous standing here will be NEXT turn** — the
## share of known enemies that can bring fire on the cell, from `UtilityLookahead`.
##
## The one input that is not a reading of the board as it currently is, and the only
## one that is **tier-gated at the input rather than at the action**: a unit that
## does not search has no entry for a cell and gets `NO_PREDICTION`, which is
## deliberately the SAFE reading rather than the neutral one — see below.
const INPUT_PREDICTED_THREAT := &"predicted_threat"

## tb62 Pass D: **"can I get back?"** — 1.0 when the unit could return to where it is
## standing from this cell, 0.0 when going there strands it for the rest of the bout.
##
## The case is a hop-down: descent is free and ascent needs a step, a ladder, a lift or a
## capability nothing authors, so a unit that drops off a ledge to reach something can put
## itself somewhere it cannot leave. **Stranding is a legitimate outcome** — a player
## knocking someone into a pit is the game working — **but a unit choosing it unknowingly is
## not.**
##
## **A consideration, never a precondition**, which is the whole design of it. A prohibition
## would forbid the drop that reaches an otherwise unreachable target, and that drop is
## sometimes exactly right; a weight lets a good enough reason outbid it. The strength of the
## penalty is authored per action in the `.tres` files, so it is data.
##
## ## The authored floor is 0.85, and the number that seemed to justify it was noise
##
## `PLAN.md` asks for a candidate cell weighted *"slightly"* worse. A first version floored a
## stranding cell at **0.15**, a single `seeds_to_first_win` draw of **7** appeared to catch
## it against a **1** before the block, and the curve was softened on that reading.
##
## **Retaken four times per tree — pre-block `1,1,2,3,3`, at 0.15 `1,2,3`, at 0.85
## `1,1,2,2,3,4` — the reading does not hold.** `BoutCorpus.sample()` is clock-seeded on
## purpose, so a single draw compares nothing; the 7 is one outlier in fifteen.
##
## **0.85 stays, on the design rather than the measurement.** One-way ground is *ordinary* on
## a terraced board, so an 85% cut would price every movement decision rather than a rare
## trap. Flipping back on evidence this thin is the same error mirrored. See the taskblock-62
## report — nothing here can currently tell a movement regression from sampling noise.
##
## **One reverse flood per turn, not one per candidate.**
## `MapNavigability.cells_that_can_reach` walks every edge backwards from the unit's own
## cell — the established cheap shape, since the naive form is O(cells^2).
const INPUT_CAN_RETURN := &"can_return"

## tb62 Pass E: **how much ground riding the lift from this cell would save.**
##
## The framework scores *cells*, and a lift's whole value sits at the **other** cell — so
## boarding one can never be worth anything measured where you board. This publishes the
## difference: the improvement in path distance to the target between the pad the unit is on
## and the pad it would arrive at, normalised. 0.0 when the ride gains nothing, and it is 0.0
## for every cell with no lift on it, so an action considering it is only ever pulled by a
## lift that actually goes somewhere useful.
##
## **This is what makes a ride compete for AP against shooting rather than beating it.** A
## lift that saves nothing scores nothing, and the shot wins on its own merits.
const INPUT_LIFT_ADVANCE := &"lift_advance"

## What a unit that cannot see the future is told about it: **nothing threatens
## anywhere.**
##
## The tempting default is 0.5, "unknown". That would be wrong in a way that is hard
## to see: this input is authored inverted (danger is bad), so a mid value would
## make every candidate mildly worse for a Trained unit and *change how it plays*
## purely because a capability it does not have exists. A tier's own scoring must
## not move when a higher tier's feature is added, so the absent prediction has to
## be the value that multiplies out to no opinion at all.
const NO_PREDICTION := 0.0

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

## `cell -> what it costs THIS MOVER to travel from that cell to the target's own
## cell`, flooded once per turn. Absent means the target genuinely cannot be walked to
## from there, which is a different thing from far.
##
## taskblock-63 Pass C: **was `_path_cost_from_target`, a flood rooted at the target
## running outward**, which answered *"how far could the target walk to this cell"*.
## Renamed as well as reversed, because the old name described the old flood correctly
## and the bug was that nobody noticed it was not the question being asked.
var _path_cost_to_target: Dictionary = {}
## The patrol point this unit is heading for, or null when it is not patrolling.
var _patrol_target: Variant = null
## tb62 Pass D: cells from which this unit could return to where it is standing. Built once
## per turn in `build`; see `INPUT_CAN_RETURN`.
var _returnable: Dictionary = {}

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
## or no extraction cell defined for this unit's squad.
var _objective_cell: Variant = null
var _extraction_cell: Variant = null

## `cell -> predicted threat`, from `UtilityLookahead`. Empty for every tier that
## does not search, and empty on the pass that PRODUCES it — the planner scores once
## without it to find out which cells are worth searching.
var _threats: Dictionary = {}


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
	var pathfinder := Pathfinder.for_unit(p_view.grid, p_unit)
	# taskblock-46 Pass C: a patrolling unit lays out its route the first time it
	# needs one, records that it has arrived somewhere, and then picks the point it
	# has neglected longest. Done here rather than in the planner because it is
	# per-turn context exactly like the visibility field is, and doing it before
	# scoring is what stops a unit being drawn back to the point it is stood on.
	# The trail is written every turn, for every unit, before anything is scored —
	# not only while searching. A unit that fought its way across a room and then
	# lost its target must not treat that room as unexplored, and gating the record
	# on "am I searching right now" is exactly how it would.
	_record_recent(p_unit)
	if p_unit.search_behaviour == &"PATROL":
		if p_unit.patrol_points.is_empty():
			p_unit.patrol_points = SearchRoute.generate(p_view.grid, p_unit.cell, p_unit)
		SearchRoute.record_arrival(p_unit, p_view.round_number)
		context._patrol_target = SearchRoute.next_point(p_unit)

	# **Candidate cells are always computed.** This was gated on having something to
	# move toward — a target, a resource node, an extraction cell — and the gate has
	# now been wrong twice for the same reason: whatever the list of reasons to move
	# is, it is never complete, and a unit whose reason is missing from it silently
	# gets a candidate set of exactly one cell and cannot move at all.
	#
	# taskblock-45 Pass D found it with the mission actions, which could never fire
	# because a unit with nothing in sight had nowhere to consider going. taskblock-46
	# Pass C found it again with the search verbs, for which "nothing in sight" is
	# the entire trigger. The flood is cheap next to what the planner used to spend
	# per candidate, so the gate bought little and cost a class of bug twice.
	var reachable: Array[Vector2i] = pathfinder.reachable(p_unit.cell, context._move_budget)
	if not reachable.has(p_unit.cell):
		reachable.append(p_unit.cell)
	# tb62 Pass D: one reverse flood, before any candidate is scored — see `INPUT_CAN_RETURN`.
	context._returnable = MapNavigability.cells_that_can_reach(p_view.grid, p_unit.cell, pathfinder)

	if context.target == null:
		# No enemy, so no rectangle to cull toward — the whole reachable set is the
		# candidate set. It is also the cheap case: no `VisibilityField`, no cover
		# walks, nothing but distance arithmetic per cell.
		context.candidate_cells = reachable
		return context

	context._standoff = standoff_for(context.weapon)
	context._current_distance = Grid.distance_chebyshev(p_unit.cell, context.target.cell)
	context.field = VisibilityField.build(state.grid, context.target.cell)
	# taskblock-46 Pass C (BR32.10): one flood giving every cell its real path distance
	# to the enemy, shared by every candidate — the same shape as the visibility field,
	# one per target per turn.
	#
	# **taskblock-63 Pass C: it runs backwards now.** It was
	# `reachable_costs(target.cell)`, a forward flood rooted at the target, which
	# answers *"how far could the target walk to this cell"* — not *"how far must I
	# walk to the target"*. Symmetric ground makes those identical and it never
	# mattered; one-way ground makes them disagree exactly, and a terraced board is
	# made of one-way ground, so a cell under a shelf read as nearly as good as one on
	# it because dropping off is cheap.
	#
	# **And it absorbs the flood tb62 Pass E had to add beside it.** `_can_reach_target`
	# was `MapNavigability.cells_that_can_reach`, an unweighted reverse flood built for
	# `lift_advance` precisely because the weighted one ran the wrong way — the same
	# question asked twice, in two directions, by two systems. The key set of this
	# dictionary IS "which cells can reach the target", so the second flood is gone
	# rather than kept in step.
	context._path_cost_to_target = pathfinder.costs_to_reach(context.target.cell, INF, true)
	# taskblock-43 Pass B's rectangle carries forward: it is candidate-set geometry
	# with no planner state in it, so nothing about replacing the scorer invalidates
	# it.
	context.candidate_cells = EngagementRect.cull(
		p_unit, context.target, context._standoff, reachable
	)
	# **But the rectangle is drawn toward the ENEMY, and a unit has somewhere else
	# to be.** Culled alone, a unit that can see an enemy could not consider a
	# single cell toward its resource node or its extraction cell, because those sit
	# outside a box spanned by the unit and its target. It could fight or it could
	# travel, never both — so a bout where the two squads could see each other ran
	# to the turn cap with the objective untouched. Adding back only the cells that
	# genuinely make progress keeps the set small: at most one more per destination
	# per direction, not the whole reachable blob.
	context._add_mission_progress_cells(reachable)
	return context


## The predicate id for a search behaviour — `ROAM` becomes `search_roam`. Derived
## rather than enumerated, so a fifth verb is a `.tres` naming `search_<its id>` and
## no code learns its name.
static func search_predicate_for(behaviour: StringName) -> StringName:
	return StringName(PRED_SEARCH_PREFIX + String(behaviour).to_lower())


## Where the unit is standing for scoring purposes — its own cell, or the
## destination it has already committed to this turn.
## Hands the lookahead's result to the scorer. Called once per turn by the planner,
## after the pass that decided which cells were worth searching.
func set_threats(threats: Dictionary) -> void:
	_threats = threats


## What the lookahead concluded about `cell`, or `NO_PREDICTION` when nothing looked
## at it — which covers both "this tier does not search" and "this cell was outside
## the shortlist", and those want the same answer: **no opinion, not a guess.**
func predicted_threat(cell: Vector2i) -> float:
	return float(_threats.get(cell, NO_PREDICTION))


## Adds `unit`'s current cell to its trail, oldest dropped first. Idempotent within
## a turn — standing still does not fill the trail with one cell and erase the
## memory of everywhere else, which would reintroduce the oscillation from the other
## direction.
static func _record_recent(unit: Unit) -> void:
	if unit == null:
		return
	if (
		not unit.recent_cells.is_empty()
		and unit.recent_cells[unit.recent_cells.size() - 1] == unit.cell
	):
		return
	unit.recent_cells.append(unit.cell)
	while unit.recent_cells.size() > Unit.RECENT_CELLS:
		unit.recent_cells.remove_at(0)


## 1.0 for ground with no recent memory attached, scaling down toward 0.0 for the
## cell the unit is standing on and the ones it just came from.
##
## **Graded by recency rather than a flat visited/not**, because a binary would make
## every cell outside the trail identical and leave the unit free to bounce between
## two cells eight steps apart — the same oscillation with a longer period. Distance
## to the nearest trail entry is what makes it a gradient rather than a wall.
## 1.0 when `cell` has a route back to where the unit stands, 0.0 when it does not.
##
## The unit's own cell is trivially returnable and is seeded into the flood, so standing
## still never reads as stranding. An empty map — a context built before the flood ran, which
## every hand-made fixture produces — reads as returnable rather than as stranded: a missing
## measurement must not become a penalty.
func _can_return(cell: Vector2i) -> float:
	if _returnable.is_empty():
		return 1.0
	return 1.0 if _returnable.has(cell) else 0.0


## See `INPUT_LIFT_ADVANCE`. Zero unless `cell` carries a lift pad whose partner is genuinely
## closer to the target than `cell` is; the gain is scaled against the unit's own move budget
## so "a lift worth an action" means "it saved about a turn's walking".
func _lift_advance(cell: Vector2i) -> float:
	if target == null or _path_cost_to_target.is_empty():
		return 0.0
	var partner: Variant = Surface.mag_lift_destination(view.grid, cell)
	if partner == null:
		return 0.0
	var here: float = float(_path_cost_to_target.get(cell, INF))
	var there: float = float(_path_cost_to_target.get(partner as Vector2i, INF))
	# A partner the flood never reached is not an improvement of unknown size — it is a cell
	# the target cannot be walked to from, which is the opposite of progress.
	if not is_finite(there):
		return 0.0
	# **The strongest case, and the one the action exists for: the ride is the only way the
	# two units ever meet.** taskblock-63 Pass C: this used to consult a second, unweighted
	# reverse flood built specifically because the weighted one ran outward from the target.
	# The weighted flood runs backwards now, so its own key set answers this — one flood,
	# one direction, no pair to keep in step.
	if not _path_cost_to_target.has(cell):
		return 1.0
	if not is_finite(here) or not is_finite(there) or there >= here:
		return 0.0
	return clampf((here - there) / maxf(_move_budget, 1.0), 0.0, 1.0)


func _unvisited(cell: Vector2i) -> float:
	if unit == null or unit.recent_cells.is_empty():
		return 1.0
	var freshest := 0.0
	for i in range(unit.recent_cells.size()):
		# Later entries are more recent and weigh more heavily.
		var recency: float = float(i + 1) / float(unit.recent_cells.size())
		var steps: int = Grid.distance_chebyshev(cell, unit.recent_cells[i])
		var closeness: float = clampf(1.0 - float(steps) / float(Unit.RECENT_CELLS), 0.0, 1.0)
		freshest = maxf(freshest, recency * closeness)
	return clampf(1.0 - freshest, 0.0, 1.0)


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
			INPUT_TRAVEL_FRACTION: _travel_fraction(cell),
			INPUT_CLOSES_TO_PATROL: _closes_to(cell, _patrol_target),
			INPUT_UNVISITED: _unvisited(cell),
			INPUT_FLANK_ANGLE: 0.0,
			INPUT_PREDICTED_THREAT: predicted_threat(cell),
			INPUT_CAN_RETURN: _can_return(cell),
			INPUT_LIFT_ADVANCE: 0.0,
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
		INPUT_CLOSES_DISTANCE: _closes_distance(cell, distance),
		INPUT_MOVE_ECONOMY: _move_economy(cell),
		INPUT_OWN_INTEGRITY: _integrity,
		INPUT_TRAVEL_FRACTION: _travel_fraction(cell),
		INPUT_CLOSES_TO_PATROL: _closes_to(cell, _patrol_target),
		INPUT_UNVISITED: _unvisited(cell),
		INPUT_FLANK_ANGLE: _flank_angle(cell),
		INPUT_PREDICTED_THREAT: predicted_threat(cell),
		INPUT_CAN_RETURN: _can_return(cell),
		INPUT_LIFT_ADVANCE: _lift_advance(cell),
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
	# unit walked off its own extraction cell, walked back the next turn, and did it
	# again — two units alternating onto one cell for the whole turn cap, neither
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
		PRED_WEAPON_SINGLE_FIRE: _weapon_provides_any(ActionCatalog.ATTACK_ACTION_IDS),
		PRED_WEAPON_BURSTS: _weapon_provides_any([&"burst"] as Array[StringName]),
		PRED_ENEMY_KNOWN: target != null,
		PRED_CELL_IS_ELSEWHERE: cell != _origin,
		PRED_CELL_IS_CURRENT: cell == _origin,
		PRED_WEAPON_REACHES: target != null and _weapon_reaches(distance),
		PRED_LOF_POSSIBLE: target != null and _lof_possible(cell),
		PRED_LOF_BLOCKED: target != null and not _lof_possible(cell),
		PRED_CELL_IS_COVERED: target != null and _is_covered(cell),
		PRED_CELL_HAS_MAG_LIFT: Surface.mag_lift_destination(view.grid, cell) != null,
		PRED_CAN_DEFER_TURN: _can_defer,
		PRED_OBJECTIVE_OPEN: _objective_cell != null,
		PRED_OBJECTIVE_DONE: mission != null and not _has_open_objective(),
		PRED_CELL_IS_OBJECTIVE: _objective_cell != null and cell == _objective_cell,
		PRED_IS_PLAYER_SQUAD: mission != null and unit.squad_id == mission.player_squad_id,
		PRED_ENEMY_UNKNOWN: target == null,
		PRED_FREE_TO_SEARCH: not _at_mission_post(),
		search_predicate_for(unit.search_behaviour): true,
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
##
## tb61 Pass A (`BR52.10`): **and a squadmate standing in the line blocks it, same as terrain
## does.** This read `field.allows(cell)` alone — a `VisibilityField` test, so terrain and
## opacity only. `_nearest_known_enemy` already skips allies as *targets*, but nothing anywhere
## asked whether one was standing in the way, so an AI unit would fire a twelve-round burst
## through the squadmate directly in front of it. Reproduced from a real bout: eight consecutive
## pulls resolving on the ally, ending in a matrix ejection, on turn zero.
##
## **A regression, not a gap that was always there.** The retired branch planner refused this and
## logged `held: ally_in_line`; the check went with it in the taskblock-45 rewrite.
##
## **No new input, no new weight, and that is deliberate.** `shoot.tres` already carries
## `line_of_fire` as a consideration, and `UtilityScorer`'s product model preserves a zero at
## every `n` — so answering `false` here vetoes shooting from that cell outright, which is
## exactly the old refusal. Inventing a "friendly fire risk" weight would have been a balance
## number nobody chose, to express something the existing veto already says.
func _lof_possible(cell: Vector2i) -> bool:
	if field != null and not field.allows(cell):
		return false
	return not _ally_in_line(cell)


## True if a living squadmate stands on the cells between `cell` and the target.
##
## **`Grid.line` is the shared supercover walk**, the same one `LoS` reasons over — a
## hand-rolled second line rule here is precisely the parallel system that would drift.
## Endpoints are excluded: the shooter's own cell is where it stands, and the target's cell is
## what it is shooting at.
##
## **Cell granularity, matching what this function is.** It is a cheap conservative filter whose
## `true` is confirmed later against the real resolver; a per-candidate ray march would be the
## right answer to a different question and would cost one march per scored cell, which is the
## trap `Cover.is_covered_from` was pulled out of the scoring loop for.
##
## **Read through `units_visible_to`, never `_state.units`** — that is the seam `WorldView`
## exists to hold. It costs nothing here: *"allies are always known: they are on the radio"*, so
## a squadmate is in the list at every intelligence tier, including `MINDLESS`. A unit too dim to
## remember an enemy still knows where its own squad is standing.
func _ally_in_line(cell: Vector2i) -> bool:
	if target == null:
		return false
	var allies: Array[Vector2i] = []
	for other: Unit in view.units_visible_to(unit):
		if other != unit and other.alive and other.squad_id == unit.squad_id:
			allies.append(other.cell)
	if allies.is_empty():
		return false
	for step: Vector2i in Grid.line(cell, target.cell):
		if step == cell or step == target.cell:
			continue
		if step in allies:
			return true
	return false


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


## **How much nearer this cell gets me ALONG A PATH**, not as the crow flies.
##
## 0.5 means "no closer than I already am", which keeps a neutral candidate mid-range
## rather than at an end — an input pinned to 0.0 would veto through the product,
## and "did not improve" is not a veto.
##
## ## Why straight-line was wrong (BR32.10)
##
## `approach` scores this input, and on concave geometry the cell on the WRONG side
## of a wall is the one closest as the crow flies. A unit therefore walked into the
## wall between itself and its target and stayed there, every turn, because the
## scoring genuinely preferred it. That is not a fallback that failed to fire — the
## retired planner had a Dijkstra-to-a-cell-with-a-line branch for exactly this, and
## nothing calls it any more. **Being stuck became a scoring outcome**, and the fix
## belongs in the score.
##
## Path cost comes from one flood (`_path_cost_to_target`), so a cell behind a wall is
## correctly *further* even when it is spatially nearer.
##
## **taskblock-63 Pass C: the flood is the mover's, not the target's.** It used to run
## outward from the target, which prices *the target walking here*. Where the two
## disagree is exactly where elevation exists: a cell at the foot of a shelf is a cheap
## drop away from a target standing on it and an expensive climb back, so the outward
## flood scored standing under the shelf as almost as good as standing on it.
##
## ## And absence had to change meaning with it
##
## Under the outward flood, "absent" meant *the target cannot walk here*, which is
## nearly always a walled-off target rather than a fact about the candidate — so
## falling back to straight-line was right, and vetoing would have made a sealed enemy
## veto every approach equally.
##
## Under the reverse flood, "absent" means **I cannot walk to the target from there**,
## which is a fact about the candidate and the strongest one this input has. Keeping
## the old fallback would have thrown the fix away in exactly the case it was for: the
## cell under the shelf is *adjacent* to a target standing on it, so straight-line
## scores it as excellent while the mover genuinely cannot get up.
##
## So there are three cases, and the middle one is the whole point:
##
## - **Neither here nor there can reach** — nobody on this board can walk to the
##   target, so rank on straight line as before. A sealed enemy still must not flatten
##   every candidate to the same score.
## - **There cannot reach and here can** — 0.0. Stepping somewhere the target becomes
##   unreachable from is the opposite of closing.
## - **Here cannot reach and there can** — 1.0. Anywhere that restores a route beats
##   standing where there is none.
func _closes_distance(cell: Vector2i, distance: int) -> float:
	var here: float = _path_distance_to_target(_origin)
	var there: float = _path_distance_to_target(cell)
	if not is_finite(here) and not is_finite(there):
		here = float(_current_distance)
		there = float(distance)
	elif not is_finite(there):
		return 0.0
	elif not is_finite(here):
		return 1.0
	if here <= 0.0:
		return 0.5
	return clampf(0.5 + 0.5 * (here - there) / here, 0.0, 1.0)


## Path cost from `cell` to the target, or `INF` when there is no route at all.
##
## **The cheapest-neighbour-plus-one rule that used to live here is gone**, and its
## reason went with the outward flood. It existed because the unit's own cell is
## occupied and an outward flood can never enter it — but a *reverse* flood only ever
## reads a cell as a source, and `move_cost(from, to)` checks the destination, so the
## mover's own cell is priced normally. Keeping the rule would have let a stranded cell
## borrow a reachable neighbour's cost and read as connected.
##
## `INF` for a context with no flood at all (every hand-made fixture) puts the caller
## in its own straight-line branch, which is the honest answer when there is no
## measurement rather than a penalty invented from its absence.
func _path_distance_to_target(cell: Vector2i) -> float:
	if _path_cost_to_target.has(cell):
		return float(_path_cost_to_target[cell])
	return INF


## Chebyshev distance against the turn's movement budget — a deliberate PROXY for
## real path cost. The true cost needs a pathfind per candidate, which is the class
## of per-candidate work this block exists to remove; the proxy only ever ranks
## candidates against each other and is never shown to a player or used to decide
## whether a move is affordable (`ActionQueue.enqueue` owns that).
## The complement of `move_economy`: how much of the budget this cell SPENDS.
## Published as its own input rather than expecting every author to invert
## `move_economy`, because "prefer to travel" and "prefer to stay" are both ordinary
## things to want and an inverted curve at the authoring site reads like a mistake.
func _travel_fraction(cell: Vector2i) -> float:
	return clampf(float(Grid.distance_chebyshev(_origin, cell)) / _move_budget, 0.0, 1.0)


func _move_economy(cell: Vector2i) -> float:
	var steps: float = float(Grid.distance_chebyshev(_origin, cell))
	return clampf(1.0 - steps / _move_budget, 0.0, 1.0)


## How far `cell` sits off the target's facing, 0.0 in front to 1.0 behind. Zero
## with no target, which vetoes `flank` — correctly, since there is nobody to get
## behind.
func _flank_angle(cell: Vector2i) -> float:
	if target == null or cell == target.cell:
		return 0.0
	var toward: float = FaceAction.orientation_toward(target.cell, cell)
	return clampf(absf(angle_difference(target.orientation, toward)) / PI, 0.0, 1.0)


func _is_covered(cell: Vector2i) -> bool:
	# taskblock-58 Pass C1: **the field this context already built for this same target.** The
	# `LoS.has_los` this used to reach through was recomputing, per candidate cell, an answer
	# sitting a field lookup away.
	return Cover.is_covered_from(cell, target.cell, view, unit, field)


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


## Whether the unit is already standing where its mission wants it — on the
## resource node with something left to gather, or on its extraction cell with the
## objectives done. **A fact about the unit, not about a candidate cell**, which is
## why it reads `_origin` rather than the cell being scored: the question is "does
## this unit have a post", not "would this cell be one".
func _at_mission_post() -> bool:
	if mission == null or unit.squad_id != mission.player_squad_id:
		return false
	if _objective_cell != null and _origin == _objective_cell:
		return true
	return _extraction_cell != null and not _has_open_objective() and _origin == _extraction_cell


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


## This unit's own extraction cell. `team_extraction_cells` first, falling back to
## the squad-agnostic `extraction_cells` for the player's own squad ONLY — the same
## asymmetry the retired planner's flee branch documented, and for the same reason: an enemy squad
## with no team-coded entry has no defined extraction cell, and sending it to the
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


## Which part is `unit`'s weapon. Public because the lookahead has to read an
## ENEMY's weapon to predict its reach, and re-deriving "which part shoots" at a
## second site is how two answers to one question get into a codebase.
static func weapon_id_of(unit: Unit) -> StringName:
	return _find_weapon_id(unit)


## **Whether the weapon this context picked offers any of `ids`.** The one place the planner
## asks what a weapon can actually do, so `shoot` and `burst` cannot drift apart from what
## `ActionCatalog.build_firing_action` will accept.
func _weapon_provides_any(ids: Array[StringName]) -> bool:
	if weapon == null:
		return false
	for id: StringName in ids:
		if id in weapon.provides_actions:
			return true
	return false


## Which part is this unit's weapon.
##
## tb64: **a part that provides no action is not a weapon the planner can use.** This returned
## the first living part with `damage > 0` and never consulted `provides_actions`, so a unit
## carrying a damaging part with nothing to offer had the planner select it and then find
## nothing to build with it. Preferring a part that provides something keeps every
## single-weapon unit answering exactly as before — the overwhelmingly common case — while a
## unit whose first damaging part is unusable now reaches the one behind it.
##
## The old answer stays as the fallback rather than returning `&""`: a damaging part with no
## authored `provides_actions` is a data gap, and going silent on it would hide the gap
## instead of surfacing it through `weapon_single_fire`/`weapon_bursts` reading false.
static func _find_weapon_id(unit: Unit) -> StringName:
	var fallback: StringName = &""
	for part: Part in unit.shell.living_parts():
		if part.damage <= 0.0:
			continue
		if not part.provides_actions.is_empty():
			return part.id
		if fallback == &"":
			fallback = part.id
	return fallback
