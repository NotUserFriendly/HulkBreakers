class_name CellInspection
extends RefCounted

## docs/10 taskblock04 E3: "hovering a cell fills the readout with what's
## on it" — one pure lookup gathering everything the combat readout needs
## for a single cell: terrain, any unit (E1: full status, any squad — no
## knowledge gating yet), any field object (docs/10 taskblock04 C), and
## line of sight from whichever unit is currently selected, if any (the
## closest existing primitive to "cover state relative to the selected
## unit" — LoS.has_los, not a new mechanic). The view only ever renders
## this Dictionary; it computes nothing.

## taskblock-39 Pass D: the closed set of physical states a hovered cell
## can report as its own `terrain` — this class's own local enum, not
## `Grid`'s (which now holds only `Enums.SpawnMarker`, a game marker, not
## a physical fact). A genuinely closed classification (CLAUDE.md: enums
## for engine states), not an open content vocabulary, so an enum here is
## the right call, just no longer `Grid`'s own to own.
enum PhysicalState { EMPTY, OPEN, RAMP }


## `{}` for an out-of-bounds cell. Otherwise:
## `cell`, `terrain` (PhysicalState, above), `unit` (Unit or null),
## `field_object` (Part or null — taskblock-16 Pass B2: the one source of
## truth for "is this cell covered," no separate scalar alongside it),
## `visible_from_selected` (bool or null — null when nothing is selected).
static func inspect(state: CombatState, cell: Vector2i, selected: Unit = null) -> Dictionary:
	if not state.grid.in_bounds(cell):
		return {}
	var visible: Variant = null
	if selected != null:
		visible = LoS.has_los(state.grid, selected.cell, cell)
	return {
		"cell": cell,
		"terrain": _terrain_for(state.grid, cell),
		"unit": _unit_at(state, cell),
		"field_object": state.grid.blockers.get(cell),
		"visible_from_selected": visible,
	}


## taskblock-39 Pass C: reads the cell's own placed `Surface`, not the
## old terrain field directly — a wall was already never a real,
## standalone terrain state a hovered cell could read as (tb31 Pass C's
## own settled wall model is floored ground plus a real destructible
## blocker `Part`, already surfaced separately through `field_object`
## above); the remaining three states this collapses to (no surface at
## all -> EMPTY, a ramp-tagged surface -> RAMP, anything else walkable ->
## OPEN) are the complete real set placement can express.
static func _terrain_for(grid: Grid, cell: Vector2i) -> int:
	var surface: Surface = Surface.first_walkable(grid.surfaces_at(cell))
	if surface == null:
		return PhysicalState.EMPTY
	if Surface.RAMP_TAG in surface.part.tags:
		return PhysicalState.RAMP
	return PhysicalState.OPEN


static func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for unit: Unit in state.units:
		if unit.alive and unit.cell == cell:
			return unit
	return null
