# 02 — Body Space, Projection & Targeting

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
**The plane is the aim model, not the resolver.** Read *Two models, and the boundary between
them* below before treating anything in this section as describing what happens to a round —
**`RayChain` has resolved shots since taskblock-52 Pass F** (`CombatState.shot_resolver`
defaults to `&"ray"`), and this section describes the structure the player points at.

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

**That lookup is what the plane is *for*: given a point, which region is frontmost.** It is
`ShotPlane.resolve_ray`'s internal step and it is what the aim view reads. It answers *where is
the player pointing*. It is **not** the hit-resolution system, and this doc said it was for
forty-odd taskblocks after it stopped being true.

**The plane still resolves when a bout asks it to.** `CombatState.shot_resolver` is per-bout and
takes `RESOLVER_PLANE`, which is how `ResolverDifferential` puts one board through both models.
That is the plane's remaining resolution role: a comparison arm, not the default path.

**Layered targets, for free:** the dartboard lands on the nearest target, but the plane holds
the ones behind it. A sniper threading a round past a big guy into a smaller, higher-value
target behind is *just a gap hit that continued* — and under the chain it is literally the same
march continuing, not a second lookup. The UI must therefore be able to show stats for
**partially obscured** targets deeper in the plane, not only the nearest one. That's a
requirement on the view, not a new mechanic.

Cover is a region in the plane like anything else — a Part with hp, destroyed leaves the plane.
**A wall is just high-DT destructible cover on an otherwise-passable tile** (tb31 Pass C,
superseding this doc's own earlier "terrain flagged indestructible" line — walls are meant to be
breached, not permanent): destroy one and its cell clears to fully passable ground, the same as
any other dead cover, via the shared Pathfinder fix every blocker benefits from (a destroyed
blocker no longer blocks movement). What's actually indestructible is the **void** past a wall's
own ring — non-navigable, no Part, nothing for a shot to hit either.

## Two models, and the boundary between them

**The plane answers *where is the player pointing*. The ray answers *what
happens*.** Until taskblock-52 the plane did both, and the second badly. This
section exists because the plane had never been written down as a *model* — only
accumulated as per-taskblock comments inside the file being reasoned about, which
is how two confident readings of it came out wrong in one block.

| | shot plane | ray chain |
|---|---|---|
| consumes | every candidate, enumerated | whatever the ray meets |
| cost driver | scene size, per rebuild | ray length |
| deflection | needs a **whole new plane** for the new direction | the same call, recursed |
| angle at impact | discarded — a `Region` is an axis-aligned box of projected corners with a `body` | native; it is what you solve on |
| membership | hand-enumerated per collection | one query |

**Three open bugs were consequences of the model, not oversights.** A bounce
tracer drawn to a fixed range, and a `STOP_DEAD` drawn past its own hit point,
both existed because there is no plane for a post-deflection direction and
building one is the expensive path — so the continuation was faked. `BR34.05`
(misses vanish) exists because floors were never enumerated. None needs special
handling in a ray march: **C-becomes-B is the same call again, and a ray in a
closed room cannot fail to hit.**

### The chain

```
A = muzzle point          (not the unit's cell centre)
B = the aimed point       (from the dartboard, or a raycast if nothing was clicked)
march A → B, first hit wins
solve the angle of incidence against the struck surface
→ deflect / penetrate / stop_dead   (docs/03, unchanged)
if it continues:  C = march from B along the solved direction
                  then C becomes B, B becomes A, repeat
```

- **The angle of incidence is native here**, where the plane discarded it.
  `docs/03`'s deflect/penetrate/stop maths is described against a real surface
  angle and, under the plane, got an approximation of one.
- **A penetration continues the same ray; a deflection starts a new one.** Both
  are the same call with a different direction — no branch that only one of them
  exercises.
- **The chain is capped, and the cap logs when it is hit.** An unbounded
  recursion between two parallel walls is the obvious pathology.
- **The outcome vocabulary is unchanged.** The ray changes *how* an outcome is
  determined, never what the outcomes are.

### Why the boundary sits there

`docs/08`'s pillar — the number shown is the number computed — survives the
split because the thing shown and the thing computed are still **one**
computation. The dartboard picks the **B point**; the ray resolves from A to B
onward. Two systems would only violate the pillar if both *resolved*, and only
one does.

The aim view already renders the real target and `PartPicker` already resolves a
screen ray against it, so picking a point on the dartboard **is** a ray query the
codebase already performs on every mouse move. Recoil and scatter offset B before
the march; determinism is unaffected, because that is a seeded offset on a point
followed by a closed-form march — no integrator, no accumulated simulation.

**Analytic ray-vs-box only.** `PartPicker.hit(units, grid, from, dir)` delegates
to `UnitPicker.ray_box_t` — a slab test in each box's own local frame, no scene
tree and no physics server. A `PhysicsDirectSpaceState` raycast needs a live
scene tree and would move shot resolution into the view layer, breaking the
golden rule outright. It is not the swap-in it was once described as.

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

## Answered: where a shot actually aims, and whether player and AI differ

Asked in taskblock-56 Pass B: *does a shot aim at the dartboard point on the target, or at the
target's centre — and does the answer differ between player control and AI control?* Traced from
both origins to the resolver's input, and measured rather than read.

### The two paths agree, and it is structural

**There is one aiming implementation.** `ActionCatalog.build_firing_action` is the only place in
`src/` that constructs a firing action, and every firing action resolves its aim point through the
identical expression:

```
aim_point = ShotPlane.center_of(plane, target) + aim_offset
```

- **The player's path** (`TacticsController.confirm_shot`) passes its `reticle_offset` as
  `aim_offset`. Clicking fire without touching the reticle passes `Vector2.ZERO`.
- **The AI's path** (`UtilityExecutors.build`) omits the argument entirely, taking the same
  `Vector2.ZERO` default. So does overwatch, and so does the step-out triple's middle leg.

**A default left alone is not a second implementation.** The AI has no aiming rule of its own to
drift from the player's; it has the player's rule with the one knob untouched. `no parallel
systems` holds, and `test_one_aim_path.gd` pins it — both paths' actions compared field by field,
plus a source sweep asserting no firing action is constructed outside the catalog.

**So this removes a suspect from `BR51.01` rather than supplying a lead.** A player/AI split is not
what is moving those shots.

### But the aim point is not the target's centre — it is one part's centre

`ShotPlane.center_of` returns `best.rect.get_center()`, where `best` is the target's **frontmost
region**: whichever single projected face of whichever single part sits nearest the shooter. It is
neither the body's centroid nor a point on the muzzle-to-target axis.

**An outstretched weapon or a raised arm therefore *is* the aim point.** Measured on a real
assembled body, shooter and target on level ground, the aim point and the angle it subtends off the
muzzle-to-target-cell axis:

| range (cells) | frontmost region | aim point height | off-axis |
|---|---|---|---|
| 1 | pistol | 0.80 | **20.1°** |
| 2 | pistol | 0.80 | 5.9° |
| 3 | plate_small_steel | 1.36 | 0.6° |
| 10 | arm_cladding | 1.36 | −0.1° |

Swept across the target's facing at 1 cell, the worst reading was **20.1°** and the same body at 5
cells never exceeded **3.2°**.

Three properties follow, and all three are consequences rather than decisions:

1. **The lateral error is a fixed distance in the body, so the angle it subtends grows without
   limit as range shrinks.** Half a metre of shoulder is nothing at fifteen cells and is tens of
   degrees at one. **It is a range effect, not a weapon effect.**
2. **The aim point's height is that part's height too** — dropping to the gun's 0.80 at close range
   from the upper body's 1.36. So the same mechanism aims *down* as well as sideways.
3. **Which part wins changes with range and facing**, because depth ordering shifts as the
   projection angle does. The aim point is not stable across a unit walking toward you.

**This is a finding, not a specification.** Nothing chose it; it is what "the frontmost region's
centre" means once bodies stopped being single boxes. Whether the aim point *should* be the body's
centroid, a point on the muzzle-to-target axis, or the frontmost region as today is an open design
question — **see `BR54.01`, whose stated unverified suspect this confirms.** Do not treat the table
above as intended behaviour.

**Related but separate: `InternalTargeting.aim_offset_for` computes exactly this offset for a named
internal part and has no production caller** — nothing outside its own tests reaches it. The
knowledge-gated aim-at-a-specific-internal path exists and is not wired up.

## Answered: what a projectile that hits nothing does
This was an open question here for a long time ("stop at max range, or keep travelling?").
**The supervisor answered it while `BR34.05` was being triaged, and the answer is stronger
than either option:** a shot should **nearly always hit something** — the floor, or one of
the many walls surrounding the arena. The only legitimate ways for a round to hit nothing
are **through an already-broken wall** or **out through the ceiling**.

Range **attenuates damage; it never deletes the projectile.** A round past its effective
range still travels and still strikes; it just arrives with less behind it.

That makes "miss" a resolution outcome that should be rare rather than a branch the
resolver takes whenever its lookup comes up empty — and it is the rule the ray chain is
built to satisfy, since a ray in a closed room cannot fail to hit.

## Testing without rendering
CC must build an **ASCII plane dump** (Phase 0): print the shot plane as a text grid — a
letter per part, `.` for gaps, `*` for impacts, with a depth-ordered legend. This is CC's only
way to see spatial bugs. Use it in every phase.

**The dump shows what the shooter faces; it does not show what the round did.** Since the chain
became the resolver, a round slopes muzzle-to-aim-point and continues past what it penetrates —
neither of which a single flattened plane can display. **The impact sequence is the combat log's
job** (`docs/09`): what was struck, in what order, at what angle, with what left. A rule about
*aiming* is verifiable from the dump; a rule about *resolution* is verifiable from the log, and
asserting one from the other is how the level-shot approximation survived as long as it did.
