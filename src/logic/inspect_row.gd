class_name InspectRow
extends RefCounted

## taskblock-21 Pass A4: one row of the inspect panel's own strongly-sorted
## tree — an `InventoryRow` (docs/10 taskblock03 H1's own per-item
## computation, unchanged) plus which top-level group it sorts into.
## `InspectRows.build()` is the only place this is ever constructed.

enum Group { WEAPONS, CONTAINERS, BODY }

var row: InventoryRow
var group: Group


func _init(p_row: InventoryRow, p_group: Group) -> void:
	row = p_row
	group = p_group
