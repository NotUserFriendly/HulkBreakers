class_name InspectRows
extends RefCounted

## taskblock-21 Pass A4: "strong sort, still tree'd: Weapons ->
## Inventories/containers -> body parts, each group nested by the socket
## tree beneath it. This supersedes the current inventory_panel — same
## 'currently controlled shell' scope, reorganized and sorted." Reuses
## `InventoryRows.build()` verbatim for every per-item number (dt, inert,
## kind, socket_label, depth) — this only adds a stable group partition on
## top, never recomputing anything `InventoryRows` already resolved.


## Weapons (`part.damage > 0.0`) first, then containers (`part.is_container`),
## then everything else (body/armor/organs/...) — three separate linear
## passes over `InventoryRows`' own flat list, never a `sort_custom` (Godot's
## sort is not stable), so each group's own internal order — its own
## socket-tree nesting, `depth` included — stays exactly what
## `InventoryRows` already produced. A CONTENTS row (something carried
## inside a container) groups by its OWN part: a weapon stashed in a
## backpack shows under Weapons, not buried under Containers.
static func build(unit: Unit, material_table: MaterialTable) -> Array[InspectRow]:
	var flat: Array[InventoryRow] = InventoryRows.build(unit, material_table)
	var result: Array[InspectRow] = []
	for group: InspectRow.Group in [
		InspectRow.Group.WEAPONS, InspectRow.Group.CONTAINERS, InspectRow.Group.BODY
	]:
		for row: InventoryRow in flat:
			if _group_for(row.part) == group:
				result.append(InspectRow.new(row, group))
	return result


static func _group_for(part: Part) -> InspectRow.Group:
	if part.damage > 0.0:
		return InspectRow.Group.WEAPONS
	if part.is_container:
		return InspectRow.Group.CONTAINERS
	return InspectRow.Group.BODY
