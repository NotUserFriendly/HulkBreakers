# 05 — Resources, Inventory, RAM

> **Naming note:** `volume` means body-space geometry (`02`). Container capacity is **`bulk`**.
> Don't reuse the word.

## The AP baseline
**A standard cyborg has 6 AP per turn**, before perks and upgrades. Every AP cost in these
docs is quoted against that. Costs are **data on the action/tool**, never magic numbers in
code, and the baseline itself is a tunable constant.

## Three independent constraints
A loadout must satisfy all three. They fail differently, which is the point.

| Constraint | Scope | Failure |
|---|---|---|
| **Mass** | per frame (`max_mass`) | can't carry it |
| **Bulk** | per container (`max_bulk`) | won't fit in the bag |
| **RAM** | per unit (`max_ram`) | can't *control* it |

## RAM — systems control
Measured in **TB**. Controlling your own body is light work; controlling *external* things is
not.

| Thing | Rough RAM |
|---|---|
| A hand | ~1 TB each |
| Motor control unit (walking) | ~1 TB |
| Logic matrix | ~1 TB |
| **Whole civilian humanoid unit** | ~5 TB (no overhead — not meant to be upgraded) |
| Six legs, four arms, eight guns | still < 20 TB |
| Hover cart that follows you | ~10 TB |
| Squad of flamethrower drones | 25–50 TB |
| Linking into a hulk defense grid | ~100 TB |
| Close-range matrix-hacking module | 10 TB **+ the target's max RAM** |

Design consequence: bodies are cheap to run, **fleets are not**. RAM is orthogonal to mass —
a drone swarm weighs nothing and costs a fortune to control.

## Encumbrance rules (carried from v1 — unchanged)
- **Bulk: per container, non-composing.** A container checks its *direct* children's external
  bulk against `max_bulk`. A nested container occupies its parent by its own external bulk —
  a packed bag is a fixed size.
- **Mass: discount applies ONCE, at the worn layer only.** A container's `mass_multiplier`
  reduces felt weight only when the container is *socket-attached to the body*. A container
  nested inside another contributes nothing of its own multiplier — it and its contents are
  summed flat and discounted by the single worn container above. **Multipliers never
  compose.** 50kg in a worn ×0.5 backpack → 25kg. A ×0.8 pouch inside that backpack does not
  apply its 0.8 (10kg → 5kg). Worn directly, the pouch's 0.8 applies.

## Body manipulation — carried bodies are INERT CARGO
A downed unit attaches to a `BACK` socket. **It is cargo, not equipment.** This is the
precise rule, because "attaches to BACK" implies things it must not:

| Does | Does NOT |
|---|---|
| Contribute its **mass** to the carrier | Contribute stats, `stat_mods`, or perks |
| Contribute its **volume boxes** to the carrier's projection — so it eats rounds aimed at your back (`02`) | Let you fire its weapons |
| Occupy the `BACK` socket — **so you can't carry a body and a backpack** | Cost or provide RAM (it's powered down) |
| Get dropped as one intact assembly (`01`) | Act, react, or take turns |

Tagged `INERT` on pickup; the flag is what suppresses all of the right-hand column. Uses:
- **rescue** — hauling a crewmate whose legs are gone,
- **capture** — an intact enemy Logic Matrix is salvage,
- **bullet catcher** — covering a retreat.

Recovering an enemy Logic Matrix intact means **disabling without destroying it**, which
should cost you — weigh it against the extra damage your team takes doing it politely.

## Tool tiers (AP against the 6 AP baseline)
The same job, three ways. Tier buys AP, not just numbers.

| Tool | Mounts | Cost to remove a limb | Trade-off |
|---|---|---|---|
| **Angle grinder** | fits in a backpack | **~6 AP** (a full turn) | limited uses |
| **Metal saw** | replaces a **hand** | **~2 AP** | costs you a hand; runs off unit power |
| **Power saw** | requires a **specialized torso** | **1 AP** per limb, **~2 AP** to render a whole unit | consumes an entire reactor's output |

Battlefield modification of a **dropped assembly** (`01`) is priced the same way — stripping
a pistol off a severed arm is an AP action, not free.

## Resources
**Data, not an enum.** Resource ids are open `StringName`s in a table.

| Resource | Use | Covers |
|---|---|---|
| **Organics** | Surrogates | Meat, foliage — carbon-rich, non-fuel. |
| **Minerals** | Surrogates / Armor | Bone, limestone, mined non-metals. |
| **Metals** | Frames / Weapons | Steel, iron. *Not* titanium — that's discrete. |
| **Ceramics** | Frames / Armor | High-tech: silicon wafers, ablative armor. |
| **Electronics** | Frames / Weapons | Anything rich in gold/copper/silver. |
| **Fuel** | Weapons / Flying | Petrol, diesel, kerosene — flammable hydrocarbons. |
| **Reactives** | High-end upgrades | Nuclear material: uranium, plutonium. |
