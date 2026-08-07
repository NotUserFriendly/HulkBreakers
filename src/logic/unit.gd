class_name Unit
extends RefCounted

## Runtime combat pilot: a Matrix (persistent brain) currently seated in a
## Shell (disposable body) on the grid.

const BASE_MP: float = 2.0
## Appendix E / docs/05: "a standard cyborg has 6 AP per turn, before perks
## and upgrades." Every other AP cost in the docs is quoted against this.
const DEFAULT_MAX_AP: int = 6
const AGILITY_STAT_KEY: StringName = &"agility"

## The free rise: how far up a unit may step as ordinary walking, with no climbing
## capability, no ladder, and no discrete action at all. **The one continuous number that
## replaced five categorical "is this cell labelled a ramp" checks** (tb60 A) — the rule is
## *can this unit step up that far*, never *is this thing a ramp*.
##
## **Flagged, not designed.** 0.3 is the stair riser the design names — "a ramp becomes two
## ordinary tiles at 0.3 and 0.6" — and the stated reason step height had to exist at all was
## that `Pathfinder.MAX_CLIMB_LEVELS` is capability-gated, so "a 0.3 tile is not walkable-onto
## by anything in the game." So this is the stated default rather than an invented balance
## number, and everything downstream derives from it rather than assuming it: `MapGen` sizes a
## stair at `ceil(rise / step_height)` steps, so retuning this number re-shapes generated
## stairs with no further edit.
const BASE_STEP_HEIGHT: float = 0.3
const STEP_HEIGHT_STAT_KEY: StringName = &"step_height"
## Float slack for a rise compared against a step height. The same 0.001 every other
## height comparison in this codebase uses — a stair authored at exactly the step height
## must be walkable, not a coin flip on the last bit.
const STEP_EPSILON: float = 0.001

## docs/04 gives no turn count for organic decay — a flagged, tunable
## placeholder, not a design decision.
const DECAY_TURNS := 3

## How far back the trail reaches. Long enough that a unit cannot oscillate through
## it, short enough that ground stops being "recent" and can be swept again — a
## searcher that remembers everything eventually finds nowhere worth going. Flagged,
## not tuned.
const RECENT_CELLS := 8

var id: int = -1  # assigned by CombatState.add_unit; matches Grid.occupant_id
var matrix: Matrix
var shell: Shell
var cell: Vector2i
## taskblock-36 Pass D: this unit's own true elevation — `Grid.level` at
## `cell`, cached here (mirroring `cell` itself) rather than re-derived
## from the grid every time `UnitGeometry` needs a real Y, since neither
## `UnitGeometry` nor `BodyProjector` otherwise touch the grid at all.
## Synced from the grid at `CombatState.add_unit()`.
## taskblock-37 Pass D: also re-synced by `MoveAction` on every real cell
## change (Pass D adds movement verbs that can genuinely change it —
## tb36's own "nothing else writes it this pass" is no longer true) and by
## `BoutInjector.set_cell_level`'s existing debug force.
## taskblock-37 Pass E follow-up (supervisor): widened from `int` to
## `float`, matching `Grid.level` itself — genuinely arbitrary elevation,
## not just whole levels.
var level: float = 0.0
## taskblock-37 Pass D: the real, continuous world height `UnitGeometry`/
## `ShotPlane` actually place this unit at — `level * LEVEL_HEIGHT` for an
## ordinary cell, plus a half-level offset while resting on a RAMP cell
## (`UnitGeometry.true_height_for_cell`'s own doc comment). `level` alone
## gates discrete decisions (can I climb, is this drop legal); this is
## what drives position and the shot plane. Synced everywhere `level` is.
var height: float = 0.0
var squad_id: int = 0
## taskblock-43 Pass C: which planning batch this unit belongs to, where **0
## means "independent — plans for itself"** and is the default, so nothing
## changes until a bout deliberately assigns one.
##
## **This is deliberately NOT `squad_id`, which cannot carry it.** `squad_id` is
## the TEAM — 0/1, player/enemy, the two rosters `generate_bout_overlay` builds —
## and that meaning is assumed throughout the tests and every extraction/
## targeting/friendly-fire check in the codebase. A batch is a sub-group WITHIN a
## team, so it needs its own field; overloading the team id would have made every
## batch a second team.
##
## Assigned by hand only (`BoutInjector.set_batch`). Generated missions do not
## assign batches — automatic assignment is explicitly out of scope for this
## block and lives in `docs/PLAN.md`.
var batch_id: int = 0
## taskblock-44 Pass C: how much this unit's planner is allowed to know and do.
##
## **Authored per unit for now, and this block uses it for nothing** — it exists
## so part two's tier table has somewhere to read from, and so the field is
## already riding through `dup()` and re-registration before anything depends on
## it. It wants to DERIVE from Attributes (Int and Wis are the obvious sources),
## which have not landed; that is a rewiring, not a blocker.
##
## An open `StringName` vocabulary, not an enum (CLAUDE.md): tiers are content a
## designer extends, not a closed engine state. `WorldView` is the only thing
## that reads it today, to decide whether this unit gets team-blackboard access.
##
## The default is deliberately a tier that has full access, so every existing
## bout behaves exactly as it did before this field existed.
var intelligence_tier: StringName = &"TRAINED"

## taskblock-46 Pass C: what this unit does when it knows of no enemy.
##
## **An open `StringName`, one verb per unit, and that is the diagnostic** — if
## patrol is broken, only patrolling units misbehave and the failure is attributable
## to a verb rather than to "the search behaviour". Read as a PRECONDITION on the
## search actions (`UtilityContext.PRED_SEARCH_IS`), so exactly one of them is ever
## offered to a given unit: no mode flag, no branch, and a fifth verb is a `.tres`
## plus one published predicate.
##
## `ROAM` is the default because it is the one that suits a unit nobody has said
## anything about — cover ground, steadily, and find the fight.
var search_behaviour: StringName = &"ROAM"

## taskblock-46 Pass C: `PATROL`'s own route, and when each point was last stood on.
##
## Generated once, lazily, from where the unit finds itself (`SearchRoute`), because
## a patrol assigned at spawn would need a map the roster does not have. **Visit
## times drive the choice of next point — oldest first** — which cycles every point
## with no authored order, never ping-pongs between two while a third goes
## unvisited, and lets a point that turns out to be unreachable age out of
## contention on its own rather than needing to be detected and removed.
var patrol_points: Array[Vector2i] = []
## `Vector2i -> int` round number. An absent point has never been visited, which
## sorts oldest and therefore wins.
var patrol_visits: Dictionary = {}

## Where this unit has been lately, oldest first, capped at `RECENT_CELLS`.
##
## **`PATROL` was given a memory and the other three verbs were not, and that was
## the bug.** `ROAM` and `HUNT` score pure distance-from-here, which is memoryless:
## from A the farthest reachable cell is B, and from B the farthest is A again. A
## unit with no enemy in sight therefore walks to the edge of its reach and then
## alternates between two cells for the rest of the mission — observed live, both
## squads, every turn of the bout, and reproduced on an open board as ten of
## fourteen turns spent bouncing between `(19,23)` and `(31,23)`.
##
## The same fact `patrol_visits` records, generalised: `PATROL` avoided this by
## picking the point it had neglected longest, and the reasoning in that comment
## applies word for word to the verbs that had no route to hang it on.
var recent_cells: Array[Vector2i] = []

var ap: int = 0
var max_ap: int = DEFAULT_MAX_AP
var mp: float = 0.0  # movement pool; discarded (not banked) at end of turn
var alive: bool = true
## taskblock-22 Pass A: true once this unit has actually left the board via
## either extraction path (docs/07's "EXIT with loot") — distinct from
## `alive == false`, which also covers death. An extracted unit is a real
## success, never reported/rendered like a kill; `alive` still gates turn
## order/shot-plane membership/targeting exactly as it always has (an
## extracted unit sets both), so nothing downstream needs a second check.
var extracted: bool = false
## taskblock-22 Pass A2: "sit in extract until the end of the next round."
## The round this unit was first found standing on its own team's
## extraction cell, or -1 while not currently holding — reset the instant
## it steps off (EndTurnAction's own hold-check, the only writer). A
## flagged, simple approximation of "held through the end of the next
## round" (checked at this unit's own next turn, not a true round-boundary
## event — see EndTurnAction's own doc comment).
var extraction_hold_start_round: int = -1
## taskblock-22 Pass C: "the unit powers down — out of the fight, inert
## on the board (a shell with no active pilot). It still occludes/blocks
## as geometry." Deliberately NOT `alive == false` — a shut-down unit
## must stay in the shot plane (ShotPlane.build only ever gates on
## `alive`) and keep its own grid cell occupied, unlike death or
## extraction. `CombatState.advance_turn()`'s own turn-order candidates
## are the one thing this actually excludes it from — one-way for now, no
## "wake up" mechanic exists yet (flagged, not invented).
var shutdown: bool = false

## Radians, ground-plane facing (docs/02). 0.0 faces
## BodyProjector.WORLD_FORWARD; continuous, never snapped to
## FRONT/BACK/LEFT/RIGHT.
var orientation: float = 0.0

## docs/10 taskblock05 F: socket transform overrides composing onto the
## body when UnitGeometry/BodyProjector walk it — snap, never animated.
## DOWN is never stored here directly; callers that want it (HitVolumeView,
## based on is_downed()) pass Poses.down() in as an explicit override
## (see UnitGeometry.placements()'s own pose_override parameter) rather
## than this field silently switching underneath them.
var pose: Pose = Poses.idle()

## docs/10 taskblock03 E2: "1 MP unlocks free refacing for the turn — not 1
## MP per rotation." The first manual FaceAction each turn costs 1 MP and
## sets this; every manual face after that, same turn, is free. Reset at
## turn start (CombatState._start_turn()). Free-with-action facing
## (FaceAction.face_for_free) never reads or sets this — it's always free.
var facing_unlocked: bool = false

## docs/09 taskblock06 Pass F: which weapon (by pool part id) this unit is
## holding overwatch with, or empty if not armed. Set by OverwatchAction's
## own apply() (which also ends the unit's turn — you're holding, not
## acting); cleared the instant it fires (fires once, then spent) or at
## the start of this unit's own next turn (CombatState._start_turn()),
## same reset convention as facing_unlocked above.
var overwatch_weapon_id: StringName = &""

var held_matrix: Matrix = null  # a Matrix carried after PickUpAction, awaiting ImplantAction

## docs/04: a ladder, not a health bar. Demoted on damage to the matrix-
## hosting part (DamageResolver), decays further the longer it stays
## exposed (tick_organics_decay).
var surrogate_tier: SurrogateTier = SurrogateLadder.default_ladder()[0]
## Turns since the surrogate was first exposed or damaged; 0 means intact.
var exposed_turns: int = 0


func _init(p_matrix: Matrix, p_shell: Shell, p_cell: Vector2i, p_squad_id: int = 0) -> void:
	matrix = p_matrix
	shell = p_shell
	cell = p_cell
	squad_id = p_squad_id


## Steps the surrogate one rung down the ladder (docs/04: "a torso chewed
## to SPINAL still functions") and starts (or keeps) its exposure clock
## running.
func demote_surrogate(ladder: Array[SurrogateTier]) -> void:
	surrogate_tier = SurrogateLadder.demote(surrogate_tier, ladder)
	if exposed_turns == 0:
		exposed_turns = 1


## Called once per turn this unit is exposed (docs/04: "once exposed or
## damaged, tier decays over turns"). Demotes one further rung every
## DECAY_TURNS calls since the last demotion; a no-op once nothing is
## exposed yet.
func tick_organics_decay(ladder: Array[SurrogateTier]) -> void:
	if exposed_turns <= 0:
		return
	exposed_turns += 1
	if exposed_turns > DECAY_TURNS:
		exposed_turns = 1
		surrogate_tier = SurrogateLadder.demote(surrogate_tier, ladder)


## MP granted per AP burned for movement (Appendix E). Resolved live through
## StatResolver (docs/08) so part swaps immediately affect mobility, and so
## this stays the one true source of the number — not an ad-hoc sum.
##
## docs/10 taskblock05 E1's own rule ("broken parts already leave
## living_parts(), so a destroyed part's own modifiers already stop
## applying") was not actually true here — this read shell.all_parts()
## (every part regardless of hp) until docs/09 taskblock06 Pass D's own
## mid-move interrupt test needed a destroyed leg to genuinely lower
## mobility and found it didn't. Fixed to match every other modifier-
## bearing part in the game. taskblock-20 Pass D: reads `operable_parts()`
## now, not `living_parts()` directly — a `severed_controls`-wounded leg
## (hp intact, but inert) must stop contributing agility the same way a
## destroyed one already does.
## taskblock-42 Pass C: `operable` lets turn start hand in a list it has already
## walked instead of this walking the socket tree again. Empty (every other
## caller) behaves exactly as before.
func mp_per_ap(operable: Array[Part] = []) -> float:
	var context := ResolverContext.new()
	context.parts = operable if not operable.is_empty() else shell.operable_parts()
	var agility: float = StatResolver.resolve(AGILITY_STAT_KEY, context).current
	return BASE_MP + agility


## The free rise this unit walks up, resolved live through `StatResolver` (docs/08) exactly
## the way `mp_per_ap` resolves agility — so a leg swap changes what a unit can step over on
## the same frame, and the tooltip and the pathfinder read one call.
##
## **A per-unit stat is the thing a ramp could never express.** Long legs step higher; a
## tracked chassis steps nowhere at all. `operable_parts()`, not `living_parts()`: a
## wound-disabled leg stops contributing reach the same way it stops contributing agility.
##
## `operable` lets a caller that has already walked the socket tree hand the list in, the
## same amortization `mp_per_ap` takes.
func step_height(operable: Array[Part] = []) -> float:
	var context := ResolverContext.new()
	context.base = BASE_STEP_HEIGHT
	context.parts = operable if not operable.is_empty() else shell.operable_parts()
	return StatResolver.resolve(STEP_HEIGHT_STAT_KEY, context).current


## The smallest step height among `units` — **what a map's navigability invariant must be
## judged against**, since a rise that is free for the long-legged and not for everyone else
## strands whoever is shortest. `BASE_STEP_HEIGHT` for an empty roster, so a generator running
## before any unit exists assumes the unmodified body rather than assuming nothing.
static func lowest_step_height(units: Array[Unit]) -> float:
	var lowest: float = BASE_STEP_HEIGHT
	var seen := false
	for unit: Unit in units:
		var height: float = unit.step_height()
		if not seen or height < lowest:
			lowest = height
			seen = true
	return lowest


## docs/04 taskblock02 Pass D1: "Unit resolves its matrix by walking the
## tree" — works whether it docks directly in the shell root (a bot) or two
## levels down, inside an attached surrogate (a cyborg). The same object as
## `matrix` while piloted; the one place that still knows where it actually
## lives once nesting is involved.
func resolve_matrix() -> Matrix:
	for part: Part in shell.all_parts():
		if part.hosts_matrix() and part.hosted_matrix != null:
			return part.hosted_matrix
	return null


## docs/10 taskblock03 G: "a unit with no matrix docked (a shell)... needs
## to read as down." Moved here (was HitVolumeView's own copy) — a query, not a
## stored flag, same as always. Callers that want DOWN's geometry to
## actually apply (taskblock05 F3's Pose) pass `Poses.down()` in
## explicitly where it matters (HitVolumeView) rather than this being read
## automatically by every headless placements()/project() call — a bare
## test fixture that never bothers docking a matrix (most of them; matrix
## docking is irrelevant to what they're actually testing) must not
## silently start rendering sideways.
func is_downed() -> bool:
	return resolve_matrix() == null


## docs/09 taskblock06 Pass C: "poses are sampled at instants — nothing is
## ever integrated." `progress` (0.0-1.0, e.g. how far along a queued move
## a freeze lands) exists for a future real rig to pick a genuinely
## different pose partway through a walk cycle; today there is no such
## thing — only the three snap poses (docs/10 taskblock05 F3) — so this
## always returns the SAME pose regardless of `progress`. Sampling between
## discrete states is not interpolating between them, and this seam is
## deliberately incapable of the latter: resolution is always "set the
## pose, cast the ray, read the hit" against one frozen instant, never a
## blend two instants apart. Deterministic by construction — no
## accumulated float drift, no tick-rate dependence.
func pose_at(_progress: float) -> Pose:
	return pose


## docs/04 taskblock02 Pass D3: the docked surrogate's own capabilities, or
## empty for a bot (no surrogate at all) or an unoccupied shell.
func docked_surrogate_capabilities(ladder: Array[SurrogateTier]) -> Array[StringName]:
	for part: Part in shell.all_parts():
		if part.surrogate_tier == &"":
			continue
		for tier: SurrogateTier in ladder:
			if tier.id == part.surrogate_tier:
				return tier.capabilities
	return []


## False only if `part.body_requires` names a capability the docked
## surrogate doesn't have — a part failing this is INERT (present,
## carried, massed, shootable) never removed or errored (docs/04).
func can_use_part(part: Part, ladder: Array[SurrogateTier]) -> bool:
	if part.body_requires.is_empty():
		return true
	var capabilities: Array[StringName] = docked_surrogate_capabilities(ladder)
	for required: StringName in part.body_requires:
		if not required in capabilities:
			return false
	return true


## A fully independent copy — matrix, whole shell tree, and every scalar
## field — for TACTICS-time speculative previews (docs/09). Mutating a dup
## must never be observable on the original.
func dup() -> Unit:
	var cloned := Unit.new(matrix.duplicate(true) as Matrix, shell.dup(), cell, squad_id)
	cloned.id = id
	# taskblock-43 Pass C: batch membership has to ride along here and survive
	# `CombatState.add_unit`'s own re-registration (which re-registers EVERY
	# unit, dead ones included) — a preview clone that silently lost its batch
	# would plan as an independent and disagree with the real unit it previews.
	cloned.batch_id = batch_id
	cloned.intelligence_tier = intelligence_tier
	cloned.search_behaviour = search_behaviour
	cloned.patrol_points = patrol_points.duplicate()
	cloned.patrol_visits = patrol_visits.duplicate()
	cloned.recent_cells = recent_cells.duplicate()
	cloned.ap = ap
	cloned.max_ap = max_ap
	cloned.mp = mp
	cloned.alive = alive
	cloned.extracted = extracted
	cloned.extraction_hold_start_round = extraction_hold_start_round
	cloned.shutdown = shutdown
	cloned.orientation = orientation
	cloned.pose = pose
	cloned.facing_unlocked = facing_unlocked
	cloned.overwatch_weapon_id = overwatch_weapon_id
	cloned.held_matrix = held_matrix.duplicate(true) as Matrix if held_matrix != null else null
	cloned.surrogate_tier = surrogate_tier
	cloned.exposed_turns = exposed_turns
	return cloned
