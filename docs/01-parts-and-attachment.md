# 01 — Parts & Attachment

## The inversion (read this first)
Attachment is **declared by the part, matched by the socket type** — never keyed to a
specific parent.

```
Socket: { socket_type: StringName, occupant: Part }      # lives ON a part
Part:   { attaches_to: Array[StringName], sockets: Array[Socket], ... }

legal(part, socket) := socket.socket_type in part.attaches_to and socket.occupant == null
```

Consequences that must hold, and are the point of the design:
- A torso with **12 sockets of type `SHOULDER` can host 12 arms.** No per-parent keying.
- A **Gravlance** tagged `attaches_to: [SHOULDER]` mounts anywhere a shoulder exists — a
  mech, a hauler, a turret. Nobody wrote a rule for that combination.
- Socket types are **open `StringName`s**, never an enum. New content must never need a code
  edit.

## Limbs decompose
An "arm" is not one part. Splitting it is what makes loadouts interesting.

```
TORSO
 └─ [SHOULDER] shoulder_assembly
     ├─ [SHOULDER_MOUNT] rocket_pod
     └─ [UPPER_ARM] upper_arm
         ├─ [ARMOR] upper_arm_plate
         └─ [FOREARM] forearm
             ├─ [FOREARM_TOOL] folding_sword
             ├─ [ARMOR] forearm_plate
             └─ [WRIST] hand
                 └─ [GRIP] pistol
```

A folding sword on the forearm does **not** block the upper-arm plate, which does **not**
block the shoulder rocket pod, and none of them stop the hand holding a pistol.

**Hand replacement is emergent, not special-cased.** A power drill has
`attaches_to: [WRIST]`, so it takes the socket the hand would use. It exposes no `GRIP`
socket. Therefore: no pistol. No rule was written to forbid it.

### Starter socket vocabulary (data, extend freely)
`CORE`, `SHOULDER`, `SHOULDER_MOUNT`, `UPPER_ARM`, `FOREARM`, `FOREARM_TOOL`, `WRIST`,
`GRIP`, `HIP`, `THIGH`, `SHIN`, `FOOT`, `HEAD`, `NECK`, `ARMOR`, `BACK`, `INTERNAL`,
`MATRIX`, `AMMO`, `CARGO`

## Capability tags — what a manipulator can actually do
A hand is not a boolean. Manipulators advertise **capabilities**; weapons declare
**requirements**. Both are open `StringName` sets.

```
Part:   { capabilities: Array[StringName] }        # what this manipulator can do
Weapon: { requires: Dictionary }                   # StringName -> count
```

| Capability | Means |
|---|---|
| `TRIGGER` | can operate a firing mechanism |
| `SUPPORT` | can steady/brace a weapon |
| `GRIP` | can hold an object |
| `POWER` | can drive force into a melee swing |

Worked cases, all emergent:
- A **saw-hand** has `[SUPPORT]` but not `[TRIGGER]`, `[GRIP]` or `[POWER]`.
- A **rifle** requires `{TRIGGER: 1, SUPPORT: 1}` → a cyborg with one normal hand and one saw
  **can fire it**: the good hand pulls, the saw steadies.
- A **pistol** requires `{TRIGGER: 1}` → fine in the good hand, impossible in the saw.
- A **two-handed sword** requires `{GRIP: 1, POWER: 1}` → the saw cannot add power to the
  swing, so the sword swings one-handed (or not at all, per the weapon's data).

Nothing here is special-cased per weapon. Add a capability, add a requirement, done.

## Base parts are soft
Narratively a standard arm is artificial muscle over artificial bone — **fragile**. Almost
every arm you find is already plated. The plating is what varies:

| Tier | Plating | Behavior |
|---|---|---|
| Civilian hauler | Sheet steel | barely raises DT; stops nothing serious |
| Combat unit | Ceramic + steel | deflects small arms outright (see `03`) |

A "naked" part is a real, meaningfully bad state — not a theoretical one.

> **Later (see `99`):** artificial *muscle* and artificial *bone* get distinct stats, so you
> can disable an arm without severing it. **No new mechanism is needed** — they're just
> sub-parts on `INTERNAL` sockets, and the graph already expresses that. Deferred as content,
> not architecture.

## Destruction drops assemblies, not loot piles
Blow a shoulder off and **the entire subtree below it drops as one item** — the arm, its
plating, its sword, and the pistol in its hand, still assembled.

- It is **not** exploded into a pile of disparate bits.
- You can pick up an enemy's arm and **use it as-is**.
- **Battlefield modification costs time.** Stripping that pistol off the dropped arm is an AP
  action (see `05`), not free at pickup.

Implementation: the dropped field item *is* the subtree root Part, sockets still populated.

## Part fields
| Field | Purpose |
|---|---|
| `id`, `display_name` | identity |
| `attaches_to: Array[StringName]` | what sockets it fits |
| `sockets: Array[Socket]` | what it can host |
| `capabilities: Array[StringName]` | what it can do as a manipulator |
| `material: StringName` | key into the material table → DT (see `03`) |
| `volume: Array[Box]` | body-space geometry (see `02`) |
| `hp`, `max_hp` | structural integrity |
| `mass`, `bulk` | encumbrance (see `05`) |
| `ram_cost: float` | systems control (see `05`) |
| `stat_mods` | feeds the modifier pipeline (see `08`) |
| `is_container`, `max_bulk`, `mass_multiplier`, `contents` | inventory (see `05`) |
| `hosted_matrix` | the Matrix docked in this part's `MATRIX` socket, if any |
| `tags: Array[StringName]` | open set, e.g. `VOLATILE`, `ORGANIC`, `SALVAGE`, `INERT` |

## Rules
- Attachment is a **tree**. No cycles, one occupant per socket.
- Destroying a part drops its subtree **intact, as one assembly**.
- A matrix docks only into a part that declares a `MATRIX` socket — never a free-standing
  flag any part can claim. Destroy *that* part → eject (see `04`). Today only the torso and
  head templates declare one; an arm can never host a matrix.
- `sockets` (structural) and `contents` (inventory) are **different relationships**. A
  backpack is *attached* to a `BACK` socket and *contains* items.
