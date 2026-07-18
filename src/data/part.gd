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

## Open vocabulary: VOLATILE (a descriptor now — taskblock-09 A3 moved the
## actual trigger to `failure_mode == DETONATE`), ORGANIC, SALVAGE, INERT
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

## taskblock-09 A0: what happens when this part reaches 0 HP is the
## part's OWN business, declared in data — never inferred from a closed
## `part_type`. Open StringName (CLAUDE.md: "open vocabularies for
## content"), one of MANGLE / DISABLE / DETONATE / FRAGMENT / MELTDOWN
## (docs/03). Never stacked — a part has exactly one failure_mode, not
## "MANGLE and then DISABLE." MANGLE is the default: it's the case v1
## already had (`mangles_into` below), the "dumb parts" case.
@export var failure_mode: StringName = &"MANGLE"
## Runtime — true once this part has actually failed under MANGLE
## (taskblock-09 A1). A mangled part stays FULLY ATTACHED: its sockets
## stay live/hittable, `stat_mods` stop applying (Shell.living_parts()'s
## own hp>0 filter already handles that), and DamageResolver reads a
## quarter of its resolved DT instead of the full value — an
## already-damaged heavy shell still shrugs off small arms, it isn't
## simply gone. Never a second "is destroyed" flag layered on hp<=0; this
## is specifically "is it mangled" (the wreckage look/reduced-DT state),
## nothing else reads it as a general destroyed check.
@export var is_mangled: bool = false
## Runtime — true once this part has actually failed under DISABLE
## (taskblock-09 A2). A disabled part stays attached, contributes no
## stat_mods and no actions (living_parts()'s hp>0 filter already excludes
## it from both), a weapon on it can't fire, a container on it can't be
## accessed — dead weight that still occupies its socket and still
## occludes shots as geometry.
@export var is_disabled: bool = false

## taskblock-09 A4: MELTDOWN's own countdown length in turns before a
## failed reactor DETONATEs on its own — 0 (the default) means a MELTDOWN
## part behaves like an instant DETONATE (no countdown authored).
@export var meltdown_turns: int = 0
## Runtime: -1 = not counting down; >=0 = turns left before this part
## DETONATEs on its own, ticked once per the OWNING UNIT's own turn start
## (CombatState._start_turn, the same seam LifeSupport.tick already uses).
## If the part is destroyed again while counting down, it detonates now
## rather than waiting out the rest of the clock (taskblock-09 A4).
@export var meltdown_countdown: int = -1

## taskblock-09 A4: FRAGMENT's own K and per-fragment damage — how many
## projectiles a failure_mode == FRAGMENT part spawns, in even directions,
## when it fails, and how much damage each one carries. Both default to 0
## (inert), same posture as detonate_damage/radius below — authored data,
## never a code constant. taskblock-10 replaces the even-direction spread
## with real ammo/spread machinery; until then, "K rays in even
## directions" is the taskblock's own stated placeholder.
@export var fragment_count: int = 0
@export var fragment_damage: float = 0.0

## taskblock-09 A3: DETONATE (docs/03) — renamed from "cook-off," same
## mechanic, folded into the failure_mode dispatch instead of being gated
## by the VOLATILE tag directly. A failure_mode == DETONATE part with a
## non-zero detonate_damage explodes on failure: area damage within
## detonate_radius cells. Both default to 0 (inert) — an ammo rack's own
## numbers are authored data. VOLATILE may still DESCRIBE a part (tags
## are open vocabulary) but no longer GATES this; failure_mode is the
## trigger now.
@export var detonate_damage: float = 0.0
@export var detonate_radius: float = 0.0

## taskblock-09 C0: the HP of THIS part's OWN attachment to its parent —
## authored on the CHILD, never the parent/socket, the same inversion
## `attaches_to` already uses (docs/01: "the arm carries the info"). A
## battle-bot arm is hard to sever on ANY frame it plugs into; a worker
## arm is easy even on a heavy frame. Copied onto the hosting `Socket`'s
## own runtime `joint_hp`/`joint_hp_max` at attach time (PartGraph.attach)
## — the socket holds the RUNTIME value, the child defines the MAX. 1 is a
## flagged, deliberately fragile default (every un-migrated part severs in
## one hit) rather than an invented "tough" number.
@export var joint_hp: int = 1

## taskblock-09 F: the DT discount this weapon's payload carries —
## penetration only, never touches the deflect/stop-dead angle decision
## (docs/03: deflection is geometry, not energy). Can be negative (a
## shotgun's buckshot, say) — armor gets HARDER to beat, not easier. 0.0
## (no discount) is the default. taskblock-10 moves this onto AmmoDef
## (`bonus_pen`); until it lands, it's a weapon-level placeholder, the
## same status `damage` already has (Pass G) — read through WeaponResolver
## like every other weapon-derived number, never this field directly.
@export var bonus_pen: float = 0.0

## docs/10 taskblock05 E1: what this part becomes on destruction under
## MANGLE — a StringName id into FieldObjects.wreckage_pool(), purely a
## VISUAL/SALVAGE swap now (taskblock-09 A1), never a detachment: a
## mangled part with this set still looks/salvages like its wreckage
## identity, but stays exactly where it was, attached, sockets live. Empty
## means no cosmetic swap — the part just stays itself, visually
## unchanged, `is_mangled` alone marking that it failed.
@export var mangles_into: StringName = &""

## Weapon stats (docs/02, Phase 4) — a weapon is just a Part whose
## `requires` names the manipulator capabilities it needs to fire (already
## exercised by PartGraph.can_operate in Phase 1). Not `range`: that shadows
## the builtin range() function.
##
## taskblock-09 Pass G: `damage` is a flagged, deliberate leftover, not a
## silently-kept duplicate. Weapon damage belongs on AMMO (taskblock-10's
## `AmmoDef.damage`) once that model lands — the gun itself only ever
## multiplies it (`damage_multiplier`). Until taskblock-10 replaces this
## field's role, it stays the one weapon-level damage source (read only
## through WeaponResolver, docs/08 — never directly), same placeholder
## status `bonus_pen` above already carries. Do not add a second damage
## source alongside it; when taskblock-10 lands, this field's job moves,
## it doesn't duplicate.
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
