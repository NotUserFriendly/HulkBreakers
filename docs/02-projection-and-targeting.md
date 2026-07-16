# 02 — Body Space, the Shot Plane & Targeting

**The exposure table is dead.** Weighted random body-part selection is deleted, not
refactored. **Facings are also dead** — there is no FRONT/BACK/LEFT/RIGHT snap. Geometry is
continuous and projected from the shooter's actual angle.

## Body space
Every part declares a **volume**: one or more boxes positioned in **that part's own local
space** — not the unit's (`docs/10`, Phase 12.0).

```
Box:    { center: Vector3, size: Vector3 }      # part-local; +X right, +Y up, +Z forward
Socket: { socket_type, occupant, transform: Transform3D }  # host-part-local attachment frame
Part:   { volume: Array[Box], ... }
```

`BodyProjector` composes a part's world-relevant transform by walking the socket tree down from
the shell's root (`world = parent ∘ socket.transform ∘ local`) before projecting its boxes —
that's what makes a torso with 12 mirrored `SHOULDER` sockets place 12 arms in 12 different
places instead of one. A socket with the default identity transform places its occupant
exactly where the host's own local origin is, so single-part fixtures and un-migrated sockets
project unchanged.

- **One box per part is the common case.** Authoring is a single box, not four rect-sets.
- **Multiple boxes express holes.** A shield with an eyehole is four boxes around a gap. No
  hole primitive, no mask — just absence.
- Body space is normalized; a nominal humanoid stands `BODY_HEIGHT` tall. Everything scales
  from that constant.

## Projection
```
project(unit, view_dir) -> Array[Region]
Region: { rect: Rect2, depth: float, part: Part, surface_normal: Vector3 }
```

Rotate each box by the angle between `view_dir` and the unit's orientation. A box projects
**one Region per visible face**, not one guessed region for the whole box: a face is visible
when its rotated normal points at least partly back toward the shooter, and an edge-on face
(near-zero projected width) is dropped rather than emitted as a sliver. `surface_normal`
belongs to the specific face that produced that Region — real geometry, not a guess about the
box as a whole. A box viewed corner-on shows two adjacent faces in non-overlapping screen
spans, one closer to head-on and one closer to grazing; their union is exactly the same
silhouette a single whole-box projection would produce, just split by which face was hit. Each
Region still records its own distance along the view axis as `depth`. Cheap, deterministic, no
physics.

**Everything falls out of this. Nothing below is a special case.**

| Feature | Why it works |
|---|---|
| Flanking | different angle → different projection. Continuous, no thresholds. |
| Rear ammo rack exposed | it sits at −Z; from the front the torso has lower depth and occludes it |
| Thin rear armor | fewer plate boxes behind |
| Shots slipping between parts | impact point lands where no box projects |
| Sniping an eyehole | the hole is absence; the part behind is next in depth |
| Blowing a named weapon off | aim at its projected rect |
| Carried body as a bullet catcher | its boxes project into the carrier's silhouette |

## The shot plane
Do **not** project one target. Project **everything along the line of fire** — every unit,
cover object, and obstacle — into a single plane, depth-sorted.

```
ShotPlane.build(origin, direction, world) -> Array[Region]   # sorted by depth ascending
```

```
resolve_projectile(plane, point) -> Region | null:
    for region in plane:                 # already depth-sorted, nearest first
        if region.rect.has_point(point):
            return region
    return null                          # clean through — nothing was there
```

This is the entire hit-resolution system.

**Layered targets, for free:** the dartboard lands on the nearest target, but the plane holds
the ones behind it. A sniper threading a round past a big guy into a smaller, higher-value
target behind is *just a gap hit that continued* — same code path. The UI must therefore be
able to show stats for **partially obscured** targets deeper in the plane, not only the
nearest one. That's a requirement on the view, not a new mechanic.

Cover is a region in the plane like anything else — destructible cover is a Part with hp,
terrain is a Part flagged indestructible. Destroy it and its regions leave the plane.

## The dartboard
Aiming picks an **aim point** on the shot plane, never a body part. There is no "aiming for
the neck" checkbox — you pick a spot and live with the scatter.

```
Ring:    { radius: float, weight: float }
scatter: Array[Ring]                    # ordered inner → outer. N rings, not 3.
```

Author **N rings**, not a fixed three. The reference weapon uses three — tight centre, a
fat middle where the majority land, a loose outer — but a shotgun might want two and a
railgun one. Nothing in code may assume a count.

Per projectile: pick a ring by weight, sample uniformly within its annulus, offset from the
aim point. **All sampling draws from the passed seeded RNG.**

- Chaingun: huge radii → aim centre mass, accept the spray.
- Sniper: tiny inner radius → pick the eyehole, the knee joint, the gun.

Modifiers change **radii and weights**, never outcomes, and always through the resolver
(`08`). "Spin Up" shrinks a ring; a bipod shrinks all of them; suppression inflates them.
Radii scale with range — start linear, it's a tunable.

## Open question (do not decide in code — ask)
A projectile that hits nothing in the plane: does it stop at max range, or keep travelling
into the world to hit whatever's beyond? **Default: it keeps travelling**, reusing the
ricochet travel path from `03`. Feeds the chaos pillar.

## Testing without rendering
CC must build an **ASCII plane dump** (Phase 0): print the shot plane as a text grid — a
letter per part, `.` for gaps, `*` for impacts, with a depth-ordered legend. Every rule above
becomes eyeball-verifiable in a test log, and diffable across commits. This is CC's only way
to see spatial bugs. Use it in every phase.
