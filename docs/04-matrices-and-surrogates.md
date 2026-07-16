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
