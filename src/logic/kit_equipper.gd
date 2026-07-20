class_name KitEquipper
extends RefCounted

## taskblock-28 Pass B: "a bout starts by units equipping themselves from
## their kit" — reuses `Inventory` (contents tree) to stock a `Kit`'s own
## gear into a body's already-existing container, then `PartGraph`
## (socket tree) to pull the weapon out into its hand and chamber its
## ammo. No parallel attach/detach path (CLAUDE.md: "no parallel
## systems") — every mutation here is the same `Inventory.attach`/
## `Inventory.detach`/`PartGraph.attach` any other inventory/assembly
## operation already uses.
##
## `stock` and `equip` are deliberately separate calls, not one — the
## seam a future VISIBLE equip mode (units physically walking their own
## gear from container to hand across real turns) needs: stocking always
## happens once, up front; a caller can re-run/step `equip` differently
## per mode without re-deriving what's in the container.


## Fills `kit`'s own `container_socket_id` with fresh copies of every
## `stored_item_ids` entry, drawn from `pool`. A no-op (never an error) for
## `kit == null` — "no kit" is a legitimate, unchanged posture, not a
## malformed one. Returns false (named `push_error`, nothing partially
## applied left ambiguous) on a genuinely malformed kit: an unknown
## container socket, a non-container occupant, an unknown pool id, or an
## item that doesn't fit — the same "never crash, never silently invent"
## posture `BodyAssembler` already holds.
static func stock(unit: Unit, kit: Kit, pool: Dictionary) -> bool:
	if kit == null:
		return true
	var container: Part = _container(unit, kit)
	if container == null or not container.is_container:
		push_error(
			"KitEquipper: %s has no container socket %s to stock"
			% [unit.shell.root.id, kit.container_socket_id]
		)
		return false
	for item_id: StringName in kit.stored_item_ids:
		var item_template: Part = pool.get(item_id)
		if item_template == null:
			push_error("KitEquipper: unknown pool part id %s" % item_id)
			return false
		if not Inventory.attach(item_template.duplicate(true), container, unit.shell):
			push_error(
				"KitEquipper: %s does not fit in its own kit container %s"
				% [item_id, container.id]
			)
			return false
	return true


## Moves `kit`'s own `weapon_part_id` out of its container and into
## `weapon_socket_id`, then chambers `chambered_ammo_id` if authored —
## `equip_mode` is the toggle seam (taskblock-28 Pass B: "lay the
## framework, no behavior behind it") every future equip path reads;
## only `INSTANT` has real behavior so far. A no-op for `kit == null`.
static func equip(
	unit: Unit, kit: Kit, equip_mode: Enums.EquipMode = Enums.EquipMode.INSTANT
) -> bool:
	if kit == null:
		return true
	match equip_mode:
		Enums.EquipMode.INSTANT:
			return _equip_instant(unit, kit)
		_:
			push_error("KitEquipper: equip_mode %s has no implementation yet" % equip_mode)
			return false


static func _equip_instant(unit: Unit, kit: Kit) -> bool:
	if kit.weapon_part_id == &"":
		return true

	var container: Part = _container(unit, kit)
	if container == null:
		push_error(
			"KitEquipper: %s has no container socket %s to equip from"
			% [unit.shell.root.id, kit.container_socket_id]
		)
		return false
	var weapon: Part = null
	for item: Part in container.contents:
		if item.id == kit.weapon_part_id:
			weapon = item
			break
	if weapon == null:
		push_error(
			"KitEquipper: %s never made it into its own kit container %s"
			% [kit.weapon_part_id, container.id]
		)
		return false

	var host: Part = PartGraph.find_host_of_socket(unit.shell.root, kit.weapon_socket_id)
	if host == null:
		push_error("KitEquipper: no socket id %s to equip into" % kit.weapon_socket_id)
		return false
	var socket: Socket = PartGraph.find_socket(host, kit.weapon_socket_id)

	if not Inventory.detach(weapon, container):
		return false
	if not PartGraph.attach(weapon, host, socket):
		# Put it back rather than leave it floating loose in neither place —
		# a failed equip must never silently drop the unit's own gear.
		Inventory.attach(weapon, container)
		push_error(
			"KitEquipper: %s cannot attach to socket %s on %s"
			% [weapon.id, kit.weapon_socket_id, host.id]
		)
		return false

	if kit.chambered_ammo_id != &"":
		var ammo: AmmoDef = DataLibrary.get_ammo(kit.chambered_ammo_id)
		if ammo == null:
			push_error("KitEquipper: unknown ammo id %s" % kit.chambered_ammo_id)
		else:
			var chamber_error: String = WeaponResolver.try_chamber(weapon, ammo)
			if chamber_error != "":
				push_error("KitEquipper: %s" % chamber_error)

	return true


static func _container(unit: Unit, kit: Kit) -> Part:
	if kit.container_socket_id == &"":
		return null
	var host: Part = PartGraph.find_host_of_socket(unit.shell.root, kit.container_socket_id)
	if host == null:
		return null
	return PartGraph.find_socket(host, kit.container_socket_id).occupant
