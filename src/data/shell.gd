class_name Shell
extends Resource

## Replaces v1's Chassis. Instead of a flat slots Dictionary, a Shell is a
## single `root` Part with the whole body assembled through its socket tree
## (docs/01/PartGraph). Sockets (structural) and contents (inventory) are
## different relationships — Shell only concerns the structural tree;
## Inventory still owns `contents`.

## docs/05 taskblock04 D1: "anything body-attached is discounted to at
## least 0.8. Wearing it beats dragging it, always." A ceiling on the
## multiplier `carried_mass()` actually applies, not a floor on the
## authored number: a container with a MORE generous own multiplier (a
## backpack's 0.5) still uses its own, better, value — this only rescues a
## body-attached container that forgot to author one at all (the default
## mass_multiplier, 1.0, would otherwise mean literally no discount for
## something worn, contradicting "wearing it beats dragging it, always").
const WORN_DISCOUNT_CEILING := 0.8

@export var root: Part
@export var max_mass: float = 0.0
@export var max_ram: float = 0.0
## taskblock-25 Pass A: how far this shell's torso can lean to close melee
## distance beyond a weapon's own free `weapon_length` — the exposure
## budget (docs/PLAN.md "Phase M — Melee"). 0.0 (default) means this shell
## can't lean at all; every existing shell keeps its current (no melee)
## behavior unchanged until authored otherwise. See `MeleeReach`.
@export var shell_reach: float = 0.0


func _init(p_root: Part = null) -> void:
	root = p_root


## Every part in the whole assembly, root included.
func all_parts() -> Array[Part]:
	if root == null:
		return []
	return PartGraph.walk(root)


## BR36.01: `all_parts()` plus every occupied socket's own synthetic
## `joint_handle()` — the identity a shot-plane self-exclusion list needs
## ("every region this body could produce"), never what `living_parts()`/
## `carried_mass()`/`find_part()`/every other `all_parts()` consumer wants
## (see `PartGraph.walk_with_joints`'s own doc comment for why those must
## stay joint-free). The one caller this exists for: a shooter's own
## self-obstruction/self-exclusion list.
func all_parts_with_joints() -> Array[Part]:
	if root == null:
		return []
	return PartGraph.walk_with_joints(root)


func living_parts() -> Array[Part]:
	var result: Array[Part] = []
	for part: Part in all_parts():
		if part.hp > 0:
			result.append(part)
	return result


## taskblock-20 Pass D: `living_parts()` further filtered by
## `WoundEffects.is_disabled_by_wounds` — a wound-disabled part (
## `severed_controls`' "limb inert but pristine") stays hp > 0 and stays in
## `living_parts()` (it isn't destroyed — a unit whose every part is
## wound-disabled is NOT dead, unlike a unit whose every part is destroyed),
## but must stop counting as a usable manipulator/weapon or a resolver-side
## modifier source. Every capability gate (AttackAction/BurstAction/
## OverwatchAction manipulator lists, WeaponRows, StatResolver's own
## context.parts) reads this instead of `living_parts()` directly; anything
## that only cares "is this unit still structurally alive" (a kill check)
## keeps reading `living_parts()`.
func operable_parts() -> Array[Part]:
	var result: Array[Part] = []
	for part: Part in living_parts():
		if not WoundEffects.is_disabled_by_wounds(part):
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
			var effective_multiplier: float = minf(part.mass_multiplier, WORN_DISCOUNT_CEILING)
			total += _flat_contents(part) * effective_multiplier
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
	cloned.shell_reach = shell_reach
	return cloned
