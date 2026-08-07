class_name UtilityLookahead
extends RefCounted

## taskblock-46 Pass E: **the Elite tier's search — "if I stand there, what happens
## to me next?"**
##
## Every other consideration reads the board as it is. This one reads the board as
## it WILL be, which is the only capability in `docs/11`'s tier table that is not
## expressible as a curve over something already published.
##
## ## It is a search, and it is expressed as an input
##
## The result is one normalized 0–1 number per candidate cell — the share of known
## enemies that can bring fire on that cell — fed through a response curve like
## every other consideration. That is deliberate and it is not a dodge: a utility
## AI has exactly one place to put "this option is worse than it looks", and it is
## the score. Bolting a separate minimax on beside the scorer would give a unit two
## ways to decide, which is the parallel-systems rule (`docs/00`) applied to the AI.
##
## What makes it a search rather than a lookup is the ply structure below.
##
## ## The plies
##
## - **Depth 1** is no lookahead: the flat score, what every tier below Elite gets.
## - **Depth 2** is the enemy's shot from where it stands. One `VisibilityField`
##   per known enemy, rooted at the ENEMY, so every candidate cell is answered by
##   the same flood — the cost is per-enemy, not per-candidate.
## - **Depth 3** is the enemy MOVING first and then shooting. That inverts the
##   geometry: the flood has to be rooted at the candidate cell, so it costs one
##   field per candidate examined, which is why depth 3 runs over a shortlist
##   (`SHORTLIST`) rather than over the whole candidate set.
##
## **Depth 3 is strictly wider than depth 2** — an enemy that can shoot from where
## it stands can also shoot after not moving — so the two plies are nested, not
## alternatives, and the deeper number can never be smaller than the shallower one.
## `test_utility_lookahead.gd` asserts that rather than trusting it.
##
## ## The cost is bounded before it is paid, not after
##
## A recursive search inside a per-turn planner is the thing that turns a 3-second
## bout into a 40-second one, and the failure is invisible: every test still passes,
## the bout just gets slower. So the shortlist is a hard cap taken BEFORE any
## depth-3 flood is built, and `fields_built` counts what was actually spent so a
## test can assert the bound holds rather than assuming it.
##
## ## Suspending a recursion
##
## The pacer suspends between plies and between shortlist entries — the points where
## a partial result is a complete answer at a shallower depth. A recursion that
## suspended mid-flood would have to carry the flood's own state across the
## resume, and there is nothing to gain from it: the flood is the cheap part, and
## the whole search re-derives from `(context, cell, depth)` with no accumulated
## state, so a suspend point only ever has to remember where in a loop it was.

## Which tiers get any lookahead at all. `docs/11`'s tier table, as data —
## a fifth tier that should search is added here, not by touching the search.
const TIERS: Array[StringName] = [&"ELITE"]

## The depth an Elite unit searches to. Flagged, not tuned: the taskblock specifies
## "2–3", and 3 is the deeper of the two the machinery supports.
const DEPTH := 3

## How many candidates get the depth-3 treatment, taken in the order the caller
## hands them over — which is score order, so it is the best options that get
## examined hardest. Flagged. **This is the cost bound**, and the reason it is a
## constant rather than a heuristic is that a heuristic that adapts to the board is
## a heuristic nobody can predict the cost of.
const SHORTLIST := 6

## Fields built since the last reset. Diagnostics for tests and the bench; **never
## read by a decision**, the standing posture for planner diagnostics here.
static var fields_built: int = 0


static func reset_diagnostics() -> void:
	fields_built = 0


## Whether `unit` searches at all. Everything below Elite gets depth 1 and pays
## nothing — the tier gates the INFORMATION, which is `docs/11`'s rule, and the
## unit that cannot predict simply scores the board in front of it.
static func searches(unit: Unit) -> bool:
	return unit != null and unit.intelligence_tier in TIERS


## `cell -> threat`, for the cells worth examining. **Returns an empty dictionary
## for any unit that does not search**, so the caller's "no entry means no opinion"
## reading is the same as a tier with no lookahead — no special case at the call
## site, and no default threat invented for a unit that never looked.
##
## `ordered_cells` is consumed in the order given and truncated to `SHORTLIST`; the
## planner hands it over in score order.
static func threat_map(
	context: UtilityContext, ordered_cells: Array[Vector2i], pacer: PlanPacer = null
) -> Dictionary:
	var threats: Dictionary = {}
	if not searches(context.unit):
		return threats
	var enemies: Array[Unit] = _known_enemies(context)
	if enemies.is_empty():
		return threats

	# Depth 2 first, for EVERY cell handed over. It is the cheap ply — one flood per
	# enemy, reused across all of them — and it is a complete answer on its own, so
	# a search that gets suspended and abandoned after this point has still made the
	# unit smarter than a Trained one rather than leaving it half-informed.
	var enemy_fields: Array = []
	var state: CombatState = context.view.canonical_state_for_resolvers()
	# taskblock-58 Pass C: **the board's geometry, derived once for the whole ply.** Every field
	# below is over the same grid and differs only in where it is cast from, and deriving the
	# spans is half a build's cost.
	var spans: SightSpans = SightSpans.of(state.grid)
	for enemy: Unit in enemies:
		enemy_fields.append(VisibilityField.build(state.grid, enemy.cell, spans))
		fields_built += 1
	for cell: Vector2i in ordered_cells:
		threats[cell] = _threat_from_standing_enemies(cell, enemies, enemy_fields)
	if DEPTH < 3 or (pacer != null and pacer.aborted):
		return threats

	# Depth 3: the enemy moves, THEN shoots. Rooted at the candidate, so it is paid
	# per candidate and therefore only over the shortlist.
	var reach: Array = []
	for enemy: Unit in enemies:
		reach.append(_reachable_set(context, enemy))
	var examined: int = mini(SHORTLIST, ordered_cells.size())
	for i in range(examined):
		if pacer != null:
			if pacer.should_abort():
				break
			if pacer.note_candidate():
				await pacer.frame_signal
		var cell: Vector2i = ordered_cells[i]
		threats[cell] = maxf(
			float(threats[cell]), _threat_from_moving_enemies(context, cell, enemies, reach, spans)
		)
	return threats


## The share of `enemies` that can already put a shot on `cell` without moving.
##
## A `VisibilityField` rooted at the enemy answers "does the enemy see this cell",
## and line of sight is mutual in this model — the field is built from the same
## `ShotPlane` geometry either way — so one flood per enemy serves every candidate.
static func _threat_from_standing_enemies(
	cell: Vector2i, enemies: Array[Unit], enemy_fields: Array
) -> float:
	var threatening := 0
	for i in range(enemies.size()):
		var enemy: Unit = enemies[i]
		var field: VisibilityField = enemy_fields[i]
		if field != null and not field.allows(cell):
			continue
		if not _reaches(enemy, Grid.distance_chebyshev(enemy.cell, cell)):
			continue
		threatening += 1
	return float(threatening) / float(enemies.size())


## The share of `enemies` that could move somewhere this turn and shoot `cell` from
## there. One flood rooted at `cell`, tested against each enemy's own reachable set
## — which is why this is the expensive ply and why it is shortlisted.
static func _threat_from_moving_enemies(
	context: UtilityContext, cell: Vector2i, enemies: Array[Unit], reach: Array, spans: SightSpans
) -> float:
	var state: CombatState = context.view.canonical_state_for_resolvers()
	# **This is the ply that pays per candidate**, so it is the one that most wants the board's
	# geometry derived once by its caller rather than re-derived per shortlist entry.
	var from_cell: VisibilityField = VisibilityField.build(state.grid, cell, spans)
	fields_built += 1
	var threatening := 0
	for i in range(enemies.size()):
		var enemy: Unit = enemies[i]
		for stand: Vector2i in reach[i] as Array[Vector2i]:
			if not from_cell.allows(stand):
				continue
			if not _reaches(enemy, Grid.distance_chebyshev(stand, cell)):
				continue
			threatening += 1
			break
	return float(threatening) / float(enemies.size())


## Where an enemy could stand this turn. Its own cell is always in the set: **not
## moving is a move**, and leaving it out would make a stationary enemy invisible to
## the ply that is specifically about enemies repositioning.
static func _reachable_set(context: UtilityContext, enemy: Unit) -> Array[Vector2i]:
	var pathfinder := Pathfinder.for_unit(context.view.grid, enemy)
	var budget: float = maxf(1.0, enemy.mp_per_ap() * float(enemy.ap))
	var cells: Array[Vector2i] = pathfinder.reachable(enemy.cell, budget)
	if not cells.has(enemy.cell):
		cells.append(enemy.cell)
	return cells


## Whether `enemy`'s own weapon covers `distance`. Reads the enemy's real weapon
## rather than assuming the searcher's — an Elite unit predicting a shotgun's threat
## at 12 cells would be predicting a shot that cannot happen.
static func _reaches(enemy: Unit, distance: int) -> bool:
	var weapon_id: StringName = UtilityContext.weapon_id_of(enemy)
	if weapon_id == &"":
		return false
	var weapon: Part = enemy.shell.find_part(weapon_id)
	if weapon == null:
		return false
	return (
		RangeModel.is_in_max_range(weapon, distance)
		and not RangeModel.blocks_min_range(weapon, distance)
	)


## The enemies this unit knows about — **through the `WorldView`**, so the lookahead
## inherits the same information gate as everything else and cannot predict the
## moves of a unit it has never seen.
static func _known_enemies(context: UtilityContext) -> Array[Unit]:
	var enemies: Array[Unit] = []
	for other: Unit in context.view.units_visible_to(context.unit):
		if other.squad_id == context.unit.squad_id or not other.alive:
			continue
		enemies.append(other)
	return enemies
