# 02 — Silhouette Space & Targeting

**The exposure table is dead.** Weighted random body-part selection is deleted. Hits are
resolved **spatially**, in a 2D projection of the target.

## Silhouette space
Every unit projects a **silhouette**: a 2D image of itself as seen from the attacker's
angle. Prototype uses **4 facings** (FRONT, BACK, LEFT, RIGHT); angle interpolation later.

- Coordinate space: normalized **64 × 64** per body, origin bottom-centre. Facing-independent
  units, so weapon scatter tunes once.
- Each part declares `silhouette_regions`: `{facing → Array[Rect2i]}` plus a `depth: int`
  (z-order, lower = nearer the shooter).
- **Armor plates overlap their parent part at lower depth.** The plate is literally in front.
- **Gaps are the absence of a region.** Between arm and torso there is simply nothing.

### Resolving one projectile
```
resolve_projectile(target, facing, impact_point) -> Part | null:
    hits = [r for r in target.silhouette(facing) if r.rect.has_point(impact_point)]
    if hits.is_empty(): return null          # gap — shot passes through
    return min(hits, key = depth).part       # frontmost thing wins
```

That single function is the whole system. Everything below is data feeding it.

### What falls out for free
| Feature | Mechanism | Special-cased? |
|---|---|---|
| Flanking | different facing → different silhouette | no |
| Hitting a back-mounted ammo rack | that region only exists in BACK | no |
| Weak rear armor | fewer/thinner plate regions in BACK | no |
| Shots slipping between body parts | impact point lands in a gap | no |
| Sniping an eyehole in a shield | shield region has a hole; the eye is behind it | no |
| Blowing a specific weapon off | aim at that weapon's region | no |
| Cover | occludes the lower N% of the silhouette (see below) | no |

## The dartboard
Aiming produces an **aim point** in silhouette space, not a body-part choice. There is no
"I am aiming for the neck" checkbox — you aim at a spot and live with the scatter.

Three rings, per weapon:
| Ring | Meaning | Shot share |
|---|---|---|
| 0 — centre | tightest, most accurate | small |
| 1 — mid | where the **majority** land | largest |
| 2 — outer | least accurate | small |

```
weapon.scatter = { r0: float, r1: float, r2: float, weights: [w0, w1, w2] }
```
Per projectile: pick a ring by weight, sample a point uniformly in that annulus, offset from
the aim point. **All sampling draws from the passed seeded RNG.**

- A chaingun has huge radii → you aim centre mass and accept a spray.
- A sniper has a tiny `r0` → you can pick the eyehole, the knee joint, the gun.
- Modifiers change radii and weights — never the outcome directly (see `08`). "Spin Up"
  shrinks `r1`; a bipod shrinks all three; being suppressed inflates them.

Scatter radii scale with range; the scaling formula is a tunable, start linear.

## Cover in silhouette terms
Cover does not reroute hits or reweight rolls. It **occludes**:
- Half cover masks the silhouette below y = 32 (i.e. the lower half).
- Full cover masks below y = 56, leaving a firing slit.
- A projectile whose impact point lands in a masked band hits the **cover object** instead
  (destructible → damage it; terrain → absorbed).
- Destroy the cover → the mask lifts → those regions are exposed again.

Exact mask heights are per-cover-object data, not constants in code.

## Open question (do not decide in code — ask)
Whether a shot landing in a gap should (a) miss entirely, (b) continue to whatever is behind
the target, or (c) hit a part at greater depth in that column. **Prototype default: (b)** —
it feeds the chaos pillar and reuses the ricochet travel path from `03`.

## Testing without rendering
CC must build an **ASCII silhouette dump** (Phase 0): print a 64×64 grid where each cell is
the id-letter of the frontmost part, `.` for gaps, `#` for cover mask. Overlay `*` for shot
impacts. Every rule above is then eyeball-verifiable in a test log — and diffable.
