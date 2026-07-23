class_name ShotScatter
extends RefCounted

## tb34 Pass A: the one place `range_cells -> RangeModel.dartboard_radius_
## scale -> Dartboard.resolve_scatter` gets assembled. Before this, every
## caller reassembled that chain by hand — `AttackAction`/`BurstAction`
## got it right, `AimController.resolve` (the drawn board) silently
## dropped the multiplier, so the board shown was always the weapon's
## best-case accuracy while the fired shot widened with range. One
## function owns the whole question now: every consumer (drawing,
## sampling) calls this, so the two can't independently drift again.


static func for_shot(
	shooter: Unit,
	weapon: Part,
	target_cell: Vector2i,
	_state: CombatState,
	extra_sources: Array[ModSource] = []
) -> Array[Ring]:
	var range_cells: int = Grid.distance_chebyshev(shooter.cell, target_cell)
	var radius_multiplier: float = RangeModel.dartboard_radius_scale(weapon, range_cells)
	return Dartboard.resolve_scatter(weapon, extra_sources, radius_multiplier)
