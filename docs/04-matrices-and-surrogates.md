# 04 — Matrices & Surrogates

## Two kinds of matrix
| Type | What | Role |
|---|---|---|
| **Logic Matrix** | Dense programming mesh. What most bots run on — industrial, medical, military. | Made of a unique valuable material → **worth salvaging intact**. |
| **Intelligence Matrix (IM)** | A quantum-linked copy of a human brain, most limits of flesh removed. | Your crew. Persistent. Named. |

## Linking — the risk model
The **Base Matrix stays on the ship.** It writes itself into a **Link Matrix** (a standard
Logic Matrix) in the field.

- **Link destroyed → the feeling of dying mirrors back** to the base → perk reduction or
  other side effect. This is the real cost of failure. It replaces the old
  `pending_return_penalty` placeholder with an actual mechanic.
- **Link tier caps capability.** A low-tier link carries only a fraction of the base's
  ability — a high-level matrix in a cheap link plays like a lower-level one.
- **The compensation:** a low-tier link may only carry ~3 perks (not final), but the player
  **chooses which** — and they can be the base matrix's highest-tier perks. Cheap links are
  narrow, not merely weak.

```
effective_level = base.level * link.tier_ratio
perk_slots      = link.perk_slots         # player picks which perks fill them
```

The rule from v1 still holds absolutely: **matrices are never permanently lost.** Losing
costs bodies, cargo, and perk progress — never a crew member.

## Surrogates
The matrix is not purely hardware. For advanced integration it is **half biological**: the
matrix seeds a **surrogate vat**, growing a body around it.

Tiers are an **ordered data ladder** (a Resource with a rank), not a hardcoded enum — new
tiers must not need a code edit.

| Tier | Body | Notes |
|---|---|---|
| `FULL` | Complete human body | |
| `PERIPHERAL` | Arms + legs around a hollow core | |
| `TORSIC` | Torso and head | |
| `SPINAL` | Head and spine | still usable |
| `BRAIN_ONLY` | Just the matrix and its casing | drives a shell fine — that's a bot |

**Degradation is a ladder, not a health bar.** Damage knocks a surrogate down tiers. A torso
chewed down to `SPINAL` still works. Kill a player unit and it reduces to *some* amount of
surrogate — salvageable.

**Organics have a clock.** Surrogate tissue is tougher than human tissue but still
deoxygenates and dies. Once exposed or damaged, tier decays **over turns**. Eventually you
have a bare matrix.

| Body state | Best at |
|---|---|
| Raw matrix | Plugging into **shells** — it drives a bot |
| Surrogate | Specialized **cybernetic** parts |

## A surrogate is a Part (taskblock02 Pass D)
Same inversion as everything else in `01` — no new mechanism. A surrogate is a real, shootable
`Part` with its own `MATRIX` socket the matrix docks inside; the *shell* hosts the surrogate,
the *surrogate* hosts the matrix. **Matrix → surrogate → shell** is just two levels of the
existing socket graph. A bot skips the middle level and docks a bare matrix straight into the
shell's own `MATRIX` socket — same `dock_matrix()` call either way.

`Socket.socket_type` values: `MATRIX` (a bare matrix, no surrogate), `SURROGATE_BRAIN`,
`SURROGATE_SPINAL`, `SURROGATE_TORSIC`, `SURROGATE_PERIPHERAL`, `SURROGATE_FULL` — a shell's own
surrogate cavity is one of these, sized to whatever tier it was built to fit. The cavity itself
sits at a fixed, well-known socket **id** (`BodyAssembler.SURROGATE_SOCKET_ID`), same idea as
`MATRIX` for a bot: what varies between shells is the cavity's *type* (how big a surrogate it
fits), never which socket to look for.

**Tier is a maximum, not an exact match — any surrogate fits a larger box.** `Part.surrogate_tier`
is the one field an author writes (`&"SPINAL"`, say); `attaches_to` is **derived** from the
ladder (`SurrogateLadder.derive_attaches_to`) — every socket type whose own tier ranks no worse
than this one. A `BRAIN_ONLY` surrogate (worst rank) fits every cavity there is; a `FULL`
surrogate (best rank) fits only a `SURROGATE_FULL` cavity. Add a rung to the ladder and every
surrogate's legal cavities update with no hand-editing.

**Capability gating.** `SurrogateTier.capabilities` is what a docked surrogate at that tier
lets the shell's body-gated parts (`Part.body_requires`) actually do — do **not** assume tiers
nest supersets of each other; `PERIPHERAL` (limbs, hollow core) and `TORSIC` (organs, no limbs)
can carry genuinely different sets, not just more or fewer of one list. A part whose
`body_requires` isn't met is **inert** — present, carried, massed, shootable, never removed or
errored. Vocabulary is intentionally thin: only `LOCOMOTION` is authored so far, for the one
mechanic that needs it. Ask before adding more.

**Ejection has two shapes**, both "matrices are never lost," both demote a rung:
- Destroy the part hosting a **bare matrix** directly (a bot) → the matrix ejects alone
  (`DamageResolver.eject_matrix_if_needed`, unchanged since `01`).
- Destroy the **shell root** while it hosts an **attached surrogate** → the whole surrogate,
  matrix and all, drops as one intact field item (`eject_surrogate_if_needed`) — the shell was
  what protected it, and (unlike a normal subtree drop) the root has no parent within itself to
  drop *from*.
- Destroy the **surrogate itself** (its own hp reaches 0) → falls through to the first case:
  the surrogate hosts the matrix directly, so `eject_matrix_if_needed` already covers it.

**Life support** (`LifeSupport.tick`, called once per turn alongside the existing exposed-turns
clock): once a surrogate is exposed, its decay clock branches on socket + power + organics.

| Surrogate is | Decay clock |
|---|---|
| socketed, shell **unpowered** | advances — the plain per-turn demotion `04` always described |
| socketed + **powered**, no organics carried | **holds** |
| socketed + **powered** + organics carried | **winds back** one step, consuming one ration |

`Shell.is_powered()` is true while any living part carries the `POWER_SOURCE` tag (the pool's
`reactor`, tagged `POWER_SOURCE` + `VOLATILE` both — shooting it out stops regen and starts a
fire from one tag each, not two systems to keep in sync). Regen never **promotes** a tier; it
only walks the same demotion counter back toward zero, floored there. Once a tier is actually
lost it stays lost until a **growth item** — explicitly a hook, not built: a future item that
lets a surrogate be transplanted into a larger socket and grown to fit, i.e. promoted, which
passive regen can never do.

**Scope note:** life support only ticks a surrogate still socketed in a piloted `Unit`. A
**detached** surrogate — dropped loose after ejection — has no per-turn ticking today; that
needs a field-item tick loop the mission layer doesn't have yet. Flagged, not silently skipped.

## Why surrogates exist (design intent — do not optimize away)
Two reasons, both deliberate:
1. **Visceral.** Gore makes the game feel like it has stakes.
2. **Empathetic.** A matrix has a *name* — the person whose brain was copied. A surrogate
   grown to that person's preferences **looks like they did**. Even a squad of brains and
   spinal columns in steel bodies keeps a human face, and can talk.

That face is the reason the player cares whether Jerry comes home. Keep it.

## Recovery states (battle end)
| State | Condition | Result |
|---|---|---|
| `PILOTING` | Still in a body at extraction | Clean. |
| `CARRIED` | Picked up by an ally, extracted | Clean. |
| `LEFT_BEHIND` | Still on the hulk floor at mission end | Returns anyway; flag a penalty (mechanic TBD — set the flag, invent nothing). |
| `LINK_KILLED` | Link matrix destroyed | Returns; apply death-feedback penalty. |

## Prototype scope
Implement: matrix identity, link tier → effective level + perk slots, surrogate tier as a
degradation ladder with a turn clock, ejection, carry, recovery states.
**Skip:** vat simulation, growth time, appearance generation, dialogue.
