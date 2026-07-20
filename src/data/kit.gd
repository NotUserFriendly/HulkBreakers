class_name Kit
extends Resource

## taskblock-28 Pass B: what a preset's own units start CARRYING (in an
## already-existing body container) and how that becomes "armed" once
## equip runs — "a bout starts by units equipping themselves from their
## kit," so a bout is self-arming, not hand-set. Sits next to
## `BotPreset.loadout` (structural fill, resolved at ASSEMBLY time) as
## `BotPreset.kit` (optional; null — the default every pre-existing preset
## keeps — means "no kit, already armed via `loadout` the old way,"
## unchanged behavior): `loadout` answers "what shape is this body,"
## `kit` answers "what's it carrying, and how does that reach its hands."
##
## Reuses `Inventory`'s own container-tree ops to stock the gear and
## `PartGraph`'s own socket ops to equip the weapon — no parallel
## attach/detach path (CLAUDE.md: "no parallel systems").

## Which already-existing container socket on the assembled body this
## kit's own gear fills (e.g. &"BACK", holding an `ammo_rack` the
## template already mounts) — a kit only ever FILLS a container, never
## attaches one of its own.
@export var container_socket_id: StringName = &""

## Every item this kit stores in that container, by pool part id — the
## weapon plus whatever else it carries. Open data: a designer authors a
## new kit by listing ids here, no code.
@export var stored_item_ids: Array[StringName] = []

## The weapon this kit equips at bout setup — must also appear in
## `stored_item_ids` (the weapon genuinely starts IN the kit; equip PULLS
## it out into the hand, it never spawns a second copy).
@export var weapon_part_id: StringName = &""

## Which grip socket (already on the body, e.g. &"GRIP_R") the weapon
## equips into — left bare by the preset's own `loadout` on purpose, so
## equip is the only thing that ever fills it.
@export var weapon_socket_id: StringName = &""

## AmmoDef id chambered into the weapon once equipped — "" (the default)
## chambers nothing.
@export var chambered_ammo_id: StringName = &""


func _init(
	p_container_socket_id: StringName = &"",
	p_stored_item_ids: Array[StringName] = [],
	p_weapon_part_id: StringName = &"",
	p_weapon_socket_id: StringName = &"",
	p_chambered_ammo_id: StringName = &""
) -> void:
	container_socket_id = p_container_socket_id
	stored_item_ids = p_stored_item_ids
	weapon_part_id = p_weapon_part_id
	weapon_socket_id = p_weapon_socket_id
	chambered_ammo_id = p_chambered_ammo_id
