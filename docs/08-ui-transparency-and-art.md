# 08 — Transparency, UI & Art Direction

## The rule that governs everything here
> **The description and the damage come from the same code.** Always.

A modern tactical RPG lives or dies on this: if a character has nested traits feeding each
other, **predicted damage must equal actual output**. Not approximately. Exactly.

Therefore: **descriptions are generated from the resolver, never hand-written.** A weapon
has no description string. It has stats, and the tooltip is a *render of the resolved stat
block*. If those two can drift, the design has already failed.

## The modifier pipeline
Every stat resolves through one pipeline that records **provenance**.

```
StatValue: { base: float, current: float, sources: Array[ModSource] }
ModSource: { source_name, source_kind: {PART, PERK, SKILL, AMMO, STATUS, STANCE}, op, delta }

resolve(stat_id, context) -> StatValue      # single entry point, deterministic, pure
```

Nothing may compute a final number outside this. The renderer, the AI, and the damage
resolver all call `resolve()`.

### What the player sees
Base chaingun:
```
5 Damage, 10 projectile burst, recoil 10
```
The player has used **Spin Up** (more projectiles, slightly less recoil). The description
does **not** still say 10 — it says:
```
5 Damage, [14] projectile burst, recoil [8]
```
with changed numbers **highlighted**. Load incendiary ammo and it appends:
```
Shots inflict 0.5 stacks of burn.
```

*(taskblock-13 Pass D: recoil is no longer a flat authored number — its own BASE is computed
per shot from the ammo's damage and the gun's barrel length (`RecoilResolver`), then resolved
through this same pipeline (`WeaponResolver.resolve_recoil_step`) so a perk like Spin Up can
still apply a real, provenance-tracked modifier on top. The "10 -> 8" illustration above is
unchanged in spirit; only where the un-modified 10 itself comes from changed.)*

### Drill-down
Highlighting a number reveals its `sources` — what changed it and by how much.

An **unexpected value** (a decimal where you'd expect an integer — "0.5 stacks") must pull up
*both* the description of burn **and** how burn stacks are calculated. In this case:
> Values preserve decimals for calculation. As soon as a character holds **less than half a
> stack**, the stack vanishes.

The rule: any value whose *form* surprises the player is a link to the rule that produced it.

### Why CC should love this
This is a **property test**, not a UI task:
```
for every (loadout, target, seed):
    assert tooltip_predicted_damage(loadout, target) == simulate_damage(loadout, target, seed)
```
Transparency is the single most testable feature in the project. Make it Phase 2 and every
later system inherits the guarantee.

## Terminal UI
Menus are a **terminal**. Monospace, text-first, limited palette. **This section governs the
terminal UI only** — panels, log, stat blocks. It never governed the 3D world; the board and
everything on it has its own `WorldPalette`, lit and shaded (`docs/10`).

- Godot `RichTextLabel` + BBCode does the highlighting and drill-down links natively.
- Fonts (all OFL/free): **JetBrains Mono**, **IBM Plex Mono**, **Share Tech Mono**, **VT323**.
- Palette: background, foreground, dim, highlight, warn, damage. **Six colors, no more.**
- Everything is a `Theme` resource — no per-scene styling.
- Scanlines/glow/CRT curvature are **shader work, deferred to a VFX pass.** Do not fake them
  with sprites. Build the UI flat and correct; it gets its shine later.

Practical upside: the UI is text, so CC can assert on it and a screenshot isn't needed to
know it's right.

## Art direction
**Half-Life 2 era. Maybe a little lower.** Low-fidelity enough to read as *a game*, not an
engine demo. Consistency beats fidelity everywhere — one coherent look, no AAA cosplay.

| Budget | Target |
|---|---|
| Character tris | ~2–5k |
| Texture size | 512–1024 |
| Materials | Diffuse-led. Avoid full PBR stacks. |
| Rigs | Simple. Few bones. |
| Lighting | Baked/simple where possible |

**Free asset sources** for placeholder and even shipping geometry: **Kenney** (kenney.nl,
CC0), **Quaternius** (quaternius.com, CC0), **Poly Haven** / **ambientCG** for CC0 textures.
Model in **Blender**. None of this costs money.

### Camera
The signature move: **click unit → click attack → click target → zoom to third person** over
the shooter, target highlighted. From there the player picks aim point and manipulations on
the dartboard (`02`). Clicking fire without touching anything sends a **default burst** —
the depth is opt-in, never mandatory.

This camera is **Phase 12+**. It is a view over the silhouette system, which must work
headlessly first.
