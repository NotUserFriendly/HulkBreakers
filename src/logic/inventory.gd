class_name Inventory
extends RefCounted

## Container-tree ops on Part.contents (docs/05/Appendix D). Part has no
## parent back-reference, so detach()/attach() take the container explicitly
## (`detach(part, from)`, `attach(part, into)`). Distinct from PartGraph,
## which operates on the structural socket tree — sockets and contents are
## different relationships.


## True if `part` could be attached into `into` right now: `into` must be a
## container, attaching must not create a cycle, must not exceed `into`'s
## max_bulk (by direct children's external bulk), and — when `frame` is
## given — must not push the frame over max_mass (Frame.carried_mass()).
static func can_attach(part: Part, into: Part, frame: Frame = null) -> bool:
	if not into.is_container:
		return false
	if walk(part).has(into):
		return false  # into is part itself, or already nested inside part — would cycle

	var direct_bulk: float = 0.0
	for child: Part in into.contents:
		direct_bulk += child.bulk
	if direct_bulk + part.bulk > into.max_bulk:
		return false

	if frame != null:
		into.contents.append(part)
		var mass_ok: bool = frame.carried_mass() <= frame.max_mass
		into.contents.erase(part)
		if not mass_ok:
			return false

	return true


static func attach(part: Part, into: Part, frame: Frame = null) -> bool:
	if not can_attach(part, into, frame):
		return false
	into.contents.append(part)
	return true


static func detach(part: Part, from: Part) -> bool:
	if not from.contents.has(part):
		return false
	from.contents.erase(part)
	return true


## Depth-first traversal of the subtree rooted at `root`, root included.
static func walk(root: Part) -> Array[Part]:
	var result: Array[Part] = [root]
	for child: Part in root.contents:
		result.append_array(walk(child))
	return result


## Every part nested inside `root` at any depth, root excluded.
static func flatten(root: Part) -> Array[Part]:
	var result: Array[Part] = []
	for child: Part in root.contents:
		result.append_array(walk(child))
	return result
