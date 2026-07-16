class_name TileInspection
extends RefCounted

## docs/10 taskblock04 E3: "hovering a tile fills the readout with what's
## on it" — one pure lookup gathering everything the combat readout needs
## for a single cell: terrain, any unit (E1: full status, any squad — no
## knowledge gating yet), any field object (docs/10 taskblock04 C), and
## line of sight from whichever unit is currently selected, if any (the
## closest existing primitive to "cover state relative to the selected
## unit" — LoS.has_los, not a new mechanic). The view only ever renders
## this Dictionary; it computes nothing.


## `{}` for an out-of-bounds cell. Otherwise:
## `cell`, `terrain` (Enums.TerrainType), `unit` (Unit or null),
## `field_object` (Part or null), `cover_value` (float, this cell's own),
## `visible_from_selected` (bool or null — null when nothing is selected).
static func inspect(state: CombatState, cell: Vector2i, selected: Unit = null) -> Dictionary:
	if not state.grid.in_bounds(cell):
		return {}
	var visible: Variant = null
	if selected != null:
		visible = LoS.has_los(state.grid, selected.cell, cell)
	return {
		"cell": cell,
		"terrain": state.grid.get_terrain(cell),
		"unit": _unit_at(state, cell),
		"field_object": state.grid.blockers.get(cell),
		"cover_value": state.grid.get_cover_value(cell),
		"visible_from_selected": visible,
	}


static func _unit_at(state: CombatState, cell: Vector2i) -> Unit:
	for unit: Unit in state.units:
		if unit.alive and unit.cell == cell:
			return unit
	return null
