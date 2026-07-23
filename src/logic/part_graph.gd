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
## subtree). taskblock-09 C0: also copies `part.joint_hp` onto the socket's
## own runtime `joint_hp`/`joint_hp_max` — the child defines the max, the
## socket holds the current value, same inversion `attaches_to` already
## uses.
static func attach(part: Part, target: Part, socket: Socket) -> bool:
	if not target.sockets.has(socket):
		return false
	if not is_legal_attachment(part, socket):
		return false
	if walk(part).has(target):
		return false
	socket.occupant = part
	socket.joint_hp = part.joint_hp
	socket.joint_hp_max = part.joint_hp
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


## BR36.01: every real Part `walk` would return, PLUS every occupied
## socket's own `joint_handle()` — the synthetic identity
## `BodyProjector._project_joint` tags a joint Region with (tb09 D), never a
## real member of the socket tree `walk` traverses. A caller building "every
## region this body could produce" (self-obstruction/self-exclusion lists —
## `ShotPlane.self_obstruction`/`resolve_shot`'s own `exclude_parts`) needs
## joints included too, or the shooter's own joint regions are never
## excluded and a shot can resolve to the shooter's own body at near-zero
## depth. Deliberately its OWN method rather than a change to `walk` itself
## (`walk`'s many structural callers — `attach`'s cycle check,
## `find_host_of_socket`, `find_owning_socket`, `drop` — never expect a
## synthetic non-tree Part) or to `Shell.all_parts()` (every OTHER consumer
## of that — `living_parts()`'s hp>0 filter chief among them — would
## silently pick up a joint handle's own immutable default hp=1, making a
## unit's joint regions read as permanently-living parts and breaking every
## `living_parts().is_empty()` kill check in the game).
static func walk_with_joints(root: Part) -> Array[Part]:
	var result: Array[Part] = [root]
	for socket: Socket in root.sockets:
		if socket.occupant != null:
			result.append(socket.joint_handle())
			result.append_array(walk_with_joints(socket.occupant))
	return result


## The part ANYWHERE in root's own assembly (root included) whose own
## `sockets` include one with this `id` — the recursive counterpart to
## `find_socket` (which only ever looks at `target`'s own sockets, never
## the whole tree). taskblock-28 Pass B: how `KitEquipper` locates a kit's
## own named container/grip socket without the caller having to know
## which part actually hosts it. Distinct from `find_owning_socket` below
## (that finds who holds a given PART; this finds who holds a given
## SOCKET id) — order-independent, same posture as `find_socket` itself.
static func find_host_of_socket(root: Part, socket_id: StringName) -> Part:
	for part: Part in walk(root):
		for socket: Socket in part.sockets:
			if socket.id == socket_id:
				return part
	return null


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
