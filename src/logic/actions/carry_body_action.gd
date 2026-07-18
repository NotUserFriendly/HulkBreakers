class_name CarryBodyAction
extends CombatAction

## Straps a downed body (a loose Part field item — an ejected subtree,
## docs/01) onto the carrier's own BACK socket, tagged INERT (docs/05): it
## contributes mass and volume boxes to the carrier's projection only — no
## stats, no weapons, no RAM — and occupies BACK so a backpack and a body
## are mutually exclusive.

const DEFAULT_AP_COST := 2

var carrier: Unit
var body_cell: Vector2i
var body_id: StringName
var ap_cost: int


func _init(
	p_carrier: Unit, p_body_cell: Vector2i, p_body_id: StringName, p_ap_cost: int = DEFAULT_AP_COST
) -> void:
	carrier = p_carrier
	body_cell = p_body_cell
	body_id = p_body_id
	ap_cost = p_ap_cost


func is_legal(state: CombatState) -> bool:
	var actual: Unit = state.find_unit(carrier.id)
	if actual == null or not actual.alive or state.current_unit() != actual:
		return false
	if actual.ap < ap_cost or actual.cell != body_cell:
		return false

	var body: Variant = state.grid.find_field_item(body_cell, body_id)
	if body == null or not (body is Part):
		return false

	var socket: Socket = _find_free_back_socket(actual.shell)
	return socket != null and PartGraph.is_legal_attachment(body, socket)


func apply(state: CombatState) -> void:
	var actual: Unit = state.find_unit(carrier.id)
	var body: Part = state.grid.find_field_item(body_cell, body_id)

	var items: Array = state.grid.field_items[body_cell]
	items.erase(body)
	if items.is_empty():
		state.grid.field_items.erase(body_cell)

	var socket: Socket = _find_free_back_socket(actual.shell)
	var owner: Part = _owner_of(actual.shell, socket)
	PartGraph.attach(body, owner, socket)
	if not (&"INERT" in body.tags):
		body.tags.append(&"INERT")

	actual.ap -= ap_cost
	var text: String = "CarryBodyAction: unit %d slung %s across their back" % [actual.id, body_id]
	state.log_action(text)
	if not state.is_preview:
		state.combat_log.emit(
			LogEvent.new(
				state.round_number,
				Enums.Phase.RESOLUTION,
				actual.id,
				&"carry_body",
				{"body": body_id},
				"slung %s across their back" % body_id
			)
		)


## The first free BACK socket anywhere in the shell, not just on the root —
## a specialized carrier part could host it instead of the torso.
func _find_free_back_socket(shell: Shell) -> Socket:
	for part: Part in shell.all_parts():
		var socket: Socket = PartGraph.find_free_socket(part, &"BACK")
		if socket != null:
			return socket
	return null


func _owner_of(shell: Shell, socket: Socket) -> Part:
	for part: Part in shell.all_parts():
		if part.sockets.has(socket):
			return part
	return null


func describe() -> String:
	return "CarryBodyAction(carrier=%d, body=%s)" % [carrier.id, body_id]
