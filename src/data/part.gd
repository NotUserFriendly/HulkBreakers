class_name Part
extends Resource

## The unit of the socket graph (docs/01). Attachment is inverted: a part
## declares which socket types it fits (`attaches_to`); a socket just holds a
## type tag and an occupant. No parent-specific code is ever needed —
## `attaches_to: [SHOULDER]` mounts on any shoulder, on anything.
##
## Categorization is open data, not closed enums: `capabilities` (what a
## manipulator can do — TRIGGER/SUPPORT/GRIP/POWER, ...) and `tags` (open
## flags — VOLATILE/ORGANIC/SALVAGE/INERT, ...) replace v1's SlotType/PartType
## enums entirely.

@export var id: StringName
@export var display_name: String = ""

## What socket types this part can occupy when attached elsewhere.
@export var attaches_to: Array[StringName] = []
## Sockets this part itself hosts, for other parts to attach into.
@export var sockets: Array[Socket] = []

## What this part can do as a manipulator (TRIGGER, SUPPORT, GRIP, POWER, ...).
@export var capabilities: Array[StringName] = []
## For a weapon/tool: StringName capability -> count needed to operate it.
## An empty dict means "no manipulator requirements" (e.g. armor plate).
@export var requires: Dictionary = {}

## Key into the material table -> DT (Phase 5). Open StringName, not an enum.
@export var material: StringName = &""
## Body-space geometry — one or more boxes in this PART's own local space,
## not the unit's (docs/02/10, Phase 12.0). Where it actually sits on the
## body comes from whatever socket hosts this part, composed by
## BodyProjector down the tree. Not container capacity; see `bulk` for that
## (docs/05 naming note).
@export var volume: Array[Box] = []

@export var hp: int = 1
@export var max_hp: int = 1
@export var mass: float = 0.0
## This part's own external size, checked against a container's max_bulk.
@export var bulk: float = 0.0
@export var ram_cost: float = 0.0
@export var stat_mods: Dictionary = {}

## Inventory (docs/05) — a distinct relationship from `sockets`/`attaches_to`.
## A backpack is socket-attached to a BACK socket and separately contains items.
@export var is_container: bool = false
@export var max_bulk: float = 0.0
@export var mass_multiplier: float = 1.0
@export var contents: Array[Part] = []

## `hosted_matrix` is the Matrix currently seated in this part's MATRIX
## socket, if any. Whether one exists at all is derived from `sockets` via
## `hosts_matrix()`, below — never set directly. Only torso and head
## templates declare a MATRIX socket today (docs/01); an arm can never
## host a matrix.
@export var hosted_matrix: Matrix = null

## docs/04 taskblock02 Pass D: set only on a surrogate Part itself — the
## `SurrogateTier.id` (e.g. `&"SPINAL"`) this specific organic body IS.
## Empty for every non-surrogate part. `attaches_to` for a surrogate is
## DERIVED from this against the ladder (SurrogateLadder.derive_attaches_to)
## — the author writes this one field, never a hand-picked socket list.
@export var surrogate_tier: StringName = &""

## docs/04 taskblock02 Pass D3: open capability tags this part needs FROM
## THE DOCKED SURROGATE to actually function — distinct from `requires`
## above, which is about manipulator PARTS (a hand's TRIGGER), not the
## pilot's own body. A part whose `body_requires` isn't a subset of the
## docked surrogate's own `SurrogateTier.capabilities` is inert: present,
## carried, massed, shootable, but unusable — never an error. Empty means
## "needs nothing from the body" (most parts). Vocabulary intentionally
## thin (docs/04: "do not invent the capability vocabulary... ask") — only
## `LOCOMOTION` is authored so far, for the one mechanic that needs it.
@export var body_requires: Array[StringName] = []

## Open vocabulary: VOLATILE (cooks off, Phase 5), ORGANIC, SALVAGE, INERT
## (a carried body, docs/05), POWER_SOURCE (Shell.is_powered(), docs/04
## taskblock02 Pass D4), ORGANICS (a lootable ration Shell.consume_organics
## looks for) ...
@export var tags: Array[StringName] = []

## docs/07: empty for most items — the same design bought from a merchant
## or found on a hulk is a plain, undifferentiated item. A handful of
## designs deliberately overlap between the two loot pools; on those,
## LootTable sets this to distinguish "standard" (merchant) from
## "original_pattern" / "prototype" (hulk) — minor but visible, not a
## separate stat-rolled item (that's backlog, docs/99).
@export var variant_tag: StringName = &""

## False marks permanent terrain (e.g. cover that can never be destroyed,
## docs/02).
@export var is_destructible: bool = true

## Weapon stats (docs/02, Phase 4) — a weapon is just a Part whose
## `requires` names the manipulator capabilities it needs to fire (already
## exercised by PartGraph.can_operate in Phase 1). Not `range`: that shadows
## the builtin range() function.
@export var damage: float = 0.0
@export var burst: int = 1
@export var recoil: float = 0.0
@export var weapon_max_range: float = 0.0
@export var ap_cost: int = 1
## Float, not a bool (docs/03): >1.0 always crits, and the excess is the
## double-crit chance. 0.0 (never crits) is the inert default.
@export var crit_chance: float = 0.0
## Ordered inner -> outer; each Ring's radius is its own outer edge, so ring
## i's annulus spans (scatter[i-1].radius, scatter[i].radius]. N rings, never
## a fixed three — nothing may assume a count.
@export var scatter: Array[Ring] = []

## Cook-off (docs/03): a VOLATILE part with a non-zero cook_off_damage
## explodes on destruction, dealing this much area damage within
## cook_off_radius cells. Both default to 0 (inert) — an ammo rack's actual
## numbers are authored data, not a code constant.
@export var cook_off_damage: float = 0.0
@export var cook_off_radius: float = 0.0


## True if this part declares a MATRIX socket — the only thing that makes a
## part pilotable (docs/01). Derived from `sockets`, never a settable flag.
func hosts_matrix() -> bool:
	for socket: Socket in sockets:
		if socket.socket_type == &"MATRIX":
			return true
	return false


## Docks `matrix` into this part's MATRIX socket. Fails (returns false,
## `hosted_matrix` untouched) if this part has no MATRIX socket or is
## already hosting one — the only legal way to set `hosted_matrix`.
func dock_matrix(matrix: Matrix) -> bool:
	if not hosts_matrix() or hosted_matrix != null:
		return false
	hosted_matrix = matrix
	return true
