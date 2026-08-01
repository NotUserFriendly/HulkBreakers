# Taskblock 52 Report — The ray chain, at the hard pause

Passes A, B, C and D landed in order and the block is stopped at its own **HARD PAUSE**, awaiting a
decision on adoption before Passes E and F. Suite green throughout. **Both models are alive behind
`CombatState.shot_resolver` and the plane is still the default** — nothing has been switched over,
and nothing has been deleted.

## Decisions made without asking

- **`Part.is_destructible` was made real.** The flag is declared in `part.gd` and set `false` on
  `ship_floor` and `ramp`, and **no logic anywhere read it**. That was harmless only while floors
  could not be shot; the moment Pass D gave surfaces geometry, a 1-hp indestructible deck plate would
  have been destroyed by the first round and rooms would have grown holes in their floors. The
  alternative was to give floors a large hit-point total, which is a balance number invented to hide
  a modelling gap. An indestructible part now takes the round and stops it but never reaches zero.
- **Floor geometry was authored as data, not synthesised in code.** `ship_floor` and `ramp` gained a
  `volume` whose top face sits at the surface height. The alternative — a synthetic box built inside
  `RayCaster` — would have meant a designer could not add a walkable surface without a code edit.
  **The 0.2 thickness is flagged, not designed:** no shipped material authors a `dt_curve`, so
  `dt_at` ignores thickness entirely today.
- **Six `DamageResolver` helpers were made public rather than copied** (`roll_crit`, `crit_effects`,
  `resolve_joint_hit`, `resolve_destruction_consequences`, `inflict_lodged_wound_if_inside`,
  `body_of`). The chain decides *where* a round goes; what happens when it arrives stays the one
  resolver. The alternative was a second copy of the crit and destruction logic in the new path,
  which is the parallel system this project keeps deleting.
- **Joints were put into the march** (`assembly_placements(include_joints)`, default false). Not
  asked for. Without it every joint hit would have shown up in the differential as a disagreement for
  no reason other than one model not knowing joints exist.
- **`Closest root` was kept even though it is measured-dead.** Deleting a stage the taskblock
  specified is a design call. It is recorded as never-firing in a test whose doc comment says to
  update rather than delete it if that changes.
- **`PartPicker` was fixed as well as the caster** (`BR52.01`). It was outside the strict scope of a
  resolver block, but leaving the aim UI hit-testing at a different height from the thing resolution
  marches through would have been two answers to one question.

## Tests that failed, then were corrected

Four failed and were corrected; two of those were defects in the code and two in the tests.

1. **A penetrating round struck the same plate six times.** Found by *reading a printed log*, not by
   an assertion — the chain resumed past the struck box's **entry** face, which leaves the round
   inside it. `ray_box_hit` reports the exit face now. There is an assertion for it, plus one for
   `hollow` parts, whose enter-and-exit pair is the one case that legitimately strikes one box twice
   and had no coverage at all (nothing in shipped data sets `hollow`).
2. **The differential reported 152 of 216 shots as `different_part` while its own printed detail
   showed both models striking `wall/STOP_DEAD`.** The comparator compared `Part` by object identity
   across two independently built boards. **This is the most dangerous failure of the block** — it
   would have read as a catastrophic parity failure and been believed, because the headline number
   looked like exactly the kind of thing a replacement resolver gets wrong.
3. **An attribution check scored the ray chain at 51%** by rounding hit coordinates to cells. A hit
   lands exactly *on* a box face, and a coordinate sitting at 0.5 rounds into the neighbouring cell —
   the test was measuring its own rounding. Replaced with a real point-to-box distance; the honest
   figure is 100%.
4. **A joint fixture made the joint unreachable by construction.** A 0.2 x 0.2 x 0.6 arm centred on
   the socket entirely swallows the 0.12 joint cube, so the test was measuring the fixture. The plane
   would not have hit it either, for the same reason.

A fifth is worth recording although it was my expectation rather than a test: the first version of
`test_an_axis_aligned_tie_falls_through_to_closest_root` asserted the wrong stage. Correcting it is
what surfaced that closest-root cannot fire (see Open questions).

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** `BR34.05` is `SUPERVISOR`-owned and the ray chain satisfies its stated rule under test
(0/360 empty in a closed room, 59/59 shallow downward shots landing), **but the ray chain is not the
default**, so nothing the supervisor could look at has changed yet. Moving it to `Pending` before the
flag inverts would be claiming a fix nobody can see. It is left `Active` with a corrected diagnosis
and the measurements behind it.

## Open questions

- **The adoption decision itself — this is the hard pause.** The evidence points one way on every
  axis the taskblock named. Seam: plane 56/200 empty, ray 0/200. Differential over 216 seeded shots:
  **zero cases where the plane hit and the ray missed**, 64 where the reverse is true. Attribution:
  the plane's reported hit point lies on the surface it claims to have struck in **100 of 152** cases;
  the ray chain in **216 of 216**. Cost, release build: **6 715 → 2 021 usec per shot (3.32x)** and
  **148 829 → ~24 256 usec per 12-round burst (6.1x)**. The taskblock called burst cost "the one
  number that could sink this"; it inverts, because the amortisation the plane was credited with is
  not something it performs — a 12-round burst builds **20** planes.
- **The recorded cause of `BR34.05` and of `PLAN.md`'s *Wide scatter passing through a wall seam* was
  wrong, and both documents have been corrected.** The 56/200 reproduces exactly — in an 11x11 room
  and no other. The mechanism is not adjacent wall rects failing to tile; it is that the plane models
  a scattered round as a ray **parallel** to the shooter-to-target line, translated sideways by the
  whole dartboard displacement, so a wide offset relocates the entire flight — muzzle included —
  outside the building. A 41x41 room swept at 90 angles x 41 offsets produces **0/3690** empties, so
  there is no measurable seam. Two of that plan item's three candidates are therefore answered.
- **`Closest root` (tie stage 3) cannot fire, and the reason is structural.** The design's argument
  was that the gun's offset from the centreline separates two cells' roots. But the condition that
  *creates* an axis-aligned tie — the ray lying on the two cells' shared plane — makes every point on
  that plane equidistant from both roots, whatever the muzzle offset. Measured: both at
  7.08872365951538. Stage 2 takes every angled tie (9 of 9) and the geometric stable order takes
  every axis-aligned one. **Options:** delete stage 3, or leave it as insurance against a tie shape
  nobody has constructed yet. Evidence points at deleting it; it is your call, so it is still there.
- **Two flagged numbers that are not design decisions yet.** `RayTiebreak.PROBE_RADIUS` (0.05) exists
  only to give the arbiter probe a corner that can lead — **it must not become a projectile width**,
  which the taskblock is explicit is a later lever. And the floor's 0.2 box thickness has no DT effect
  today because no material authors a `dt_curve`; it wants a real answer the moment one does.
- **`BR35.04` and `BR35.07` are already closed**, so this block's acceptance line "a deflection's
  drawn path is its resolved path" is not about reopening them. `BR35.04` was closed by *deleting* the
  decorative tracer on your instruction. The chain now produces a real second segment — asserted to
  start exactly where the first ended and to end on real geometry — so an honest tracer is buildable
  again. **Not built, and not built unasked.**
- **Membership should be derived, and Pass D reports rather than builds it.** The same gap has now
  been found four times from four directions (`PartPicker` versus the plane scanning different pairs;
  `InspectPanel`'s non-unit path as `BR51.25`; and `BR52.01`, where picker and renderer disagreed
  about the *height* of a collection they shared). Nothing structurally prevents a fifth. The tell
  that a derived query is right will be `PartPicker` becoming a thin **filter** over it — the picker
  deliberately should not return floors.
