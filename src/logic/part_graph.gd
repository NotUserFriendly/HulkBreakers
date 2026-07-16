class_name PartGraph
extends RefCounted

## Tree ops on the socket graph (docs/01) — the structural attachment tree.
## Distinct from Inventory's contents tree (sockets vs. contents are
## different relationships; a backpack is socket-attached to BACK and
## separately contains items).


static func is_legal_attachment(part: Part, socket: Socket) -> bool:
	return socket.socket_type in part.attaches_to and socket.occupant == null


## First free socket of `socket_type` on `target`, or null. Order-dependent
## ("whichever is free first") — legitimate only for genuinely "any will
## do" cases like deep-strike scavenging. Never use this where it matters
## WHICH socket; see `find_socket`.
static func find_free_socket(target: Part, socket_type: StringName) -> Socket:
	for socket: Socket in target.sockets:
		if socket.socket_type == socket_type and socket.occupant == null:
			return socket
	return null


## The socket on `target` (not recursive) whose own `id` matches — the
## assembly path for anything that cares WHICH socket, not just "a free one
## of this type" (docs/01 taskblock02 Pass B). Order-independent: reversing
## `target.sockets`'s declaration order changes nothing about what this
## returns.
static func find_socket(target: Part, socket_id: StringName) -> Socket:
	for socket: Socket in target.sockets:
		if socket.id == socket_id:
			return socket
	return null


## Attaches `part` into `socket`, which must belong to `target`. Rejects if
## the socket isn't target's, the type doesn't match, the socket is occupied,
## or attaching would create a cycle (target already sits inside part's own
## subtree).
static func attach(part: Part, target: Part, socket: Socket) -> bool:
	if not target.sockets.has(socket):
		return false
	if not is_legal_attachment(part, socket):
		return false
	if walk(part).has(target):
		return false
	socket.occupant = part
	return true


## Detaches whatever occupies `socket`, returning it (or null if empty).
static func detach(socket: Socket) -> Part:
	var occupant: Part = socket.occupant
	socket.occupant = null
	return occupant


## Depth-first traversal of the whole assembly rooted at `root`, root
## included.
static func walk(root: Part) -> Array[Part]:
	var result: Array[Part] = [root]
	for socket: Socket in root.sockets:
		if socket.occupant != null:
			result.append_array(walk(socket.occupant))
	return result


## The socket (anywhere in root's assembly) whose occupant is `target`, or
## null.
static func find_owning_socket(root: Part, target: Part) -> Socket:
	for part: Part in walk(root):
		for socket: Socket in part.sockets:
			if socket.occupant == target:
				return socket
	return null


## Detaches `target` from wherever it's attached within `root`'s assembly.
## `target` keeps its own sockets/occupants exactly as they were — destroying
## a part drops its subtree as one intact assembly, not a pile of bits.
## Returns false if `target` isn't found anywhere in root's assembly.
static func drop(root: Part, target: Part) -> bool:
	var socket: Socket = find_owning_socket(root, target)
	if socket == null:
		return false
	socket.occupant = null
	return true


## Bipartite matching (Kuhn's algorithm): can `manipulators` collectively
## satisfy `weapon.requires` (StringName capability -> count)? Each
## manipulator fills at most one required slot, and only if it actually has
## that capability. Plain per-capability summation is NOT sufficient: a
## single versatile hand with both TRIGGER and SUPPORT can't alone satisfy a
## two-handed {TRIGGER:1, SUPPORT:1} weapon — that needs two limbs, one per
## role — which is exactly what the matching enforces.
static func can_operate(weapon: Part, manipulators: Array[Part]) -> bool:
	var slots: Array[StringName] = []
	for cap: StringName in weapon.requires:
		var count: int = int(weapon.requires[cap])
		for i in range(count):
			slots.append(cap)

	var match_for_manipulator: Array[int] = []
	match_for_manipulator.resize(manipulators.size())
	match_for_manipulator.fill(-1)

	for slot_index in range(slots.size()):
		var visited: Array[bool] = []
		visited.resize(manipulators.size())
		visited.fill(false)
		if not _augment(slot_index, slots, manipulators, match_for_manipulator, visited):
			return false
	return true


static func _augment(
	slot_index: int,
	slots: Array[StringName],
	manipulators: Array[Part],
	match_for_manipulator: Array[int],
	visited: Array[bool]
) -> bool:
	for m in range(manipulators.size()):
		if visited[m]:
			continue
		if not manipulators[m].capabilities.has(slots[slot_index]):
			continue
		visited[m] = true
		var reassignable: bool = (
			match_for_manipulator[m] == -1
			or _augment(
				match_for_manipulator[m], slots, manipulators, match_for_manipulator, visited
			)
		)
		if reassignable:
			match_for_manipulator[m] = slot_index
			return true
	return false
