class_name Unit
extends RefCounted

## Runtime combat pilot: a Matrix (persistent brain) currently seated in a
## Shell (disposable body) on the grid.

const BASE_MP: float = 2.0
## Appendix E / docs/05: "a standard cyborg has 6 AP per turn, before perks
## and upgrades." Every other AP cost in the docs is quoted against this.
const DEFAULT_MAX_AP: int = 6
const AGILITY_STAT_KEY: StringName = &"agility"
## docs/04 gives no turn count for organic decay — a flagged, tunable
## placeholder, not a design decision.
const DECAY_TURNS := 3

var id: int = -1  # assigned by CombatState.add_unit; matches Grid.occupant_id
var matrix: Matrix
var shell: Shell
var cell: Vector2i
var squad_id: int = 0

var ap: int = 0
var max_ap: int = DEFAULT_MAX_AP
var mp: float = 0.0  # movement pool; discarded (not banked) at end of turn
var alive: bool = true

## Radians, ground-plane facing (docs/02). 0.0 faces
## BodyProjector.WORLD_FORWARD; continuous, never snapped to
## FRONT/BACK/LEFT/RIGHT.
var orientation: float = 0.0

## docs/10 taskblock05 F: socket transform overrides composing onto the
## body when UnitGeometry/BodyProjector walk it — snap, never animated.
## DOWN is never set here directly; it's a computed override applied by
## effective_pose() whenever the unit has no matrix docked.
var pose: Pose = Poses.idle()

## docs/10 taskblock03 E2: "1 MP unlocks free refacing for the turn — not 1
## MP per rotation." The first manual FaceAction each turn costs 1 MP and
## sets this; every manual face after that, same turn, is free. Reset at
## turn start (CombatState._start_turn()). Free-with-action facing
## (FaceAction.face_for_free) never reads or sets this — it's always free.
var facing_unlocked: bool = false

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
func mp_per_ap() -> float:
	var context := ResolverContext.new()
	context.parts = shell.all_parts()
	var agility: float = StatResolver.resolve(AGILITY_STAT_KEY, context).current
	return BASE_MP + agility


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
## to read as down." Moved here (was UnitView's own copy) — a query, not a
## stored flag, same as always. Callers that want DOWN's geometry to
## actually apply (taskblock05 F3's Pose) pass `Poses.down()` in
## explicitly where it matters (UnitView) rather than this being read
## automatically by every headless placements()/project() call — a bare
## test fixture that never bothers docking a matrix (most of them; matrix
## docking is irrelevant to what they're actually testing) must not
## silently start rendering sideways.
func is_downed() -> bool:
	return resolve_matrix() == null


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
	cloned.ap = ap
	cloned.max_ap = max_ap
	cloned.mp = mp
	cloned.alive = alive
	cloned.orientation = orientation
	cloned.pose = pose
	cloned.facing_unlocked = facing_unlocked
	cloned.held_matrix = held_matrix.duplicate(true) as Matrix if held_matrix != null else null
	cloned.surrogate_tier = surrogate_tier
	cloned.exposed_turns = exposed_turns
	return cloned
