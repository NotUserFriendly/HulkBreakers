class_name Inventory
extends RefCounted

## Container-tree ops on Part.contents (Appendix D). Part has no parent
## back-reference, so detach()/attach() take the container explicitly
## (`detach(part, from)`, `attach(part, into)`) rather than PLAN.md's bare
## `detach(part)`.


## True if `part` could be attached into `into` right now: `into` must be a
## container, attaching must not create a cycle, must not exceed `into`'s
## max_volume (by direct children's external volume), and — when `chassis`
## is given — must not push the chassis over max_mass (Chassis.carried_mass()).
static func can_attach(part: Part, into: Part, chassis: Chassis = null) -> bool:
	if not into.is_container:
		return false
	if walk(part).has(into):
		return false  # into is part itself, or already nested inside part — would cycle

	var direct_volume: float = 0.0
	for child: Part in into.contents:
		direct_volume += child.volume
	if direct_volume + part.volume > into.max_volume:
		return false

	if chassis != null:
		into.contents.append(part)
		var mass_ok: bool = chassis.carried_mass() <= chassis.max_mass
		into.contents.erase(part)
		if not mass_ok:
			return false

	return true


static func attach(part: Part, into: Part, chassis: Chassis = null) -> bool:
	if not can_attach(part, into, chassis):
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
