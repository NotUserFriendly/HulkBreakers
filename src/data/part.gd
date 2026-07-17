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
## docs/09 taskblock06 Pass I2: "commissioned art" — an optional rigged
## scene HitVolumeView renders IN PLACE of this part's own box meshes,
## positioned at the same composed transform a box would use. Never read
## by anything that resolves a shot: BodyProjector/ShotPlane/UnitGeometry
## all still work from `volume` alone, so a part's own hit volume is
## identical whether or not it has a commissioned mesh (docs/09: "the mesh
## must never affect resolution"). Null (the default) means every part
## authored before this field existed keeps rendering its boxes exactly as
## before — no cutover, no big-bang migration (docs/09 Pass I2: "mixed
## assemblies are legal").
@export var mesh_scene: PackedScene = null

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
## docs/05 taskblock04 D2: whether this container's own external bulk (what
## it costs a PARENT container to hold it — see Inventory.external_bulk())
## is a fixed size regardless of contents (true — a barrel is 110L whether
## empty or full) or swells with what's actually inside it (false — a soft
## backpack packed light barely takes up room). Defaults true: every
## container authored before this field existed already behaved as fixed
## size (`bulk` read directly, nothing ever swelled it), so the default
## preserves that with no behavior change.
@export var rigid: bool = true

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

## taskblock-07 Pass E1: open StringName ids this part contributes to the
## action bar (`&"shoot"`, `&"saw"`, ...) — declared per part, in data,
## never derived from any closed `part_type` ("`if part_type == WEAPON`" is
## code knowing about content; repetition in a data row is the cheap
## kind). E3: guns temporarily also list `&"overwatch"` — a PLACEHOLDER;
## its real provider is a matrix perk (`Matrix.provides_actions()`), not
## the gun. Moving it off this array and onto a perk's own array later is a
## data edit, not a code edit — see `ActionCatalog.actions_for`.
@export var provides_actions: Array[StringName] = []

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

## docs/10 taskblock04 C3: StringName resource id (docs/05's seven — organics
## / minerals / metals / ceramics / electronics / fuel / reactives) -> amount
## awarded when this part is cut apart or destroyed. Empty for anything
## that isn't meant to be harvested (most parts) — this is what a field
## object (a scrap pile, a dropped assembly) has and an ordinary weapon or
## armor plate doesn't.
@export var salvage_yield: Dictionary = {}

## docs/10 taskblock05 E1: what this part becomes on destruction — a
## StringName id into FieldObjects.wreckage_pool(). Empty (the default)
## means it doesn't mangle: the part stays itself, broken (derived from
## hp <= 0, never a second flag), and its own subtree drops intact, rooted
## at it. Set (cladding, plates, structure) means it's low-complexity
## enough to lose its identity entirely: on destruction it's REPLACED by
## the named wreckage, and its own children detach to drop as their own
## separate intact assemblies instead — the thing that held them became
## scrap, it can't hold anything.
@export var mangles_into: StringName = &""

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

## docs/09 taskblock06 Pass E: how fast an attack made with this weapon
## resolves relative to other actions at the same instant (HIGHER first)
## — AttackAction reads this off its own weapon at resolve time, so a
## fast weapon can out-speed an overwatch trigger with no code change.
## 40.0 (docs/09's own "attack / return fire" starting data) is a
## harmless default for every part, weapon or not — only ever read on
## whichever Part an AttackAction actually names as its weapon_id.
@export var speed: float = 40.0

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
