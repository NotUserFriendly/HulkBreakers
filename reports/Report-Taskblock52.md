# Taskblock 52 Report — The ray chain

Passes A-F landed in order, with a supervised stop at the block's own **HARD PAUSE** between D and E.
Suite green throughout. **The flip landed: `CombatState.shot_resolver` defaults to `&"ray"` and the
ray chain resolves every shot.** Full suite green with the flag inverted — 281 scripts, 2664 tests,
0 failures, 288.1 s. The plane is not deleted and stays selectable by the same one field, for the
differential experiments and for a rollback.

## The two gating jobs, and what they turned out to be

Both were fixture defects. Neither needed a resolver change, and **both of my recorded diagnoses of
them were partly wrong** — the corrections are the useful content here.

**`BR52.08` was two cancelling defects, not one.** I recorded it as "`_make_weapon` authors no
`volume`". True, but `_make_shooter`'s HAND socket was *also* an identity transform, which puts the
hand — and so the muzzle — at world Y=0, on the deck. The missing volume was **hiding** the identity
socket, because `muzzle_point` returned its fallback before the socket chain was ever consulted.
**That is why my first attempt cascaded into three further failures**: fixing only the volume makes
every test in the file fire from the floor. I recorded that cascade as "it moves the muzzle for every
test at once", which described the symptom and missed the cause. Fixing both halves is
behaviour-preserving by construction — the weapon carries `data/parts/pistol.tres`'s box verbatim,
the HAND socket carries `DEFAULT_MUZZLE_HEIGHT` — so the baseline shooter now genuinely produces the
1.25 muzzle it was accidentally producing before, and `grip_y` finally reaches the muzzle.

**A prediction I marked in the test file was wrong.**
`test_a_hip_height_muzzle_behind_low_cover_hits_the_cover_not_the_target` was flagged as due to
invert on the flip, with the note that inverting would not be a regression. **It does not invert.**
It passes under both resolvers. The ~0.87 figure I measured was taken on the *broken* fixture; at the
real 0.3 grip height the round is at **0.4** where the 0.6 cover stands and strikes it. The test now
asserts what its name claims, for the first time in five blocks. Anyone reading the old marker would
have been told to expect a failure that never comes.

**The deflect fixture: the comment was right and the geometry was not.** It aimed along direction
(3, 4) but displaced the aim point sideways by 2.0. The plane treats that displacement as a
**parallel translation** of the whole flight, so the round still travelled at the stated ~37 degrees;
the chain aims at the displaced *point*, which **rotates** the flight — the real muzzle-to-aim vector
was (1.4, 0.5, 5.2), meeting the face at **16 degrees**, inside steel's 30-degree threshold.
Removing the lateral offset makes the real flight equal the stated one under both models, and the
cover then has to sit where that stated ray actually goes: cell (3, 2), not (2, 2). **No angle was
swept for**, which the block was explicit about avoiding. The incidence is printed into the run log
rather than asserted on trust: **37.25 degrees**.

## Measurements re-taken after the final fixes

Per the rule that a measure predating code updates is no longer trustworthy:

- **Suite cost, plane default → ray default:** `shot_planes` **14 965 → 9 079**, wall time
  **370.6 s → 288.1 s**. The remaining plane builds are the aiming job the plane keeps (centre mass,
  aim layers, AI line-of-fire) plus the parity experiments that deliberately run both models.
- **An intermediate figure I should not be quoted on:** a mid-work run reported 9 153 plane builds
  and 305.8 s. That run had only the first fixture fixed and the deflect fixture still failing; the
  numbers above are from the final green run.
- Two orphaned `DirectionalLight3D` nodes in `test_world_palette.gd` are unchanged by this work and
  predate it.

## Plan item closed by the flip

**`docs/PLAN.md`'s *Wide scatter passing through a wall seam* is answered and removed.** It was a
design call among three candidates; Pass A answered two and the chain answers the third. `BR34.05` is
the same decision from the other direction, is `SUPERVISOR`-owned, and stays `Pending`.

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
- **The aim preview was moved onto the active resolver** (Pass E). `AimController._resolve_hit` built
  its own `ShotPlane` purely to answer "what is under the reticle", so `docs/08`'s pillar held only by
  two implementations agreeing. The alternative was to leave the preview on the plane permanently,
  which would have made the number shown and the number computed drift the moment the flag inverted.
- **`test_aim_controller.gd`'s corpus test was extended, not repointed.** Pinning "the preview equals
  `ShotPlane.resolve_ray`" after the flag inverted would have asserted that the preview *disagrees*
  with the resolver — the exact drift that test exists to catch, inverted. It now checks both models
  against their own resolver.

## Tests that failed, then were corrected

Four failed and were corrected during A-E; two were defects in the code and two in the tests. Pass F
then updated a further 15 blocking fixtures, and the pattern there is worth stating once: **each was
restated in terms of the rule it protected rather than bumped to match new output.** Impact counts had
been standing in for pull counts, for "one attack fired", and for "the round reached its target"; none
of those survive a round that continues past what it hit. Where a premise died outright — a burst test
requiring *"at least one real miss"* on a board where nothing can miss any more — the fixture was
rebuilt on an unfloored grid rather than the assertion weakened.

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

**A fifth, and it is the most valuable one in the block: an existing test caught a real bug in the
chain the moment the ray became the default.** `test_penetration_traverses_body.gd` failed on the
lodged-bullet mechanic (tb20 C4, "punched in, could not punch out") because the chain cleared its
hollow-cavity flag **before** checking whether the round actually cleared the far face — silently
deleting the mechanic on the new path. The fixture held the right assumption and the new path was
wrong, which is exactly the kind of failure a flag inversion is supposed to surface.

A sixth is worth recording although it was my expectation rather than a test: the first version of
`test_an_axis_aligned_tie_falls_through_to_closest_root` asserted the wrong stage. Correcting it is
what surfaced that closest-root cannot fire (see Open questions).

## `SUPERVISOR`-owned entries moved to `Pending`

- **`BR34.05` — misses vanish instead of striking anything.** The ray chain is the default now, so
  this is live in the game rather than behind a flag. Under test: **0/360 empty** across a
  72-angle x 5-offset sweep in a closed room, **59/59** shallow downward shots landing, and the seam
  experiment **56/200 -> 0/200**. **To see it:** fire wide — a late pull of a long chaingun burst at
  range is the shape that used to vanish — and fire *down* at the deck, which previously had no
  geometry at all. Every round should now leave a mark on something.
  **Its recorded diagnosis was also wrong and has been corrected in the entry**; the cause is the
  plane's parallel-ray scatter model, not wall rects failing to tile.

## What the flip still needs

**Nothing. Both jobs are done and `BR52.08` is closed** (`CC`-owned, moved to
`docs/BUGS-ARCHIVE.md`). This section is kept rather than deleted because the two items it listed are
where the corrections above attach.

## Withdrawn from the ledger by the supervisor

- **The click hitch (filed as `BR52.05`, withdrawn same day).** *"52.05 isn't a bug as we're
  investigating as part of the new build process immediately."* Per the standing rule that defects in
  a system actively being built are symptoms of work in progress rather than ledger entries, it lives
  here instead. **The observation is still worth keeping**, because the supervisor's own revision is
  the useful part: it is not selection-specific — *"it seems to occur when clicking any unit for a
  purpose... selecting the active unit... clicking a unit to aim at... clicking a unit to confirm
  aim."* Three intents, three code paths, one symptom points at something they share rather than at
  any one handler. And it is a **discrete** cost on a click, distinct from `BR51.14`/`BR26.02`, which
  are motion costs. If it needs an instrument, `ShotPlane.builds` is the one to reach for first: one
  build measured **~8 500 usec** on a 217-blocker board this block, and a twelve-round burst measured
  **20 builds**, so a click that rebuilds a plane several times would produce exactly this shape.

## Open questions

- **CLOSED — the flag flip and the 14 failures behind it.** All 14 were fixture updates and all are
  landed; the suite is green with the ray chain as the default. The history is kept because two of my
  framings of it were wrong and the corrections are recorded below rather than quietly dropped.
  **They clustered as *more impacts than expected*** — a 12-round burst logging 36, "3 pulls x 9
  pellets" logging 61 rather than 27 — which is what a round continuing until its damage runs out
  looks like now that floors are real geometry: it punches through its target and goes on to strike
  the deck. **The one live consequence for future work: an impact count is no longer a proxy for
  "one attack fired" or "the round reached its target".** Assert on which surface was met first.

  **CORRECTION (2026-08-02): the three options I offered were wrong, and two of them described the
  same thing.** I asked whether a spent round should keep marching. **It does not, and never did** —
  `RayChain` returns the moment `spill <= 0.0`, so a round stops when its damage is exhausted rather
  than when it runs out of geometry. That was "option 2", i.e. already the behaviour. The extra
  impacts are rounds that genuinely still carry damage and punch onward because they can.
  **So there is no design change here to make**, and the supervisor's read is the right one: a
  shotgun pellet penetrating that effectively is a *balance* problem, to be answered when ammo types
  land, not a resolver one. **That reclassifies the Pass F failures**: they are fixture expectations
  encoding the plane's old behaviour and want updating, not a decision.
  **CORRECTION: the low-cover failure is not a chain defect and `AttackAction` is fine.** I reported
  it as one on the strength of a probe that fired *level* rays and saw them strike the cover
  correctly — the probe never reproduced the slope, which is the entire difference. Re-probed on the
  real geometry: **the plane models a shot as travelling at a constant height** (`_find_next` tests
  every region at the aim point's own `y`), so a round from a 1.25 muzzle at a 0.5 chest sits at 0.5
  all the way and clips 0.6 cover. **The chain marches muzzle-to-aim-point, which slopes** — measured
  at **0.845** where that cover stands, correctly clearing it. A real round slopes; the chain is
  right and the fixture encodes the approximation. **So all 14 are fixture updates**, and the flip is
  mechanical work rather than a diagnosis.
- **The parity evidence adoption was approved on**, kept here because it is what the decision rests
  on. Seam: plane 56/200 empty, ray 0/200. Differential over 216 seeded shots:
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
- **RESOLVED — `closest root` (tie stage 3) stays as cheap insurance** (supervisor, 2026-08-02),
  although it cannot fire in any tie that can currently be constructed. The reason it cannot is
  structural: the condition that *creates* an axis-aligned tie — the ray lying on the two cells'
  shared plane — makes every point on that plane equidistant from both roots, whatever the muzzle
  offset (measured: both at 7.08872365951538). Stage 2 takes every angled tie (9 of 9); the geometric
  stable order takes every axis-aligned one. Recorded as measured-dead in a test that says to update
  rather than delete it if that ever changes.
- **Two flagged numbers that are not design decisions yet.** `RayTiebreak.PROBE_RADIUS` (0.05) exists
  only to give the arbiter probe a corner that can lead — **it must not become a projectile width**,
  which the taskblock is explicit is a later lever. And the floor's 0.2 box thickness has no DT effect
  today because no material authors a `dt_curve`; it wants a real answer the moment one does.
- **`BR35.04` and `BR35.07` are already closed**, so this block's acceptance line "a deflection's
  drawn path is its resolved path" is not about reopening them. `BR35.04` was closed by *deleting* the
  decorative tracer on your instruction. The chain now produces a real second segment — asserted to
  start exactly where the first ended and to end on real geometry — so an honest tracer is buildable
  again. **Not built, and not built unasked.**
- **Membership should be derived, and there is a concrete shape for it** (asked for and answered
  2026-08-02; still not built, deliberately). The same gap has been found four times from four
  directions (`PartPicker` versus the plane scanning different pairs; `InspectPanel`'s non-unit path
  as `BR51.25`; and `BR52.01`, where picker and renderer disagreed about the *height* of a collection
  they shared). Nothing structurally prevents a fifth.

  **The shape:** not a new container and not a per-box `Callable` visitor — the first duplicates
  state, the second costs an invocation across ~1300 boxes on the hover hot path, which is the sin the
  plane was committing. Instead: drop `RayCaster`'s `CombatState` dependency (it only touches
  `units`, `grid` and the log) so it takes what `PartPicker` is already handed; add a `kinds` filter
  over the open `RayHit.KIND_*` vocabulary, applied at the source so a caller that must not see floors
  never pays to test them; then `PartPicker.hit` becomes a thin call into it, mapping `RayHit` to the
  dict its callers already expect. `InspectPanel`'s non-unit path consumes the same.

  **Two behaviour changes that want a decision, not an assumption:** the picker would inherit **tie
  resolution** (it has none today), and **joints would become pickable** unless filtered off — tb09 D
  says a joint is aimable, so the aim UI may want them, but hovering highlighting a joint handle is
  visible. Default it off.

  **Its own block, not this one.** `PartPicker.hit` runs on every mouse motion and carries two open
  perf entries (`BR35.01` mitigated-not-fixed, `BR51.14` open); the per-motion figure needs re-taking
  either side of the change, and folding that into the block that replaced the resolver would make a
  regression impossible to attribute.
