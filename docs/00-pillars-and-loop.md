# 00 — Pillars & Loop

## Premise
You captain a **HulkBreaker**: a ship that strips materials from **voidhulks**, derelict
vessels millennia old. Your crew is a set of **Intelligence Matrices** — human minds burned
into hardware, wearing grown flesh over salvaged steel. Pay is what you pull out.

Not post-apocalyptic. The world has safe places; your crew just doesn't live in them.

## Terminology (use these exactly — "robot" is retired)
| Term | Means |
|---|---|
| **Matrix** | The mind. Intelligence (your crew) or Logic (everyone else). See `04`. |
| **Surrogate** | Organic tissue grown from a matrix. A ladder of tiers, not a health bar. |
| **Shell** | The mechanical body — sockets, plating, actuators. A shell with no matrix docked is inert: intact, salvage, wearable. |
| **Cyborg** | A unit combining surrogate + shell. Your crew, typically. |
| **Bot** | A purely mechanical unit: matrix + shell, no surrogate. Most enemies; also a crew matrix flying a bare shell. |
| **Unit** | Engine-level term for anything that takes a turn. Covers both. |

The stack is **matrix → surrogate → shell**. "Robot" describes none of that layering and is
not used anywhere in code, docs, or UI.

## Design pillars
1. **Modularity is the game.** Parts attach by tag, not by keyed slot. If it says it fits a
   shoulder, it fits any shoulder, on anything.
2. **Chaos over precision.** Armor deflects, rounds ricochet, ammo cooks off. A firefight
   should spray consequences sideways.
3. **Transparency is mandatory.** The number shown is the number computed, always, by the
   same code. See `08`.
4. **Player advantage is deliberate and asymmetric.** Players get verbs enemies never get.
   See `06`.
5. **Matrices persist. Everything else is disposable.** Bodies are ammunition.
6. **Low fidelity, high consistency.** See `08`.

## The loop
```
Ship → pick a hulk → insert team → mission (gather resources / hit objective)
     → EXTRACT with loot        ──┐
     → or TERMINATE MISSION     ──┤ (kill your own surrogates, consciousness blinks back)
     → or STRANDED (involuntary)─┤ (no player matrix can act — not a loss)
                                  ↓
              turn in for credits → buy/refine → upgrade ship & matrices → repeat
```

Combat does not end because the enemy is dead — a mission ends only when the player chooses,
or can't continue. Three outcomes (`Enums.MissionOutcome`, `07`): `EXTRACTED`, `TERMINATED`,
`STRANDED`.

- **Credits** are currency. Credits *can* buy resources, but harvesting from hulks is far
  more efficient — the loop should always pull you back into a hulk.
- **Terminate mission** is a real option, not a failure state: you lose the bodies and the
  loot, keep the matrices, and save the time.
- **Failure** costs bodies and cargo, never matrices — `STRANDED` (`07`) is the involuntary
  version of the same guarantee. If a *linked* matrix is destroyed, the death feedback carries
  a penalty to the base matrix (see `04`).

## Two insertion modes
| Mode | How | Consequence |
|---|---|---|
| **Landing** (prototype) | Ship docks, team walks in with the gear you chose. | You control the loadout. |
| **Deep strike** (Phase 7 — in scope) | Matrices fired in as a missile. They use the ingress energy to force enemy matrices out of existing shells and wear whatever they land in. | Zero loadout control. Might land in a scrap heap and spend the first rounds getting to its feet, or in a shell store and get its pick — fighting with unfamiliar parts either way. Guarantees some profit since matrices can't be lost: even one cyborg walking out carrying the team's matrices is a win. |

**Deep strike is pulled forward deliberately.** It is the best stress test the project has:
it forces randomized shell assembly and arbitrary body-part combinations through the whole
stack, and anything malformed surfaces immediately instead of in month three.

## Prototype scope
One hulk, both insertion modes, gather-and-extract, terminate as an alternative exit.
Everything in `99` is out.
