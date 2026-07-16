class_name Shell
extends Resource

## Replaces v1's Chassis. Instead of a flat slots Dictionary, a Shell is a
## single `root` Part with the whole body assembled through its socket tree
## (docs/01/PartGraph). Sockets (structural) and contents (inventory) are
## different relationships — Shell only concerns the structural tree;
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


## docs/04 taskblock02 Pass D4: true if any living part is tagged
## `POWER_SOURCE` (the pool's `reactor`, e.g.) — the hook life support
## checks before a docked surrogate can hold or regenerate instead of
## decaying. Shooting out the one part that carries this tag stops regen
## at the same instant it (if also `VOLATILE`) cooks off — one tag, two
## consequences, not two separate systems to keep in sync.
func is_powered() -> bool:
	for part: Part in living_parts():
		if &"POWER_SOURCE" in part.tags:
			return true
	return false


## True if some `ORGANICS`-tagged item sits in any container this assembly
## carries (docs/05 containers; docs/04 taskblock02 Pass D4 life support's
## regen fuel) — not recursive into nested containers-within-containers,
## matching `find_part`'s own "reasonable bound for one loadout" scope.
func has_organics() -> bool:
	return _find_organics_container() != null


## Removes and returns the first `ORGANICS`-tagged item found, or null if
## none — life support's regen consumes exactly one per tick (docs/04:
## "hauling food is now a live trade against bulk and mass").
func consume_organics() -> Part:
	var container: Part = _find_organics_container()
	if container == null:
		return null
	for item: Part in container.contents:
		if &"ORGANICS" in item.tags:
			container.contents.erase(item)
			return item
	return null


func _find_organics_container() -> Part:
	for part: Part in all_parts():
		if not part.is_container:
			continue
		for item: Part in part.contents:
			if &"ORGANICS" in item.tags:
				return part
	return null


## The first part in this assembly whose id matches — actions resolve a
## targeted part this way rather than holding a bare Part reference across
## states (docs/09): a preview's shell is an independent clone. Assumes a
## single shell doesn't carry two parts sharing the same id, a reasonable
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


## Sum of every part's ram_cost (docs/05) — systems control, checked
## against max_ram the same way carried_mass() is checked against max_mass.
## Unlike mass, nothing discounts RAM for being carried in a container —
## controlling an external thing doesn't get cheaper by bagging it — so
## contents are summed flat with no mass_multiplier-style factor.
func total_ram() -> float:
	var total := 0.0
	for part: Part in all_parts():
		total += part.ram_cost
		if part.is_container:
			total += _flat_ram(part)
	return total


func _flat_ram(container: Part) -> float:
	var total := 0.0
	for child: Part in container.contents:
		total += child.ram_cost
		if child.is_container:
			total += _flat_ram(child)
	return total


## A fully independent copy of the whole assembly, for TACTICS-time
## speculative previews (docs/09) — Part.duplicate(true) recurses through
## sockets/contents/hosted_matrix, so no shared Part is ever mutated by a
## preview that turns out to fire a weapon or take damage.
func dup() -> Shell:
	var cloned := Shell.new(root.duplicate(true) as Part if root != null else null)
	cloned.max_mass = max_mass
	cloned.max_ram = max_ram
	return cloned
