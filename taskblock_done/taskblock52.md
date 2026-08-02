# Taskblock 52 — The ray chain: resolve shots in 3D, aim in 2D

*Replaces `ShotPlane` as the shot **resolver**. Closes `BR34.05`, `BR35.04`, `BR35.07`, and `PLAN.md`'s
*Wide scatter passing through a wall seam*. Bumps `PLAN.md`'s NEXT — deliberately, because these bugs
are worked around rather than fixed while the current model stands.*

**The current model resolves a shot against a 2D silhouette of the whole world. This one marches a ray
through the actual world.**

| | plane (current) | ray chain (this block) |
|---|---|---|
| consumes | every candidate, enumerated | whatever the ray meets |
| cost driver | scene size, per rebuild | ray length |
| deflection | needs a **whole new plane** for the new direction | the same call, recursed |
| angle at impact | discarded — a rect keeps only `body` | native; it is what you solve on |
| membership | hand-enumerated per collection | one query |

**Three open bugs are consequences of the model, not oversights.** `BR35.04` (bounce tracer is a
decorative fixed-range projection) and `BR35.07` (`STOP_DEAD` drawn past its own hit point) exist
because there is no plane for a post-deflection direction and building one is the expensive path — so
the continuation is faked. `BR34.05` (misses vanish) exists because floors were never enumerated. **None
needs special handling here: C-becomes-B is the same call again, and a ray in a closed room cannot fail
to hit.**

**The foundation already exists and is already in the right layer.** `PartPicker.hit(units, grid, from,
dir)` returns the nearest part with a `t`, delegating to `UnitPicker` — analytic ray-vs-box, no scene
tree, no physics server, running on every mouse move today. **Do not add a `PhysicsDirectSpaceState`
raycast**; it needs a scene tree and would move shot resolution into the view layer, breaking the golden
rule outright.

**`ShotPlane` is referenced in 76 files / 133 sites.** This block does not delete it — see Pass F.

---

# PASS A — Write the model down, and take the numbers you will be judged against

## A1. `docs/02` states both models and the boundary between them

The plane has never been written down as a *model* — only accumulated as per-taskblock comments inside
the file being reasoned about. That is why two confident readings of it were wrong last block.

- **The plane's job becomes aiming.** It answers *where is the player pointing*.
- **The ray's job is resolution.** It answers *what happens*.
- Right now the plane does both, and does the second badly. `docs/08`'s pillar survives because the
  thing shown and the thing computed are still one computation — the dartboard picks the **B point**,
  and the ray resolves from A to B onward.

## A2. Baseline, before anything changes

- **Reproduce the seam measurement** — 56/200 empties at lateral offset ~8. An unreproduced number is
  not a baseline.
- **Per-shot and per-burst cost of the current plane.** `ShotPlane.build` was measured at 35 258 usec on
  `BR26.02`'s hot path. **This is the one place the plane genuinely wins**: one build serves a whole
  burst, N cheap point-in-rect tests. A ray chain pays per round. Take both numbers so the trade is
  measured rather than argued.
- A dense sweep harness, committed and rerunnable, so Pass G can show the seam closed.

**TESTS:** the sweep reproduces the recorded empties; cost figures are stamped with `BuildIdentity`.

---

# PASS B — The chain

```
A = muzzle point          (not the unit's cell centre)
B = the aimed point       (from the dartboard, or a raycast if nothing was clicked)
march A → B, first hit wins
solve the angle of incidence against the struck surface
→ deflect / penetrate / stop_dead   (docs/03, unchanged)
if it continues:  C = march from B along the solved direction
                  then C becomes B, B becomes A, repeat
```

- **The angle of incidence is native here.** The current model discards it — a `Region` is an
  axis-aligned box of projected corners with a `body`, and nothing survives about the face's real
  orientation. `docs/03`'s deflect/penetrate/stop maths is described against a real surface angle and
  currently gets an approximation.
- **Cap the chain**, and log the cap being hit. An unbounded recursion between two parallel walls is the
  obvious pathology.
- **The existing outcome vocabulary is unchanged.** This block changes *how* the outcome is determined,
  never what the outcomes are.
- **A penetration continues the same ray; a deflection starts a new one.** Both are the same call with
  different direction — no branch that only one of them exercises.

**TESTS:** a shot into a closed room with a floor **always** strikes something (this is the supervisor's
standing rule and it is now testable); a deflection's second segment ends where geometry says, not at a
fixed range; a `STOP_DEAD` chain has exactly one segment; a seeded shot resolves identically across
runs; the chain cap fires and logs rather than recursing.

---

# PASS C — Ties: raycast, then box cast, then fall back — and log every one

**What can actually tie is narrower than it looks.** Units are lumpy part trees and cannot share a cell
with a wall, so a unit-vs-wall tie is effectively impossible. **The realistic case is wall-vs-wall** —
adjacent cells sharing a face plane at exactly the same `t`.

**And a tie is benign.** A shared plane means the ray hits *at least one* of them; the gap that
`BR34.05` and the seam item describe cannot occur. **A tie is an attribution question — which cell takes
the damage — not a hit/miss question.**

Three stages, each only reached when the one above it does not resolve:

1. **Raycast.** Resolves nearly always.
2. **Box cast, over the tied candidates only.** It cannot add hits or widen the projectile — it is
   handed the set the ray already found and arbitrates within it. Swept along the ray, it leads with a
   corner at an angle and breaks the tie. **When the ray is axis-aligned the box is too and meets both
   symmetrically**, so that subcase falls through to stage 3. That is fine; stage 3 is why it exists.
3. **Fallback.** **Not type priority** — the realistic tie is same-type, where a type rule is a no-op.
   Use **closest root**: A's root is the shooter, each candidate's root is its own object; the gun is
   offset from the unit's centreline and the two cells' centres differ, so root-to-root distance
   separates them. Cell-aligned, so the maths is cheap.

**Every tie writes to the combat log**, with the stage that resolved it. Neither the supervisor nor CC
knows the tie rate; a stage that fires once in ten thousand shots is a path nobody ever sees run, which
is exactly the failure this project keeps producing. **The log is what turns stage 2 from insurance into
something with evidence behind it** — and if ties are geometrically asymmetric, that is the condition
under which the box stage is actually earning its place.

**TESTS:** a constructed wall-vs-wall tie resolves and logs; an axis-aligned tie falls through to stage
3 and logs that it did; the box stage never returns a body the raycast did not find (**assert this — it
is the property that keeps it an arbiter rather than a second cast**).

---

# PASS D — Membership dissolves

Three collections exist in `Grid`; `ShotPlane.build` loops two.

| collection | in the plane | in a ray march |
|---|---|---|
| `state.units` | yes | yes |
| `grid.blockers` | yes | yes |
| `grid.field_items` | **no** | yes |
| `grid.surfaces` | **no** | yes |

- **Floors.** `Surface` already carries `var part: Part` (taskblock-38 made floor and terrain into parts)
  and `var height: float`. No stand-in type, no new outcome. A floor is ordinary geometry to a ray —
  none of the plane's edge-on-sliver awkwardness applies.
- **Field items.** `BodyProjector.project_assembly`'s own doc comment states its purpose — *"a dropped
  assembly, a scrap pile... this is what makes a dropped assembly shootable: a pile of scrap stops
  rounds"* — and `ShotPlane` calls it on `blockers` and **never on `field_items`**. The capability was
  built for this and left unwired. The supervisor's rule: a dropped arm on a tile is a part tree exactly
  as a unit's shell is.
- **`field_items` maps a cell to an `Array`.** March against every entry.

**Report whether membership should be *derived* rather than listed** — one "everything occupying space"
query that the ray, the picker and the inspect preview all consume. `PartPicker` scans two collections
while the plane scans two different ones, and `InspectPanel`'s non-unit path was a third instance
(`BR51.25`). Do not build it here; say whether the next absent collection is prevented structurally or
found the same way these three were.

**TESTS:** a downward shot strikes the floor and the struck body is the surface's own `Part`; a shot at
a dropped assembly strikes it; a cell holding several items exposes all of them; ramp-standing geometry
resolves at its true ramp-aware height, matching what `BoardView` renders.

---

# ⏸ HARD PAUSE — parity before adoption

**Both systems alive, behind a flag; the plane is still the default.** Report:

- The seam sweep, ray chain versus plane.
- Per-shot and per-burst cost, both models, release build.
- **A differential run:** the same seeded shots through both, listing every case where they disagree and
  why. Disagreements are expected — the ray is more correct — but each one should be *explicable*, and
  an inexplicable one is a defect in the new path.
- Determinism: identical results across runs, and traversal order is geometric rather than dictionary
  order (which is a **stronger** guarantee than the plane's `sort_custom` over `Dictionary` iteration).

**The burst cost is the one number that could sink this.** If a burst is dramatically worse, say so
rather than absorbing it — `BR26.02` is open with a stated steady-160 bar.

---

# PASS E — The dartboard becomes an input device

The aim view already renders the real target and `PartPicker` already resolves a screen ray against it —
*"the player clicks an enemy for a closer look, then clicks a point on that object."* That closer look
is the dartboard, and picking a point on it **is** a ray query the codebase already performs.

- The dartboard answers **where is the player pointing**, producing the B point.
- Recoil and scatter offset B before the march. **Determinism is unaffected** — a seeded offset on a
  point, then a closed-form march. No integrator, no accumulated simulation.
- The plane keeps its aiming job only if it is doing something `PartPicker` does not. **Say which**, if
  so.

**TESTS:** a click at a screen position produces the same B point the aim view drew a reticle at; scatter
offsets are seeded and reproducible; the aim preview's reported outcome matches what resolution produces
(**`docs/08`: the number shown is the number computed**).

---

# PASS F — Reconcile, do not delete

**`ShotPlane` is referenced at 133 sites across 76 files.** Deleting it in the same block that replaces
it makes any regression impossible to attribute.

- After parity, the ray chain becomes the default and the flag inverts.
- **Then** work out what `ShotPlane` is still for. If Pass E leaves it with no job, it retires in a later
  block with its own sweep — the shape taskblock-45 used for `unit_ai.gd`.
- `SUPERSEDED.md` records the model change: what the plane was, why a ray chain replaced it as the
  resolver, and the measured before/after.

**Not in this block:** deleting `ShotPlane`, `BodyProjector`, or their tests.

---

# Acceptance

- **A shot in a closed room nearly always hits something**, under test across a dense sweep, with every
  remaining miss having a named reason.
- The seam sweep finds zero empties where Pass A reproduced them — **and a shot aimed at a genuine
  opening still passes through it.**
- A deflection's drawn path is its resolved path (`BR35.04`, `BR35.07` close on geometry, not on drawing
  code).
- Costs reported both models, release build, per shot and per burst.
- `docs/02` states both models and the boundary.

# Not this block's job

- **Explosion types.** `PLAN.md`'s *Explosions: three types on one substrate*. This block makes
  fragments *possible* by giving them things to hit; it does not build them. Fragments are bullets and
  will use this resolver.
- **`BR51.01`** (shots land wide left) — camera-side, unexplained, its own investigation. **It may
  dissolve here**; if it does, say so, do not assume it.
- **`BR26.02`'s residue.** Measure this block's impact; do not chase it.
- **Deriving plane membership** (Pass D reports; building it is a separate decision).
- **Box casting as a projectile width mechanic.** Stage 2 is an arbiter over ties. A shotgun pellet and
  a sniper round wanting different thicknesses is a design lever for later, and letting a tiebreak
  dictate the weapon model would be the wrong reason to build it.
