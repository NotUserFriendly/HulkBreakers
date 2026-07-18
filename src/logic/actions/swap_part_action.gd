class_name SwapPartAction
extends CombatAction

## Detaches whatever occupies a socket and attaches a loose replacement in
## its place (docs/01/05: "battlefield modification costs time"). The old
## occupant, if any, drops to the unit's own cell as a field item — a
## severed part doesn't vanish, it becomes pickup-able. `ap_cost` is data on
## the tool doing the swapping (docs/05's tool tiers), not a code constant.

var unit: Unit
var socket_owner_id: StringName
var socket_type: StringName
var replacement_id: StringName
var ap_cost: int


func _init(
	p_unit: Unit,
	p_socket_owner_id: StringName,
	p_socket_type: StringName,
	p_replacement_id: StringName,
	p_ap_cost: int
) -> void:
	unit = p_unit
	socket_owner_id = p_socket_owner_id
	socket_type = p_socket_type
	replacement_id = p_replacement_id
	ap_cost = p_ap_cost


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(unit.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.ap < ap_cost:
		return false

	var owner: Part = actual.shell.find_part(socket_owner_id)
	if owner == null:
		return false
	var socket: Socket = _find_socket(owner, socket_type)
	if socket == null:
		return false

	var replacement: Variant = state.grid.find_field_item(actual.cell, replacement_id)
	if replacement == null or not (replacement is Part):
		return false
	return socket_type in (replacement as Part).attaches_to


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(unit.id)
	var owner: Part = actual.shell.find_part(socket_owner_id)
	var socket: Socket = _find_socket(owner, socket_type)
	var replacement: Part = state.grid.find_field_item(actual.cell, replacement_id)

	var items: Array = state.grid.field_items[actual.cell]
	items.erase(replacement)
	if items.is_empty():
		state.grid.field_items.erase(actual.cell)

	var old: Part = PartGraph.detach(socket)
	if old != null:
		if not state.grid.field_items.has(actual.cell):
			state.grid.field_items[actual.cell] = []
		state.grid.field_items[actual.cell].append(old)

	PartGraph.attach(replacement, owner, socket)
	actual.ap -= ap_cost
	var text: String = (
		"SwapPartAction: unit %d swapped in %s at %s" % [actual.id, replacement_id, socket_type]
	)
	state.log_action(text)
	if not state.is_preview:
		var data: Dictionary = {
			"socket_owner": socket_owner_id,
			"socket_type": socket_type,
			"replacement": replacement_id,
			"removed": old.id if old != null else &"",
		}
		var event := LogEvent.new(
			state.round_number,
			Enums.Phase.RESOLUTION,
			actual.id,
			&"swap_part",
			data,
			"swapped in %s at %s" % [replacement_id, socket_type]
		)
		state.combat_log.emit(event)


func _find_socket(owner: Part, type: StringName) -> Socket:
	for socket: Socket in owner.sockets:
		if socket.socket_type == type:
			return socket
	return null


func describe() -> String:
	return (
		"SwapPartAction(unit=%d, socket=%s, replacement=%s)"
		% [unit.id, socket_type, replacement_id]
	)
