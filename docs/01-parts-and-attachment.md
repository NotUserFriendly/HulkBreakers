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

## The Reference Humanoid
Authored data, not architecture — the socket graph above already expresses all of this. It
exists because body-shape-driven behaviour can't be tested against a shapeless body.

### Why this exists
Humanoids are the simple case, and we start here precisely so the non-bipedal work later has
a known-good reference to diverge from. But the shape has to be **real**, because a pile of
mechanics are geometry-driven and silently do nothing without it:

| Mechanic | Needs |
|---|---|
| Cover masking by height (`docs/02`) | legs low, torso mid, head high — at real heights |
| Flanking (`docs/03`) | plates on the **front**, thin/nothing at the **back** |
| Armor DT / stop-dead / deflect (`docs/03`) | **plates that exist at all** |
| Cook-off by flanking an ammo rack (`docs/03`) | a `BACK` socket carrying a `VOLATILE` part |
| Carried body as a bullet catcher (`docs/05`) | a `BACK` socket |
| Sniping a small high-value target (`docs/02`) | a head that is small and separate |
| Matrix ejection from torso **or head** (`docs/01`) | a head with a `MATRIX` socket |

### Scale
Unit origin sits **on the ground, between the feet**. `CELL_SIZE = 1.0`. A standard humanoid
is **~1.85 tall** and fits inside its cell. Feet at `y = 0`. Nothing may extend below `y = 0`.

### Skeleton
All socket transforms are in the **host part's** local space; all volumes are **part-local**,
centred on the part's own origin (Phase 12.0).

All of torso's own numbers below are relative to **torso's own origin** — but torso is the
shell **ROOT**, and `UnitGeometry` places a root at exactly the unit's cell height (`y = 0`)
with no separate "standing height" concept. So torso's origin itself carries a
`ROOT_ELEVATION = 1.25` baked into its volume and every socket it hosts directly (derived, not
invented: leg height `0.90` + the `HIP` socket's own `0.35` drop below torso's origin) — that's
what makes "feet at `y ≈ 0`" literally true instead of the legs hanging below the floor.
Everything **below** torso (arm/forearm/hand/leg's own sockets) stays exactly as authored,
unaffected — the elevation only applies once, at the root.

```
torso            volume  c(0, 1.25, 0)      s(0.50, 0.70, 0.28)      # attaches to nothing: ROOT
  NECK           t(0,  1.65,  0)      -> head
  SHOULDER       t(-0.31, 1.53, 0)    -> arm          # left
  SHOULDER       t( 0.31, 1.53, 0)    -> arm          # right
  HIP            t(-0.14, 0.90, 0)    -> leg          # left
  HIP            t( 0.14, 0.90, 0)    -> leg          # right
  BACK           t(0,  1.30,-0.17)    -> backpack / ammo rack / carried body
  ARMOR          t(0,  1.25, 0.15)    -> torso_plate_front
  ARMOR          t(0,  1.25,-0.15)    -> torso_plate_rear
  MATRIX

head             volume  c(0, 0.12, 0)     s(0.22, 0.24, 0.22)
  MATRIX
  ARMOR          t(0, 0.12, 0.12)     -> head_plate

arm              volume  c(0,-0.17, 0)     s(0.14, 0.34, 0.14)      # upper arm
  ARMOR          t(0,-0.17, 0.09)     -> arm_plate
  FOREARM        t(0,-0.34, 0)        -> forearm

forearm          volume  c(0,-0.17, 0)     s(0.12, 0.34, 0.12)
  ARMOR          t(0,-0.17, 0.08)     -> arm_plate
  FOREARM_TOOL   t(0,-0.17, 0.09)     -> folding_sword etc.
  WRIST          t(0,-0.34, 0)        -> hand / saw / drill

hand             volume  c(0,-0.05, 0)     s(0.10, 0.10, 0.10)
  GRIP           t(0,-0.05, 0.08)     -> pistol / rifle / sword

leg              volume  c(0,-0.45, 0)     s(0.16, 0.90, 0.16)
  ARMOR          t(0,-0.45, 0.09)     -> leg_plate
```

Composed, that puts **feet at y≈0, legs 0.00–0.90, torso 0.90–1.60, head 1.60–1.85** — and a
head that is a ~0.22 target sitting above everything, which is the sniper case.

### Plates are FACINGS, not shells
This is the load-bearing idea. **A plate is a thin box on one face of its parent**, never a
shell around it.

```
torso_plate_front   volume  c(0,0,0)  s(0.54, 0.66, 0.05)   material steel     dt 6
torso_plate_rear    volume  c(0,0,0)  s(0.54, 0.66, 0.03)   material sheet_steel dt 3
head_plate          volume  c(0,0,0)  s(0.24, 0.20, 0.04)   material ceramic   dt 9
arm_plate           volume  c(0,0,0)  s(0.16, 0.30, 0.04)   material steel     dt 6
leg_plate           volume  c(0,0,0)  s(0.18, 0.70, 0.04)   material sheet_steel dt 3
```

Consequences, **none of them special-cased**:
- From the front, `torso_plate_front` sits nearer the shooter than the torso → wins on depth →
  eats the round. DT 6 shrugs off small arms.
- **Flank it and the front plate isn't in the projection at all.** You hit `torso_plate_rear`
  (DT 3, thin) or bare torso. `docs/03`'s "coverage is never total" becomes literally true in
  geometry rather than a promise.
- Plates are slightly wider/taller than the part but **do not enclose it** — the sides stay
  exposed. Free flanking gradient, no rule.
- A destroyed plate detaches; the part behind is bare on the next shot.

**Sockets are the armour budget.** A part with one `ARMOR` socket can carry one plate. Want an
over-armoured brick? Author a torso template with more `ARMOR` sockets, and pay for it in mass
and RAM. No code change.

### Materials
No part may have `material == &""` (`docs/10`). Reference assignment:

| Part | Material | Why |
|---|---|---|
| torso, arm, forearm, leg | `artificial_bone` (dt 2) | base structure is soft (above) |
| hand | `artificial_muscle` (dt 1) | fragile |
| head | `artificial_bone` (dt 2) | |
| front plates | `steel` (dt 6) | combat plating |
| rear/leg plates | `sheet_steel` (dt 3) | thin |
| head_plate | `ceramic` (dt 9) | small, expensive, hard |
| ammo_rack | `sheet_steel`, tag `VOLATILE` | cooks off |

A bare limb (dt 2) dies to anything. A steel-plated front (dt 6) shrugs off a chaingun. That's
the "base parts are soft" tier gap, finally expressed.

### Non-bipedal later
Nothing above is privileged in code. A six-legged shell declares six `HIP` sockets at its own
transforms; a turret declares no `HIP` at all. This is one row in a template table, and the
projector, cover, flanking, and armour rules never learn it happened.
