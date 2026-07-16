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
	cloned.held_matrix = held_matrix.duplicate(true) as Matrix if held_matrix != null else null
	cloned.surrogate_tier = surrogate_tier
	cloned.exposed_turns = exposed_turns
	return cloned
