class_name Frame
extends Resource

## Replaces v1's Chassis. Instead of a flat slots Dictionary, a Frame is a
## single `root` Part with the whole body assembled through its socket tree
## (docs/01/PartGraph). Sockets (structural) and contents (inventory) are
## different relationships — Frame only concerns the structural tree;
## Inventory still owns `contents`.

@export var root: Part
@export var max_mass: float = 0.0
@export var max_ram: float = 0.0


func _init(p_root: Part = null) -> void:
	root = p_root


## Every part in the whole assembly, root included.
func all_parts() -> Array[Part]:
	if root == null:
		return []
	return PartGraph.walk(root)


func living_parts() -> Array[Part]:
	var result: Array[Part] = []
	for part: Part in all_parts():
		if part.hp > 0:
			result.append(part)
	return result


## The first part in this assembly whose id matches — actions resolve a
## targeted part this way rather than holding a bare Part reference across
## states (docs/09): a preview's frame is an independent clone. Assumes a
## single frame doesn't carry two parts sharing the same id, a reasonable
## bound for one loadout.
func find_part(part_id: StringName) -> Part:
	for part: Part in all_parts():
		if part.id == part_id:
			return part
	return null


## Recursive felt mass (Appendix D / docs/05): a container's mass_multiplier
## discount applies once, only at the directly-worn layer, across the whole
## assembly (not just root-level attachments — a pistol in a hand three
## joints down still contributes its mass).
func carried_mass() -> float:
	var total := 0.0
	for part: Part in all_parts():
		total += part.mass
		if part.is_container:
			total += _flat_contents(part) * part.mass_multiplier
	return total


func _flat_contents(container: Part) -> float:
	var total := 0.0
	for child: Part in container.contents:
		total += child.mass
		if child.is_container:
			total += _flat_contents(child)
	return total


## A fully independent copy of the whole assembly, for TACTICS-time
## speculative previews (docs/09) — Part.duplicate(true) recurses through
## sockets/contents/hosted_matrix, so no shared Part is ever mutated by a
## preview that turns out to fire a weapon or take damage.
func dup() -> Frame:
	var cloned := Frame.new(root.duplicate(true) as Part if root != null else null)
	cloned.max_mass = max_mass
	cloned.max_ram = max_ram
	return cloned
