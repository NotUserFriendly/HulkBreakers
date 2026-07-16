class_name Inventory
extends RefCounted

## Container-tree ops on Part.contents (docs/05/Appendix D). Part has no
## parent back-reference, so detach()/attach() take the container explicitly
## (`detach(part, from)`, `attach(part, into)`). Distinct from PartGraph,
## which operates on the structural socket tree — sockets and contents are
## different relationships.


## docs/05 taskblock04 D2 amendment: "a nested container occupies its
## parent by its own external bulk — a packed bag is a fixed size" is now
## only true for a RIGID container. A soft one's external bulk swells with
## what's actually inside it — an empty soft backpack is nearly free to
## nest inside a barrel; a full one may not fit. Per-container bulk checks
## stay direct-children-only, non-composing: a soft container's own swell
## sums its direct contents' own `bulk`, never their own recursive
## external_bulk (that composing is reserved for whoever nests IT, one
## level up — see `can_attach` below).
static func external_bulk(part: Part) -> float:
	if part.rigid:
		return part.bulk
	var total: float = part.bulk
	for child: Part in part.contents:
		total += child.bulk
	return total


## True if `part` could be attached into `into` right now: `into` must be a
## container, attaching must not create a cycle, must not exceed `into`'s
## max_bulk (by direct children's own external bulk), and — when `shell` is
## given — must not push the shell over max_mass (Shell.carried_mass()) or
## max_ram (Shell.total_ram()). Three independent constraints (docs/05):
## mass, bulk, and RAM fail differently, which is the point — a weightless
## drone swarm can pass mass and still fail on RAM alone.
static func can_attach(part: Part, into: Part, shell: Shell = null) -> bool:
	if not into.is_container:
		return false
	if walk(part).has(into):
		return false  # into is part itself, or already nested inside part — would cycle

	var direct_bulk: float = 0.0
	for child: Part in into.contents:
		direct_bulk += external_bulk(child)
	if direct_bulk + external_bulk(part) > into.max_bulk:
		return false

	if shell != null:
		into.contents.append(part)
		var mass_ok: bool = shell.carried_mass() <= shell.max_mass
		var ram_ok: bool = shell.total_ram() <= shell.max_ram
		into.contents.erase(part)
		if not mass_ok or not ram_ok:
			return false

	return true


static func attach(part: Part, into: Part, shell: Shell = null) -> bool:
	if not can_attach(part, into, shell):
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
