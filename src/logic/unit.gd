class_name Unit
extends RefCounted

## Runtime combat pilot: a Matrix (persistent brain) currently seated in a
## Chassis (disposable body) on the grid.

const BASE_MP: float = 2.0
const DEFAULT_MAX_AP: int = 2
const AGILITY_STAT_KEY: String = "agility"

var id: int = -1  # assigned by CombatState.add_unit; matches Grid.occupant_id
var matrix: Matrix
var chassis: Chassis
var cell: Vector2i
var squad_id: int = 0

var ap: int = 0
var max_ap: int = DEFAULT_MAX_AP
var mp: float = 0.0  # movement pool; discarded (not banked) at end of turn
var alive: bool = true

var held_core: MatrixCore = null  # a MatrixCore carried after PickUpAction, awaiting ImplantAction


func _init(p_matrix: Matrix, p_chassis: Chassis, p_cell: Vector2i, p_squad_id: int = 0) -> void:
	matrix = p_matrix
	chassis = p_chassis
	cell = p_cell
	squad_id = p_squad_id


## MP granted per AP burned for movement (Appendix E). Derived live from
## aggregate_stats() so part swaps immediately affect mobility.
func mp_per_ap() -> float:
	var stats: Dictionary = chassis.aggregate_stats()
	var agility: float = stats.get(AGILITY_STAT_KEY, 0.0)
	return BASE_MP + agility
