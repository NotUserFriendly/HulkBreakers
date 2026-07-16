class_name InventoryRows
extends RefCounted

## docs/10 taskblock03 H1: builds the inventory panel's row list from a
## Unit's shell — pure and headless-testable, so "does the panel show
## sockets and contents as what they actually are" is a plain GUT test,
## never something only a screenshot can catch. The view (InventoryPanel)
## only ever turns this into TreeItems; it computes nothing.


## Depth-first: the shell root first, then each socket's occupant (in socket
## declaration order) recursively, with that part's own `contents` (if any)
## inserted right after it, one level deeper. Destroyed parts (hp <= 0) are
## omitted entirely — "struck through or omitted... they've left the tree
## anyway" (H2).
static func build(unit: Unit, material_table: MaterialTable) -> Array[InventoryRow]:
	var rows: Array[InventoryRow] = []
	if unit.shell.root == null:
		return rows
	var ladder: Array[SurrogateTier] = SurrogateLadder.default_ladder()
	_walk_socketed(unit.shell.root, 0, &"", rows, unit, material_table, ladder)
	return rows


static func _walk_socketed(
	part: Part,
	depth: int,
	socket_label: StringName,
	rows: Array[InventoryRow],
	unit: Unit,
	material_table: MaterialTable,
	ladder: Array[SurrogateTier]
) -> void:
	if part.hp <= 0:
		return
	rows.append(
		_row(part, depth, InventoryRow.Kind.SOCKET, socket_label, unit, material_table, ladder)
	)
	if part.is_container:
		_walk_contents(part, depth + 1, rows, unit, material_table, ladder)
	for socket: Socket in part.sockets:
		if socket.occupant == null:
			continue
		var label: StringName = socket.id if socket.id != &"" else socket.socket_type
		_walk_socketed(socket.occupant, depth + 1, label, rows, unit, material_table, ladder)


static func _walk_contents(
	container: Part,
	depth: int,
	rows: Array[InventoryRow],
	unit: Unit,
	material_table: MaterialTable,
	ladder: Array[SurrogateTier]
) -> void:
	for item: Part in container.contents:
		if item.hp <= 0:
			continue
		rows.append(
			_row(item, depth, InventoryRow.Kind.CONTENTS, &"", unit, material_table, ladder)
		)
		if item.is_container:
			_walk_contents(item, depth + 1, rows, unit, material_table, ladder)


static func _row(
	part: Part,
	depth: int,
	kind: InventoryRow.Kind,
	socket_label: StringName,
	unit: Unit,
	material_table: MaterialTable,
	ladder: Array[SurrogateTier]
) -> InventoryRow:
	var dt: float = material_table.get_entry(part.material).dt
	var inert: bool = not unit.can_use_part(part, ladder)
	return InventoryRow.new(part, depth, kind, socket_label, dt, inert)
