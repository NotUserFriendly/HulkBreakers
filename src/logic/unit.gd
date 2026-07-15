class_name Unit
extends RefCounted

## Runtime combat pilot: a Matrix (persistent brain) currently seated in a
## Frame (disposable body) on the grid.

const BASE_MP: float = 2.0
const DEFAULT_MAX_AP: int = 2
const AGILITY_STAT_KEY: StringName = &"agility"

var id: int = -1  # assigned by CombatState.add_unit; matches Grid.occupant_id
var matrix: Matrix
var frame: Frame
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


func _init(p_matrix: Matrix, p_frame: Frame, p_cell: Vector2i, p_squad_id: int = 0) -> void:
	matrix = p_matrix
	frame = p_frame
	cell = p_cell
	squad_id = p_squad_id


## MP granted per AP burned for movement (Appendix E). Resolved live through
## StatResolver (docs/08) so part swaps immediately affect mobility, and so
## this stays the one true source of the number — not an ad-hoc sum.
func mp_per_ap() -> float:
	var context := ResolverContext.new()
	context.parts = frame.all_parts()
	var agility: float = StatResolver.resolve(AGILITY_STAT_KEY, context).current
	return BASE_MP + agility
