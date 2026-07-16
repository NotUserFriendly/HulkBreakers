# 07 — Mission & Meta Loop

## Mission structure
```
insert → explore / fight → gather resources or hit objective → EXIT
```

Combat does **not** end because the enemy squad is dead (taskblock02 Pass E: that condition is
deleted, not renamed — `CombatState.is_over()` no longer exists). If a map is clear, the player
still has things to do: shore it up, cut apart shells, haul loot. A mission ends only when the
player chooses, or can't continue — three outcomes, `Enums.MissionOutcome`:

| Outcome | Trigger | Matrices |
|---|---|---|
| `EXTRACTED` | Reach extraction, leave with what was carried. | Come home with the haul. |
| `TERMINATED` | The player's own choice (kill your own surrogates). Never the "lose" button — it's the tourniquet. | Come home; loot lost. |
| `STRANDED` | Involuntary — no player matrix can act (`MissionState.is_stranded()`). | Come home regardless — **not a loss**; the roguelike rule is absolute. |

Turn in → credits → buy/refine/upgrade → next hulk.

## Hulk persistence
Hulks are **pseudo-persistent**:
- The **map is generated once** from a seed and stays that way. You can return to it.
- **Enemy presence and behavior are dynamic** — it repopulates.

Consequence: mapping gear is worth carrying. Loot you had to leave behind is loot you can
come back for, and **maps of voidhulks are sellable to other scavs.**

## Ship upgrades — mostly information
Scanning tiers determine how much you know before boots hit the deck.

| Tier | Sees |
|---|---|
| Low | Areas exposed to vacuum; anything behind glass or optically clear. |
| Mid | A map of the outermost rooms and spaces. |
| High | Deeper, but never everything. |

**Nothing beats boots on the ground.** Scanners narrow the unknown; they don't remove it.

## Claims
Some hulks are **settled** — pirates or colonists enforcing a claim. You buy the right to
cut, or you don't cut. A settled hulk is usually **safer** than an unknown one. That's the
trade.

## Economy rules
- **Credits** buy resources, but harvesting is far more efficient. The economy must always
  push you back into a hulk.
### Loot pools overlap slightly — and that's the point
Merchants sell what's been manufactured in the last few centuries. Hulks hold gear millennia
old. **A small overlap exists**: the handful of designs that have been in continuous
production for thousands of years.

| Source | The same rifle is… |
|---|---|
| **Merchant** | The standard. There are many like it, but this one is yours. |
| **Hulk** | An **original pattern** or a **prototype**. |

Differences are **minor but visible**. The thousand-year-old model should *feel* special even
when it's only marginally better — that feeling is the reward, not the stat line. Most of each
pool remains exclusive; the overlap is a seasoning, not a merge.

> Later (`99`): loot randomization with affixes and small stat rolls.

## Prototype scope
| In | Out (see `99`) |
|---|---|
| One hulk, seeded map, persistent across two visits | Ship upgrade tree, scanners |
| Gather-resource objective | Claims, settlements, pirates |
| Extract vs terminate | Map selling, deep strike |
| Credits + the 7 resources as counters | Refining chains, merchants |
