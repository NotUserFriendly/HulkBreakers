# CHANGELOG.md — What's Been Built

### taskblock-52 — the combat log stops corrupting itself (`BR52.04`)

**`FileSink`'s own doc comment said "Appends to a real file". The code opened with
`FileAccess.WRITE`, which truncates. The mismatch between the two was the bug.** Two sinks alive on
one path — a new bout attaching one while the old is still open — meant the second reset the file to
zero while the first still held a handle tens of kilobytes in; its next write landed at that stale
offset and the kernel zero-filled the gap.

**Measured on a real session log: 49 403 of 138 436 bytes were NUL**, one contiguous run starting at
byte 1073. **Worse than it sounds**, because `file` then classifies the log as `data` and **`grep`
silently declines to match it** while `tail` still renders fine — so it reads as healthy to a human
and returns nothing to every tool. Several greps against that file came back empty during this
session before the cause was found.

**A new bout appends; a new session rotates** (supervisor, 2026-08-02). A bout is not a session:
several bouts in one run share a log, and the next run archives it into
`out/logs/combat-YYYYMMDD-HHMMSS.log` before starting clean. **The live path deliberately does not
move** — `tail -f`, `grep` and the startup "log: <path>" line all point at `out/combat.log`, and
there is only ever one live session, so it is the archive that needs distinct names. Rotation is
**per path and once per process**, not per construction, or a second sink attaching mid-session would
rotate the log out from under the first — the exact case this whole entry is about. The archive is
named for **when that session ran** (the file's own modification time), so a name describes its
contents, and the stamp is sortable so a directory listing is already in session order. Two defences, answering different halves: open with `READ_WRITE` so nothing truncates
(`WRITE` survives only as a create-if-missing fallback), **and** `seek_end()` before every write,
since two live handles each carry their own position and opening at the end would not survive the
second one.

**The regression tests were verified by re-breaking the fix**, not merely by passing. Reverted to
`FileAccess.WRITE`, both fail — and that also showed the corruption is not only the large-offset NUL
case: at small scale the stale handle writes *mid-line*, producing
`move: from the second sinkmove: the first sink is still alive`.

**`BR35.08` (detonations are invisible) closed on the owner's instruction** after the supervisor saw
an explosion trigger naturally. Recorded as owner-directed rather than CC-verified — no change in
this block targeted it; what moved underneath it was taskblock-51's detonation work. `BR51.21` (no
injection ever animates) is untouched, so a debug-forced blast still cannot draw.

**`BR52.05` (the click hitch) withdrawn from the ledger by the supervisor** — actively being
investigated as part of current work, so it belongs in the report rather than the bug list, per the
standing rule about defects in systems still being built.

### taskblock-52 Passes E and F — the dartboard is an input device, and the flag inverts

**The aim preview stopped being a second resolver.** `AimController._resolve_hit` built its own
`ShotPlane` and walked it, purely to answer "what is under the reticle" — so `docs/08`'s pillar (the
tooltip and the damage come from the same call) was true only by two implementations agreeing. It
follows `CombatState.shot_resolver` now, so preview and shot go through **one** query by construction.
`test_aim_controller.gd`'s corpus test was extended rather than repointed: it checks both models
against their own resolver, which is strictly more than it checked before.

**The ray path is the simpler of the two, which is the point of the split.** The dartboard already
produces a world point — `AimPlaneGeometry.world_point` is where `AimView` draws the reticle — so B
exists before resolution is asked for anything, and the shot is muzzle-to-B. The plane path has to go
through `ray_from_muzzle`, whose own doc comment explains that vertical aim is expressed by *moving
the muzzle's height* while keeping `dir.y == 0`, because the plane's coordinates cannot carry a tilted
ray. A march needs no such convention. Asserted: a click at a screen position recovers the aim point
the reticle was drawn from, and the impact sits on the muzzle-to-reticle line to 0.000000.

**Pass F: adoption approved, and the flag flip is NOT landed.** The parity case holds and
`ShotPlane` is neither deleted nor retired — but **inverting `CombatState.shot_resolver` red-lights
14 tests**, and Pass F's acceptance is a green suite with the flag inverted. Flipping it anyway would
be hacking around a failure. The plane still resolves shots; the ray chain is fully built, tested and
selectable by one field.

**What the 14 are, recorded so the next session starts with them.** They cluster as *more impacts
than expected* — a 12-round burst logging 36, "3 pulls x 9 pellets" logging 61 rather than 27 — which
is what a round continuing until its damage runs out looks like now that floors are real geometry: it
punches through its target and goes on to strike the deck. **That is arguably correct under
`BR34.05`'s own rule and it triples impact counts, log volume and tracer draws.**

**Corrected 2026-08-02:** CC framed this as an open design question about whether a *spent* round
keeps marching. It does not and never did — `RayChain` returns as soon as `spill <= 0.0`, so a round
stops when its damage is exhausted. The extra impacts are rounds that still carry real damage. The
supervisor's reading stands: a pellet penetrating that effectively is a **balance** problem for when
ammo types land, not a resolver one — **so the Pass F failures are fixture expectations encoding the
plane's behaviour, not a decision waiting on anyone.** At least one failure is a different shape:
`test_attack_action.gd`'s low-cover obstruction case resolves to the target instead of the cover —
and **the raw march handles that correctly in isolation** (probed: level shots from muzzle height
0.30 and 0.50 both strike the cover at t=1.50; 0.80 clears it), so the fault is in how `AttackAction`
composes the aim point, not in the chain.

**What `ShotPlane` is still for, since Pass F asks:** its **aiming** job, and nothing else — centre
mass (`center_of`/`depth_of` for the default aim point), aim-layer enumeration for the layered-target
UI, muzzle self-obstruction, and the AI's line-of-fire and overwatch predicates. That is exactly the
boundary `docs/02` states, so it is not left jobless and does not retire in a later block on current
evidence.

**A real bug in the chain, caught by an existing test the moment the ray became the default.**
`test_penetration_traverses_body.gd` failed on the lodged-bullet mechanic (tb20 C4, "punched in,
could not punch out"): the chain cleared its hollow-cavity flag **before** checking whether the round
actually cleared the far face, which silently deleted the mechanic on the new path. The fixture held
the right assumption and the new path was wrong.

**And a second harness gap, beyond `BR52.02`.** That failure raised a script error, which opens a
**debugger break that halts the run waiting for input** — a ten-minute timeout that looked exactly
like a hang. Recorded on `BR52.02`, which is already about a test file's failure being invisible to
the gate.

**`docs/SUPERSEDED.md` carries six rows** for the reversal: the plane as resolver, the parallel-ray
scatter model, the approximated incidence angle, floors being in no resolver at all, the dead
`is_destructible` flag, and the aim preview's own second resolver.

### taskblock-52 hard pause — both models alive behind a flag, the plane still the default

**`CombatState.shot_resolver` chooses the model**, per bout rather than as a global static so a
differential can put one board through both without mutating shared state, and so a test switching
resolvers cannot leak into the next. `dup()` carries it — a preview must resolve the way the real
bout will, or `docs/08`'s pillar breaks. `ShotResolution.resolve_point` is the dispatch;
`ShotPlane` is untouched and still the default.

**`_aim_point_world` is the single conversion between the two aiming vocabularies.** The plane takes
`(origin, direction, lateral offset)` and tests every candidate at a constant lateral; the chain takes
a muzzle and an aimed point. One conversion means the differential compares one shot rather than two
similar ones.

**Seam sweep, both models, same room:** plane **56/200 empty**, ray chain **0/200**. On a room large
enough to hold every offset both are 0/945, so the ray chain's zero is not merely the absence of the
plane's own defect.

**Differential, 216 seeded shots, 11-room:**

| | count |
|---|---|
| agree | 33 |
| ray hit, plane missed | 64 |
| different part struck | 113 |
| different outcome | 6 |
| **plane hit, ray missed** | **0** |

The direction that would be a defect is empty. **And the disagreements are explicable, measured
rather than asserted:** of the plane's 152 hits, only **100 (65.8%) report a hit point that actually
lies on the surface they say they struck**; the ray chain is **216/216 (100%)**. The plane
reconstructs a hit coordinate from `(depth, lateral)` where `depth` is the struck cell's *centre*
projected on the shooter-to-target line rather than the face the round met, so a third of its
reported impacts name a place that is nowhere near the thing they hit. That is the `different_part`
bucket. The 6 `different_outcome` cases are STOP_DEAD versus DEFLECT on the same surface — the
incidence angle, which the plane approximates and the chain solves.

**Cost, release build, and it inverts the concern:**

| | plane | ray chain |
|---|---|---|
| one shot | **6 715 usec** | **2 021 usec** (3.32x faster) |
| a 12-round burst | **148 829 usec** | **~24 256 usec** (6.1x faster) |
| builds per burst | 20 | — |

Debug figures track (8 368 → 2 424, 3.45x). The taskblock named the burst cost as "the one number
that could sink this"; it does the opposite, because the amortisation the plane was credited with is
not something it performs.

**Determinism holds on both paths**, and traversal is **geometric rather than dictionary order** —
asserted by building the same room with its blockers inserted in reverse and checking 52 headings
give identical answers. The plane's `sort_custom` over `Dictionary` iteration is stable only because
map generation is seeded; the march never consults insertion order.

**A comparator bug in the differential, caught before it was believed.** The first version compared
`region.part` by object identity across two independently built boards and reported 152 of 216 shots
as `different_part` while its own printed detail showed both models striking `wall/STOP_DEAD`. It
compares part id plus landing cell now. A second measurement bug in the same session: an attribution
check that rounded hit coordinates to cells scored the ray chain at 51%, because a hit lands exactly
on a box face and a coordinate at 0.5 rounds into the neighbouring cell — replaced with a real
point-to-box distance, which is where 100% came from.

### taskblock-52 Pass D — membership dissolves: floors are ordinary geometry, and a dead flag wakes up

**The ray marches all four collections.** `ShotPlane.build` looped `state.units` and
`grid.blockers`; `PartPicker` looped those plus `grid.field_items`; **neither looked at
`grid.surfaces`**. That absence is the whole of `BR34.05`'s "or the floor" half — a round angled
slightly down had nothing to intersect, so "miss" was not a wrong branch being taken, it was the only
branch that existed. Measured: **59/59 shallow downward shots land** inside a closed room.

**Floors got geometry as data, not as code.** `ship_floor` and `ramp` now carry a `volume` — a
full-cell box whose **top face sits exactly at the surface height**, matching the flat quad
`BoardView._build_terrain` draws there. A designer adding a new walkable surface adds a Part with a
volume; no code edit, and no synthesised stand-in box in the caster.

**The 0.2 thickness is flagged, and it is not a balance number today.** No shipped material authors a
`dt_curve`, so `MaterialEntry.dt_at` returns the flat `dt` regardless of thickness — the floor's box
depth has no DT effect at all right now. Nothing on screen contradicts any value under the level
step either, since the renderer draws a zero-thickness quad. **Worth a real decision the moment a
`dt_curve` is authored**, and flagged as such rather than presented as settled.

**`Part.is_destructible` finally does something, and it had to.** The flag is declared in `part.gd`
("False marks permanent terrain... that can never be destroyed") and set on `ship_floor` and `ramp`,
and **no logic anywhere read it** — a dead field, harmless only because nothing could shoot a floor.
`ship_floor` carries `hp = 1`, so the first round to strike a deck plate would have destroyed it,
`BodyProjector.projects()` would have stopped projecting it, and rooms would have developed holes in
their floors. `apply_damage_to_part` now refuses to damage or destroy an indestructible part — it
still stops the round, it simply never reaches zero. Floors stay at 1 hp rather than being given an
invented hit-point total. Blast radius checked rather than assumed: only `ship_floor` and `ramp` ship
with the flag false; walls are explicitly destructible (tb31 Pass C) and `test_map_gen.gd` asserts it.

**Surfaces are placed at their own height, not the cell's.** `_consider_surface` reads
`surface.height` and `surface.facing` directly rather than going through
`UnitGeometry.true_height_for_cell`, which resolves to a cell's *first walkable* surface — a catwalk
over a floor would otherwise place both at the lower one's height. Asserted with two stacked surfaces
at one cell.

**Every remaining miss has a named reason, asserted rather than waved at.** On an open, unwalled
board a shallow enough round genuinely leaves the map, which `docs/02` counts as legitimate. The test
asserts a shot misses **exactly when** its own flight would run past the board before reaching the
deck — 3 of 59, each shallower than the board is long. The first version of that test asserted 29/29
on an open board, got 26, and was wrong.

### taskblock-52 Pass D — reported, not built: should membership be derived?

The taskblock asks whether the four collections should be replaced by one "everything occupying
space" query that the ray, the picker and the inspect preview all consume, and explicitly asks for a
report rather than a build.

**Yes, and the evidence is that the same gap has now been found three times from three directions.**
`PartPicker` scanned two collections while the plane scanned two different ones; `InspectPanel`'s
non-unit path was a third instance (`BR51.25`); and `BR52.01` was a fourth — the picker and the
renderer disagreeing about the *height* of the collection they did share.

**The next absent collection is not prevented structurally.** Nothing in the code says "these are the
things that occupy space"; each consumer writes its own `for cell in grid.<something>` loop, so a
fifth collection is found the same way these were — by someone noticing a shot passing through
something. `RayCaster.tied_candidates` is now the closest thing to a single answer, but it is one
consumer's private list rather than a shared query.

**What a derived query should be, when it is built:** `Grid` exposing occupancy, so the collections
become an implementation detail of the grid rather than a vocabulary every caller must know. The
tell that it is right will be `PartPicker` becoming a thin filter over it — the picker deliberately
should *not* return floors (clicking a floor selects the tile, which `BoardPicker` handles), so the
query must be filterable rather than one-size-fits-all.

**Not built here, deliberately.** It would touch every consumer in the same block that replaced the
resolver, which is exactly the attribution problem Pass F exists to avoid.

### taskblock-52 Pass C — ties resolve, log the stage that did it, and one stage turns out never to fire

**`RayTiebreak` has all three stages and every tie writes a `ray_tie` line naming the one that
resolved it.** The log was specified precisely because nobody knew the tie rate; measured now, from a
point source in a walled 21x21 room: **4 ties in 720 rays (0.56%)**, and 4 in 1440 — the extra angles
add none, because the ties are exactly the four axis-aligned directions.

**Stage 2, the box cast, earns its place: 9 of 9 angled ties.** The probe is a box aligned to the
ray, swept along it, represented by its four cross-section corner rays; each candidate is scored by
the earliest `t` any corner reaches it. For a ray at angle theta the cross-section basis tilts with
it, so one corner sits fractionally further downrange and reaches the shared face plane first — and
it favours the side the ray is angling away from, which is a fact about the approach rather than a
coin flip. **It iterates the tied set alone and returns one of its members**, so it is structurally
incapable of reporting a body the raycast did not find; asserted, as the taskblock asks by name.

**`PROBE_RADIUS` is 0.05 and is not a projectile width.** Box casting as a weapon property is
explicitly a later design lever, and letting a tiebreak dictate the weapon model would be the wrong
reason to build it. Flagged and tunable.

**Stage 3, closest root, has never fired — and the reason is structural, not a sampling accident.**
The design's argument was that "the gun is offset from the unit's centreline and the two cells'
centres differ, so root-to-root distance separates them." **The condition that creates an
axis-aligned tie defeats exactly that:** to meet two side-by-side cells at one `t` with an
axis-aligned ray, the ray must lie on their shared plane, and every point on that plane is
equidistant from both roots whatever the muzzle offset. Measured directly — both roots at
7.08872365951538 — so stage 3 is symmetric in precisely the case stage 2 defers to it in.

What actually catches those is the **geometric stable order** (cell, then part id), which is a
stronger determinism guarantee than the plane ever had: the plane sorted with `sort_custom` over
`Dictionary` iteration, which is insertion order and therefore a property of the map generator
rather than of the resolver.

**Closest root is kept rather than deleted**, because removing a stage the taskblock specified is a
design call and not CC's. It is recorded as measured-dead in
`test_closest_root_does_not_fire_in_any_tie_that_can_currently_be_constructed`, whose own doc
comment says to update it rather than delete it if a later change makes the stage fire.

### taskblock-52 Pass B — the ray chain: A to B, then C becomes B

**`RayChain` marches a projectile through the actual world.** A is the muzzle, B is the aimed point,
first hit wins; the angle of incidence is solved against the struck face; a penetration continues
the same ray and a deflection starts a new one, both through the same call. **0/360 empty** across a
72-angle x 5-offset sweep inside a closed room — the supervisor's standing rule from `BR34.05` is
satisfied and, for the first time, runnable.

**Three new logic classes, all headless.** `RayHit` (one struck surface: part, body, socket, real
face normal, thickness, cell, root origin, entry and exit) with `to_region()` so
`DamageResolver.resolve_impact` and every `ShotResolution` log consumer stay byte-for-byte unchanged;
`RayCaster` (the one "what does this ray meet" query, over units, joints, blockers and field items);
`RayTiebreak` (stage 3 today, closest root; the box cast is Pass C's).

**`UnitPicker.ray_box_hit` is the one slab test now**, and `ray_box_t` is a thin read of it. It
reports the face the ray clipped against, carried out through the placement's orthonormal basis —
which is what makes incidence native. **No `PhysicsDirectSpaceState`**: that needs a live scene tree
and would move shot resolution into the view layer.

**Six `DamageResolver` helpers became public rather than being copied** — `roll_crit`,
`crit_effects`, `resolve_joint_hit`, `resolve_destruction_consequences`,
`inflict_lodged_wound_if_inside`, `body_of`. The chain decides *where* a round goes; what happens
when it arrives is still the one resolver.

**Joints are in the march.** `UnitGeometry.assembly_placements` takes `include_joints` (default
false, so every existing caller and the whole view layer is unchanged) and emits one
`BodyProjector.JOINT_BOX_SIZE` box per occupied socket, carrying the socket on the `BoxPlacement`.
Without it every joint hit would have read as a ray-versus-plane disagreement for no reason other
than one model not knowing joints exist.

**A real bug the tests caught, and it was found by reading a log rather than by an assertion.** The
first chain advanced past the struck box's *entry* face, which leaves the round inside it — one
500-damage round logged **six impacts on one plate**. `ray_box_hit` now reports the exit face too,
and a penetration resumes past it. There is an assertion for it now, and a second for `hollow`
parts, whose entering-and-exiting pair is the one case that legitimately strikes one box twice
(nothing in shipped data sets `hollow`, so that branch had no coverage at all).

**`BR52.01` fixed, and it was two defects.** `PartPicker` hit-tested blockers and field items at
world height 0 while `BoardView._spawn_blocker` draws them at the cell's real height — and
`near_ray`'s cheap reject measured distance to a point on the *ground*, so a blocker on a cell
raised by 2.0 was **rejected outright** for any ray passing above ~3.0, the exact failure that
reject's own doc comment says must never happen. Both now read `true_height_for_cell`. Proved
against `BoardView`'s own placement call rather than a re-derived expectation.

**`BR52.02` filed, not fixed:** a test file that fails to parse is dropped from the run and the
suite still exits 0. Walked into it while renaming `_near_ray` — ten tests vanished and the gate
stayed green.

### taskblock-52 Pass A — the seam baseline, re-taken, and the recorded cause overturned

**The 56/200 figure reproduces exactly, and it does not mean what both living documents said it
meant.** `SeamSweep` (`src/logic/seam_sweep.gd`) is taskblock-35's uncommitted harness rebuilt and
committed: a shooter in a fully enclosed room, shots swept over angles x lateral offsets, counting how
many resolve against nothing. Parameterised by the thing that fires, so the plane and the ray chain are
measured by one instrument rather than two.

**Reproduced at 56/200 in an 11x11 room** — and only in an 11x11 room. Sweeping room size showed the
count tracking the room, not the walls: 9-room 80/200, 11-room 56/200, 13-room 24/200, and **17, 21 and
31-rooms zero**. That is the shape of a measurement of the *room*, not of a projection artifact.

**Three measurements say the recorded diagnosis is wrong.** `BUGS.md` (`BR34.05`) and `PLAN.md`
(*Wide scatter passing through a wall seam*) both record the cause as adjacent wall cells' projected
rects failing to tile edge-to-edge, letting a wide dartboard point thread a real gap.

1. **The threshold is the wall's own face.** Swept in 0.25 steps along one axis: every offset to **5.25**
   hits, every offset from **5.50** misses. The perimeter wall box's outer face is at exactly 5.50. A
   seam would scatter empties across offsets and angles; this is one clean edge sitting on the geometry.
2. **The vanishing rounds start outside the building.** `DamageResolver` tests every region at a
   *constant* lateral offset, so a scattered round is modelled as a ray **parallel** to the
   shooter-to-target line, translated sideways by the whole dartboard displacement. At lateral 6.0 in an
   11-room the flight begins at (5.00, 11.00) — `in_bounds` false. It never reaches the wall to thread it.
3. **No seam is measurable.** A 41x41 room, 90 angles x 41 offsets out to 15, every offset well inside
   the walls: **0/3690 empty.**

**So the defect is in how scatter is modelled, not in how walls are projected** — and the ray chain
fixes it structurally rather than by patching, since a march from the real muzzle to the aimed point
diverges from the gun the way a real round does.

### taskblock-52 Pass A — the plane does not amortise across a burst, and the cost case rested on it

**A 12-round chaingun burst builds 20 shot planes.** `DamageResolver.resolve_shot` builds its own plane
on entry — every pull, every pellet, every ricochet hop — so the plane `BurstAction` builds up front is
used only to pick the aim point. The stated trade ("one build serves a whole burst, then N cheap
point-in-rect tests, where a ray chain pays per round") describes something the code does not do.

Measured on a real 217-blocker board (`tools/shot_cost_bench.gd`, debug build):

| | usec |
|---|---|
| plane build (1291 regions) | **8 509** |
| one shot (build + walk) | **8 549** |
| of which the walk | **~260** (noise; one run measured -52) |
| one 12-round burst | **183 000** |
| planes per burst | **20** |

**~97% of a shot's cost is building a plane it then barely uses** — 2.44% of regions contain the aim
point in the test fixture. `test_shot_plane_amortisation.gd` pins the counts (deterministic and
machine-independent) rather than the timings.

**A number that informed the decision turned out to be stale.** `BR26.02` recorded `ShotPlane.build` at
**35 258 usec**; a bare build on a comparable board now measures **8 509**. The two were taken through
different call paths — the historical figure came off `aim_state()`, which also cloned the state before
taskblock-51 memoised it — so this is not a claimed 4x win, it is a warning that the figure the trade
was being argued from no longer describes the thing it names.

**`tools/bench_release.sh` takes a `BENCH` env var** (`ai_planning` default, `shot_cost` new) and
`bench_main.gd` takes `--bench=`; every existing invocation is unchanged.

### taskblock-51 — a CC-owned sweep: `BR35.03` confirmed closed, `BR35.01` mitigated

**`BR35.03` was already fixed and only needed confirming**, exactly as its triage predicted. taskblock-42
Pass E gated the board rebuild on `DebugVerbs.affects_board(verb_id)` and **both** overlays carry it.
Closed on a reading, with no change made — recorded that way rather than as a fix.

**`BR35.01`: a cheap reject before the per-box test.** `PartPicker.hit` ran a full assembly ray test
against every blocker and field item regardless of the ray's direction — a handful of props when it was
written, 200+ wall cells since tb31 C, on every mouse motion. It now skips a cell whose perpendicular
distance from the ray exceeds `SKIP_RADIUS`. **18 454 -> 14 390 usec per motion (54 -> 69 fps)** on the
same probe this block has used throughout; with the earlier tooltip fix that is **42 527 -> 14 390**, a
third of the original.

**Stated plainly: this is a mitigation, not the structural fix.** The scan is still linear in blocker
count with a cheap reject in front; a spatial index is the real answer and was not attempted. The reject
is conservative by design — admitting a cell the real test rejects costs time, rejecting one that would
have been hit is a shot through a wall.

### taskblock-51 — detonations reach cover, chain in waves, and go off where they actually are

**Cover takes the blast.** `detonate()` iterated `state.units` and nothing else, so a barrel beside a
barrel could not chain and an explosion beside a wall left it untouched — the same units-only assumption
that had hidden the drawing gate. Blockers in radius now take the damage.

**Chaining is the supervisor's stated shape:** *"chain react simultaneously, then in order, they should
never re-explode something that's already exploded."* Everything in one wave goes off together and its
damage lands before the next wave is decided. **Termination is the exploded set, not a depth cap** — a
bound that says "this cannot go on forever" is not the same as one that says "nothing goes off twice",
and only the second was asked for. Two barrels in range of each other are the case that loops without it.

**And a blast is centred on the exploding part, not its owner's cell** — the supervisor's catch:
*"an ammo rack on a unit's back may be higher up or offset."* `_locate_cell` returns the unit's cell, so
a mounted part detonated at its wearer's feet. `UnitGeometry.assembly_placements` already composes each
part's real world transform — what renders the box and what `PartPicker` hits — so that is asked rather
than a second answer derived. Measured: a mounted plate logs `(5.00, 1.25, 5.15)` where it used to log
`(5, 0, 5)`. **The test uses a sub-part deliberately**: the shell root legitimately sits at the unit's
base, so a root-part fixture passes on the broken version too.

**`Detonation` is now its own file**, split from `DamageResolver` when chaining pushed that past its
1000-line cap. `DamageResolver.locate_cell` became public rather than copied, since a second "where is
this part" would be the parallel system this project keeps deleting.

**Filing correction (supervisor):** defects in a system actively being built are not bugs, they are
symptoms of work in progress, and belong in the report until the system settles. Three entries CC had
filed were withdrawn on that basis; the session's one real defect — a part destroyed by an explosion
vanishing from inspect while staying on the model — is filed as `BR51.24`.

### taskblock-51 — `set_part_hp` is a board-changing verb

One line, and it explains a paired symptom the supervisor reported: a barrel forced to 0 hp stayed drawn
while inspect showed an empty tile. `set_part_hp` was absent from `BOARD_CHANGING_VERBS`, so
`sync_board_view()` never ran after it — correct while the verb only changed a number, wrong the moment
`BR51.20` let it destroy things.

**The remaining reports from that session are filed rather than fixed**, because each is a decision:
`BR51.21` (no injection ever animates — the overlay never calls `ResolutionPlayer.play()`, which is why
the explosion sphere cannot appear on this path), `BR51.22` (detonations damage units only, never cover —
`detonate()` iterates `state.units` and nothing else), and `BR51.23` (a detonation is centred on the
owning unit's cell, so an ammo rack explodes at its wearer's feet — the supervisor's own catch, and CC
chose wrong).

### taskblock-51 — `BR51.20`: zeroing a part now runs its failure mode, and one place emits a detonation

`BoutInjector.set_part_hp` set the number and stopped. `DamageResolver.resolve_part_failure` — the only
thing that runs MANGLE / DISABLE / DETONATE / FRAGMENT / MELTDOWN — had exactly one caller, inside impact
resolution. So a goo barrel forced to 0 hp sat there intact, and **forcing a detonation, the entire point
of being able to target a barrel (`BR51.02`), never worked**. Nothing in this block had ever set one off.

**`resolve_part_failure` takes a nullable `ImpactResult`** and writes results only when there is one, so
the injector invents no hollow stand-in — that would have been a second failure path beside the
resolver's.

**And the detonation event moved to where the failure happens.** It was emitted by
`ShotResolution.log_impact_result` off the impact, which meant a failure with no impact resolved
mechanically and logged nothing. `DamageResolver` emits it now: one emitter, both callers.

**Two costs, recorded rather than glossed:** the event is centred on the exploding object's own cell
rather than the bullet's strike point (more correct for an explosion, but it is a change), and it logs
**unattributed** — `ImpactResult` carries no attacker, and threading one through three layers for a
visual fix was not worth it. That is a real loss against the previous emission site.

**This is a synthetic failure, and the supervisor's caveat stands:** what matters is a barrel getting
shot, and this forces the consequence without the cause. It makes the consequence observable; it does
not verify the shot path, which is `BR51.01`'s job.

### taskblock-51 — a detonation draws because it detonated, not because it hurt someone

**The supervisor's argument closed a gap CC had merely documented:** *"if something is exploding, isn't
it a part? Shouldn't it always draw because it catches itself in the explosion?"*

`DamageResolver.detonate()` iterates `state.units` only, and a goo barrel is a **blocker** — so it is
never in its own blast list. Gating the drawn sphere on `detonated_units` therefore hid every explosion
that caught nobody, which is most of them. `ImpactResult` now carries **`detonated`**: that it went off,
which is a different fact from whom it hurt, and it is what the event is emitted on.

CC had recorded this as a known gap needing "a fact the resolver does not currently return". The fact was
one line; the reason it stayed a gap is that CC treated a documented limitation as a resolved question.

### taskblock-51 Pass C — `BR35.08`: detonations are visible, at their real size

Built to the supervisor's spec: a translucent red sphere from the detonation point, growing outward to
the **actual explosion radius**, then fading. **Grow : fade is 1 : 3**, and the total is a tunable beside
the other bullet timing (`DETONATION_MS`, 1000 ms).

**The radius travels in the log rather than being chosen in the view**, which is the whole point — a
drawn extent computed view-side would be `BR35.04`'s decorative tracer wearing different clothes. A new
`detonation` event carries the centre and `part.detonate_radius`, and is emitted **once per explosion**;
the existing `detonate` events are one *per affected unit*, which is right for damage bookkeeping and
would have stacked one sphere per victim.

**Known gap, stated rather than hidden:** a detonation that harms nobody produces an empty
`detonated_units` and so draws nothing. Reaching it needs a "this part detonated" fact the resolver does
not currently return, distinct from "these units were hurt" — the same shape as `BR34.05`, where absence
of a thing to hit is indistinguishable from nothing having happened.

### taskblock-51 Pass C — continuations are dull orange and flash with their own hit

Both supervisor-specified. A penetration or a ricochet is the **same round still travelling**, so it now
draws in a dull orange (`TRACER_CONTINUATION_COLOR`) rather than sharing the primary's bright flash —
the blue it replaces was chosen for the decorative projection deleted in `BR35.04` and made a
continuation look like a second, unrelated shot.

**And a pull's hops flash together rather than in sequence.** An event whose successor continues it is
started without being awaited, so only the final hop of a pull is waited on: one trigger pull is one
visual event, a bright primary with its dull-orange continuations alongside. `BR27.03` records that
these were always supposed to resolve simultaneously; taskblock-27 Pass A2's `DEFLECT_BEAT_MS` was a
deliberate pause built on the opposite assumption and is now unused rather than merely reclassified.

**Guarded against the obvious over-reach:** a *new* pull is never folded into the one before it, and
only an `impact` can continue a pull — a `move` or `faced` between hops ends it, so a tracer is never
drawn concurrently with an unrelated animation.

### taskblock-51 Pass C — a hop is not a new shot (`BR27.03` / `BR34.01` pacing)

**The supervisor's correction to the previous entry:** deflects should be *visible*, the blue lines were
simply reporting something that did not happen. *"When a bullet is fired, I want to be able to see what
it hit, and then where it went."* That is what removing the decorative projection leaves — the real
continuation. `resolve_shot` returns one `ImpactResult` per hop and `resolve_and_log_point` logs them
adjacently, so a ricochet that finds a target already draws from the deflection point to its real hit.

**And the pacing was the other half.** *"All shots would land and tracers flash, THEN the deflections
would flash, even though logically a shot would land and deflect right after each other."*
`ResolutionPlayer.play()` inserted `INTER_SHOT_BREAK_MS` between **every** consecutive impact, so a
single trigger pull that hit a wall and carried on read as two gunshots a tenth of a second apart.

Impacts now carry a **`hop_index`** — 0 is the shot, anything higher continues it — and only hop 0 takes
the between-shots break. A round reads as one object travelling rather than as a reply to itself. The
decision is a named static (`starts_a_new_pull`) so it can be asserted directly instead of by measuring
wall-clock gaps, and an event with no `hop_index` defaults to starting a pull, so fragments, misses and
pre-existing logs are never silently glued together.

**Still open in this cluster:** `BR35.07` (`STOP_DEAD` overshoot), `BR34.05` (misses vanish — a logic
defect, not a drawing one), `BR35.08` (detonations draw nothing), and `BR34.01`'s other half, the bright
flash replaying per hop rather than once per pull.

### taskblock-51 Pass C — `BR35.04`: the decorative deflect projection is deleted

**The cluster's suspected shared root, located.** `ShotResolution.log_impact_result` stamped
`deflect_end_*` on **every** DEFLECT: the reflection direction pushed out to `max_range`, with its own
comment stating the intent — *"so the reflected direction is always drawable regardless of whether a
real ricochet hop follows it"*. `ResolutionPlayer._play_impact` then drew that as a second, blue
segment. A line to an arbitrary distance, corresponding to nothing that resolved, and on screen
indistinguishable from a real hit. It invented the wall impacts the supervisor spent a review session
investigating.

**Removed, not reconciled** — the supervisor's explicit call. A ricochet that finds a target logs its
own `impact` with a real origin and hit point and draws through the ordinary path; one that finds
nothing now draws nothing, which is the truthful answer. `ImpactResult.reflected_dir`/
`reflected_vertical` are untouched; the resolver needs them to recurse.

**Four existing tests asserted the defect** and had to be rewritten, not merely updated: "a deflect
draws a second tracer", "N deflects draw 2N segments", "the second segment is blue", and the
logic-side "a DEFLECT carries a deflect endpoint". None was wrong about what the code did; all four
were wrong about what it should do, and together they held the defect in place. A fifth was added: a
log written *before* this change still replays without inventing geometry, because the view no longer
reads those fields at all.

**What this does NOT yet fix, stated so the cluster is not assumed closed:** `BR35.07` (`STOP_DEAD`
drawn past its hit point), `BR34.05` (misses vanish — which is a *logic* defect, "miss" being modelled
as terminate-the-round rather than continue-until-something-stops-it), `BR34.01` (every hop replays the
full hit flash), `BR27.03` (inter-event sequencing) and `BR35.08` (detonations draw nothing, which needs
the supervisor's specified growing red sphere). The primary tracer was confirmed faithful — it draws
real `origin_*` to real `hit_*` — so those four are not instances of this same substitution.

### taskblock-51 — `BR51.11` (the long way round), corpses as wrecks, and the catch-up theory disproved

**`BR51.11`: `tween_method` interpolates plain numbers.** `ResolutionPlayer` handed it raw orientations,
so 0.1 -> 6.0 ran 336 degrees left instead of 24 right. It now tweens towards
`from + angle_difference(from, to)` — the same facing, numerically adjacent to the start. **The test
asserts the arc, not the endpoint**, because the broken version arrives in the right place too; verified
by reverting, where four of six angle pairs take the long way. Squad 1 and not squad 0 is a
distribution of starting facings, not a squad rule, and that is pinned so the fix is not read as a
squad-specific patch.

**Corpses are selectable as wrecks** (supervisor's decision): *"Dead units should not be selectable as
units. They should be selectable in the same way parts on the ground or cover is."* Pass K is what made
this a one-line answer — a `PART` target already describes "a thing on the board with parts on it", so
a wreck needs no fourth kind. **Nothing can be commanded through one**, because only a `UNIT` target
reaches the queue; a wreck is inspectable and nothing else. Both click dict shapes resolve it.

**The catch-up hypothesis is disproved by the instrument built to test it.** Eight dumps all read
`fastest 3915.8 (prev 116.2, next 260.0)` — the frame *before* the spike was 116 fps, not a stall, so
the 0.255 ms frame is not paying back an overrun. The proposed `BR51.15`/`BR51.17` merge is withdrawn.
The maximum is still an artifact (a frame that did no drawing), so `BR51.17` stays open with the
catch-up remedy removed from its options. **Also visible: the game is not capped at 160** — `avg less
top 1%` reads 177-185, above the monitor's refresh, exactly the uncapped condition the supervisor
predicted when they specified these figures.

### taskblock-51 — the performance readout reports the fastest frame's neighbours

**The supervisor's question, made answerable:** *"Is it queuing frames for some reason, and when those
finally get to hit, they run over?"* A frame that takes almost no time because the previous one overran
reports a huge `1 / delta` — bookkeeping, not throughput.

Two readings in their live dumps support it. `instant` hit **212.6** against a 160 Hz cap, so
above-refresh frames are genuinely being produced; and the reporting fraction bounds the spike exactly
— **one frame in 4 585** sits within 1% of the maximum, an isolated outlier rather than the top of a
cluster.

The signature of catch-up is **adjacency**, so `PerfStats.fastest_neighbourhood()` returns the fastest
frame together with the frames either side of it, and `describe()` carries a sixth line:
`fastest 2013.4 (prev 7.9, next 148.0)` reads as a stall being paid back, while
`fastest 161.2 (prev 158.0, next 159.4)` is simply the fastest of a healthy run. **Both cases are
tested** — without the contrast case the figure could not tell them apart and would be decoration.

**This is what should decide `BR51.17`.** If the maximum is a catch-up artifact then anchoring the
top-1% cut to it is anchoring it to noise, and the fix is excluding frames that are not real frames —
not a different percentile. That is a better answer than any of the three CC offered, and it came from
the supervisor's observation. **Possibly one defect with `BR51.15`**: `min` has read 7.4 in every dump
this session, so if the fastest frame sits immediately after a ~7 fps frame, the stall and the bogus
maximum are the same event seen from both ends.

### taskblock-51 — `BR51.14`: hovering tiles cost a `CombatState` clone per mouse motion

**Measured before it was touched**, per the entry's own instruction not to assume it was `BR26.02`
again. On a 216-blocker board, one motion while merely hovering with a unit selected:

| | usec/motion | clones per 30 calls |
|---|---|---|
| before | **42 527** (23 fps) | 48 |
| after | **18 454** (54 fps) | 19 |

The supervisor reported 160 fps falling to ~20, which the first number matches almost exactly.

**The cause was not the per-event rate, it was a clone.** `TooltipController.refresh()` was connected
to **both** `hover_changed` *and* `mouse_moved` — and `mouse_moved` fires unconditionally on every
motion, while `refresh()` calls `SelectionController.previewed_unit()`, which is a `CombatState.dup()`.
Following the cursor across one tile does not change a word of what the tooltip says, so `mouse_moved`
now only **repositions** (`TooltipView.move_to`, which already existed privately) and rebuilds only when
the hovered target changes or the queue's revision does — the latter because `TileInspection` runs from
the *previewed* unit, so a queued move changes what a tile reads as without the hovered cell moving.

**And the hover is coalesced to one update per drawn frame**, which the reticle got in `BR26.02` and
this path did not. A 500-1000 Hz mouse against a 60-160 fps game ran it hundreds of times per frame.
Safe for the same stated reason: it is an absolute raycast through the literal cursor, not an
accumulated delta. The companion test asserts an idle frame still costs nothing, so the per-event cost
was removed rather than moved.

**The remaining 19 clones are real rebuilds** — one per genuinely new hovered tile. Memoising
`previewed_unit()` is where the next win is, and `BR26.02` recorded two attempts at it that were
reverted for concrete reasons (callers mutate the previewed unit; state changes within a frame), so it
is left alone rather than retried blind.

### taskblock-51 Pass L — death mid-turn, and an indicator fixed on one call site out of two

**`BR51.09`: the selection invalidates on read, not on an event.** `SelectionController` never
referenced `alive` anywhere, so `selected_unit` was a raw reference that outlived the unit it pointed
at — kill the acting unit and its reachable-cell overlay kept drawing into the next unit's turn.
Notifying the selection from `kill_unit` would have put a TACTICS-time concern inside a RESOLUTION-time
mutation and still missed every *other* route by which a unit stops being valid, so `selected_target`
now guards on read. **A call site cannot forget to subscribe to something it does not subscribe to** —
asserted by killing a unit behind the controller's back and never telling it. The unit's queued plan
goes with it, since `_queues` is keyed by unit id.

**`BR27.07`/`BR32.09`: the same bug, unfixed on the second call site.** tb32 Pass D deferred the
active-turn flip until after playback in `SquadControlOverlay`, with a comment calling it "a real
confirmed bug" — and changed only that one caller. `SpectatorOverlay._advance()` went on applying the
highlight *before* `resolution_player.play()` drew the previous unit's move. That is exactly the
supervisor's controlled comparison — *"the indicator moves to the next unit before the animation
completes when the AI is controlling; it moves with the unit correctly when the player is
controlling"* — and the reason the player path passes today is that a human turn ends *after* its own
animation, so it never exposes the gap. The AI path now defers and applies identically.

**Coverage gap, stated rather than papered over.** The deferral primitive is tested directly:
`apply_highlight = false` genuinely withholds the flip, `apply_active_turn_highlight()` genuinely
performs it, and the default still applies. **Driving `_advance()` end-to-end headlessly is not
covered** — a spy standing in for `ResolutionPlayer` hangs the runner rather than failing it, since a
runtime error under `-d` becomes a debugger break. The ordering inside `_advance` is verified by
reading it against the player path it now matches.

**Not decided, deliberately: whether a dead unit is selectable.** The addendum asks for that to be a
decision rather than a consequence, and Pass K made "select the wreck" expressible. It is a design
question and is left to the supervisor — what Pass L fixes is the stale pointer, which is not the same
question.

### taskblock-51 — `BR48.01`: the board was accidentally double-lit, and inspecting took the second light away

**Found by dumping the battle world rather than by reading the code** — two confident diagnoses had
already been wrong, and the dump settled it in one run. At rest, before anything is inspected, the
battle `World3D` had **four** lighting contributors: the board's own `WorldEnvironment` and
`DirectionalLight3D`, **plus the inspect panel's**. After one inspect cycle it had two.

`SubViewport.own_world_3d` **defaults to false**, so `InspectPanel`'s private `WorldEnvironment` and
`DirectionalLight3D` have been in the battle's world since the panel was built. Nothing looked wrong,
because the extra light only ever made the board brighter. It becomes visible the first time a subject
takes the **fallback path** — `open()` with no live view, which is what cover, a loose item or a bare
tile resolves to — because that sets `own_world_3d = true` and takes both nodes **out** of the battle
world. The board drops to its real single-light level and stays there, since `_isolate_clear()` never
restores the flag. **A new bout rebuilds the panel and the accidental second light comes back**, which
is the supervisor's own *"starting a new bout does fix it"* — the detail that proved it, and that
neither earlier theory could explain.

**The preview's lighting is now withdrawn whenever the viewport shares a world**, applied at build time
as well as on every transition, so the battle's lighting is constant. The flag itself is left alone:
assigning `own_world_3d` runs Godot's scenario attach/detach and errors with `Parameter "scenario" is
null` where no scenario exists yet — which is why "release the world on close" and "claim our own world
at build" were both tried and both abandoned.

**And the brightness is restored, as a measurement rather than a new number.** The supervisor preferred
the old look, so `WorldPalette.BOARD_LIGHT_ENERGY = 2.0` puts the board back at exactly what was on
screen: the two lights were identical in rotation and energy, therefore additive, therefore 2 x 1.0.
**Ambient is deliberately not doubled** — the two `WorldEnvironment` nodes were *not* additive (Godot
resolves one winner) and both carried the same `AMBIENT_COLOR`/`AMBIENT_ENERGY`, so ambient never
changed. `directional_light()` takes an optional energy defaulting to 1.0, so `BuilderScene` — which has
no second viewport and was never doubled — is untouched.

**Correction to this entry as first written:** it named `WorldPalette.LIGHT_ENERGY` as the tunable.
**No such constant existed** — `directional_light()` never set `light_energy` at all, so the board ran
on Godot's default 1.0. `BOARD_LIGHT_ENERGY` is new.

### taskblock-51 — `BR48.01`, second attempt (superseded by the entry above): the preview's lighting nodes

**The supervisor's own diagnosis, and it was right:** *"this may not be a UI issue, it may be lighting
as the inspect panel draws the clicked item, and the lighting might be custom there, and then said
lighting doesn't get reset to board style."*

`InspectPanel._preview_viewport` carries a `WorldEnvironment` **and** a `DirectionalLight3D` for its
fallback path, which renders a fresh copy in its own isolated world. The isolate-camera path — what a
click on a live item takes, so the panel shows the *actual* unit on the field — needs the opposite,
`own_world_3d = false`, and that puts **both nodes into the battle's `World3D`**: a second environment
and an extra directional light over the whole board. The comment beside them already flagged that a
second `WorldEnvironment` there "isn't a well-defined 'also applies' situation", and solved it only for
the preview camera via a per-camera override; the main camera was left to whatever Godot resolved.

It persists after closing because **`_isolate_clear()` deliberately never touches `own_world_3d`** — its
own comment says so, written in taskblock-22 for an unrelated reason. Inspect one live subject and the
viewport stays world-shared for the rest of the session.

**The fix ties the preview's lighting to who owns the world**, not to open/close: while the world is
shared, the light is hidden and the environment detached, so it is never in the battle world in either
state. The preview camera's own `environment` override already gives it the right ambient regardless of
which world it lands in, and the subject is lit correctly because it genuinely is on the board. The
fallback path keeps its lighting, which is the only lighting in its isolated world.

**Two approaches were tried and abandoned first, both recorded because each failed for its own reason.**
Releasing the shared world in `close()` asks Godot to detach a viewport from a scenario it has already
left — `Parameter "scenario" is null`, an error rather than a no-op — and reordering `close()` to
release before hiding did not help, because the detach is invalid regardless of order. Making the
assignment idempotent removed a redundant flip but not the genuine one. Tying the lighting to world
ownership avoids the flip entirely.

### taskblock-51 — `BR48.01`, first attempt: an empty modal on a bare tile

**The trigger was the open path, not the close one**, exactly as the supervisor's re-diagnosis said.
`Grid.blockers.get(cell)` is **null for a bare tile** — `open_tile`'s own doc says so — and the
spectator's fallback passed that straight in. The panel renders its matrixless shape regardless (every
`_refresh_*` no-ops gracefully on a null root, by design), so clicking empty ground opened a 900x600
modal containing nothing and paused the bout. It reads as a dim that will not lift because there is
nothing in the panel to explain what happened. A cell whose blocker the ray missed but whose ground
position was hit still opens — that is a real object, coarsely picked.

**"Does a second open/close make it darker" is now answered rather than eyeballed.** Stacking and
persisting are indistinguishable from the chair, so the tests read the real nodes back: the preview
camera's `cull_mask` is what `_isolate_focus` narrows, and `_isolate_clear` restores it from a value
captured once at build time and never re-derived — so it cannot ratchet. Asserted across two full
cycles and across opening a second inspect over the first, which is the close path that never presses
a button. **It does not stack.**

**The test that should have caught this was named for it.**
`test_clicking_a_bare_tile_or_a_tiles_object_opens_the_same_inspect_panel` only ever places a crate —
its name covers the empty case and its body does not, and the defect lived in that gap. Second instance
of narrower-than-its-name in this block, after the log fold's diagnostic assertion. Verified by
re-breaking the fix: both new assertions fail without it.

### taskblock-51 Pass K — selection understands more than units

**The root was a missing type, not a broken rule.** `SelectionController` held one slot,
`selected_unit: Unit`, while `PartPicker.hit` had always scanned `grid.blockers` and
`grid.field_items` — so the picker saw barrels, cover, walls and field items and selection had
nowhere to put them. Four reported symptoms were that one gap from different directions.

`SelectionTarget` (logic, headless) holds `UNIT` / `PART` / `CELL` plus an empty target that answers
questions rather than being `null`. **It wraps the hit dict `board_clicked` already emits** rather than
introducing a second vocabulary. `selected_unit` survives as a **derived property** — eighty-one
readers still mean it, and a second stored field would drift from the target.

- **Clicking cover selects the cover** (`TacticsController._click_part`), where it previously did
  nothing unless an action was armed. **This drops the unit selection**, which is a real behaviour
  change; the queue survives, being keyed by unit id.
- **A cell click with a unit selected is still a move order.** Tile selection was added where there was
  nothing, and nothing was taken away.
- **`BR51.02`'s remaining defect is closed at the source.** `click_cell`'s capture branch reported
  every non-unit click as a bare `CELL`, so cover could never become the debug panel's active target
  and every OBJECT-target verb inherited the hole — while the ray path resolved `PART` correctly. Two
  paths disagreeing about what a click means was the bug.
- **`BR51.10`: Inspect is disabled when the target has no body**, driven by the selection rather than
  by "has anything been clicked". `InspectPanel.open_tile` could always describe a loose part; the
  capability was simply unreachable from the board.
- **Spectator picks parts, not just units**, and **only opens the modal for what it can describe** —
  opening it for an unrenderable target left the dim over the board with nothing on top (`BR48.01`'s
  shape).

**A refusal names what it refused.** The `"refused"` status path already existed, so this was smaller
than triage assumed — what was missing is that it did not say *which* target it declined, which starts
mattering once a bare tile or a barrel can be the active one. It reads `Set Part HP: refused (cell
(4, 4))`. **Only OBJECT-param verbs name the target**: for the rest the active item is not what they
acted on, and naming it would report the wrong cause for their own failure.

**A bug found while building it:** `PartPicker.hit` returns `{unit, part, cell, t}` with **no `kind`**;
`board_clicked` emits `{kind, unit, part, cell}`. Routing a raw pick through `from_hit()` classified
every hit as a bare cell and stopped spectator unit clicks pausing the bout. Each shape now has its own
named constructor, and the trap is asserted.

### taskblock-51 — `BR51.13`: a plumbing run folds one kind, not any plumbing

`fps_dump` and `wall_cutout` are both plumbing kinds, and the fold grouped any consecutive stretch of
*any* plumbing kinds — so a framerate measurement between two wall-cutout events was swallowed by their
counted row. Runs now break on a change of kind: eleven consecutive `fps_dump` events still fold into
one row, so the anti-flooding purpose it was added for is intact.

**A passing test sat beside this the whole time.**
`test_a_diagnostic_keeps_its_own_row_and_is_never_folded_into_plumbing` protects the kind literally
named `diagnostic`, which is absent from `PLUMBING_KINDS` and never reached the folding code. Its name
claims a general rule; it asserts a membership check. **And an existing test asserted the defect** — it
required a mixed run to be labelled "2 log events". That test was not wrong about what the code did,
only about what it should do, which is the harder kind to catch.

**The current-state snapshot**, by system, with the taskblock that landed each. Grows as work ships.
For what changed shape along the way see `SUPERSEDED.md`; for what's next see `PLAN.md`.

**A changelog logs changes — it is not a code-you're-proud-of log.** Three kinds of entry belong here
that are easy to leave out, and all three are worth more than another success line:
- **Approaches tried and reverted.** "A greedy distance scorer was tried first and reverted, because it
  reproduces the concave-wall freeze" saves the next person from re-trying it. A dead end that isn't
  written down gets walked twice.
- **Partial wins, stated honestly.** "Halved the cost, did not eliminate it — the remainder is real
  per-cell geometry work" is the useful form. Rounding a partial fix up to a complete one is how a
  known-incomplete thing gets treated as done.
- **Audited and found correct.** When a sweep checks N sites and finds them fine, that conclusion is a
  current-state fact and belongs here — it is exactly what stops the next audit re-deriving the same
  ground. Record what was checked and *why* it holds, not just that it passed.

**When a later change overwrites an entry, mark the old one and point forward to the newer entry** —
don't silently leave a description that has stopped being true. A stale entry in a current-state
snapshot is worse than a missing one, because it still reads as authoritative.

*Current as of taskblock-48 Passes A–D landed — the suite has three rungs (a ~3.7 s targeted run, a
~126 s fast gate, a ~450 s full gate), one runner that both counts and fails, a run window in the game
that replays failing tests as real bouts, a shared bout corpus, and a budget that can finally see
view-only cost. taskblock-47 Passes A–E landed — the suite is profiled, budgeted on deterministic work
counts, split into a 119 s fast gate and a 537 s full gate, and audited down from 4545 turns to 1578.
**The block's biggest finding was not about the suite**: `CompletionSampler` had been naming a retired
playstyle as its profile id since taskblock-46 Pass E, so every completion rate measured in between ran
with the AI's profile weights switched off — the real figure is **72%**, not 56%, and `BR45.03`'s gap to
the old planner is 3 points rather than 19. Previously current as of the post-taskblock-46 search-memory fix — `ROAM`/`HUNT` no longer oscillate between two
cells (`BR46.01`, completion 56% over 100 seeds, unchanged within noise — the fix moved the failure
mode, not the rate), and the hunt for the other half of that report found that **16 of 40 generated maps
contain ground a unit can walk into and never leave** (`BR46.02`, open, a design call). taskblock-46
Passes A–F landed — AI v2 part three: raised rooms no longer punch pits
under cover and spawn tiles (BR40.03/BR40.04), the completion number is a random sample with a
deterministic escalation behind it rather than a pinned pessimistic window, four search verbs give a
unit with nothing in sight something to do, `Panic` names the give-up instead of shrugging silently, and
the `docs/11` tier table is filled in with an Elite depth 2–3 lookahead — **but nothing authors
`intelligence_tier`, so every unit in every measured bout is `TRAINED` and most of that table is
reachable from tests only.** Completion moved 54% → 60% across the block; `BR45.03` is narrowed, not
closed. The playstyle vocabulary is deleted outright and a bout names a `UtilityProfile` id directly.
taskblock-45 Passes A–E landed — AI v2 part two: the engagement-score planner is
deleted and a utility scorer over data-authored actions replaces it. Per-candidate `ShotPlane` casts
are gone outright (29.1 builds per turn → 0.0) and plan cost fell 485ms → 131ms, but **mission
completion fell 87.5% → 54.2% over 24 seeds and `MIN_COMPLETION_RATE` sits at 0.35 rather than its
old 0.5** — a known, characterized regression carried forward as `BR45.03`, and the highest-priority
AI item in `PLAN.md`. taskblock-44 Passes A–D landed — AI v2 part one: the release-vs-debug number
exists (~1.29x, so debug overhead is not the explanation), the line-of-fire query is inverted, the
WorldView information seam is in, and a unit's turn is navigable rather than frozen. taskblock-43
Passes A–D landed — the AI planning-cost block, whose most useful result is that the candidate search
it attacks is only ~25% of a planning turn and the LOF prefilter scan is the rest (see "AI planning
cost" below). taskblock-42 Passes A–E landed (F and G held — see below). taskblock-41 Passes A–F —
"Diagnostics: the log becomes the instrument" is closed, and so is "Checkpoints return as an ordinary
tool." The combat log now carries engine and script errors, pairs every command with its outcome and
a reason, narrates a bout build in construction order, and draws itself as a real window with a live
framerate on it. Checkpoints are a tool again rather than a gate, guarded in CI by parsing what
cannot be rendered. See `PLAN.md`.*

---

## Combat core

**Part graph** (tb01–02, docs/01/01a) — inverted attachment (parts declare `attaches_to`, sockets
declare `socket_type`); socket ids; socket transforms (sockets = joints, parts = bones); limb
decomposition; capability tags (`TRIGGER`/`SUPPORT`/`GRIP`/`POWER`) + weapon `requires`; keyed
cladding vs generic plates. Bot builder debug scene over the real `BodyAssembler`.

**Geometry & targeting** (tb02/06/07/23, docs/02) — continuous projection, no exposure table,
retaining each part's real vertical position (tb23 A: a head projects higher than a waist, no
longer flattened to one height plane); depth-sorted shot plane with gap fall-through (the sniper
thread); dartboard scatters isotropically in both the lateral and vertical axes (tb23 B);
`resolve_ray(muzzle, dir)` the resolution seam, now a true 3D ray — a shot can pass over a short
part into a taller one behind it, and a ricochet branches vertically as well as horizontally
(tb23 C); `READING`/`RESOLVES` never conflated. **Muzzle-anchor fix** (tb27 A1) — every attack
action now builds its shot-plane `origin` from the SAME shouldered-muzzle point as its `direction`
(previously `direction` used the shooter's cell, `origin` its own muzzle — the mismatch could
resolve a target at negative depth relative to the ray, animating as the burst firing backward).
Shot/deflect impacts also now hold a deliberate beat (`DEFLECT_BEAT_MS`) between the primary hit
and its own deflect tracer (tb27 A2), instead of both resolving in the same instant.

**One geometry: the 2D/3D shot-plane split closed, and the first slice of multi-level (tb36,
docs/02/PLAN.md)** — tb23 gave rays a real vertical component; the surfaces they resolved against
stayed 2D for three more taskblocks. Four passes, each re-running a seeded full-mission bout (seed
12354) and diffing its combat-log event stream byte-for-byte against the pass before it — every
pass landed with **zero observable change** to that bout, the standing proof that none of this
altered a single level shot.
- **Pass A** — `BodyProjector.project`/`project_assembly`/`project_part`/`_project_box` and
  `ShotPlane.build` widen to `Vector3` origins/directions; every existing caller wraps its flat
  `Vector2` with `y == 0.0`. Pure plumbing, provably inert.
- **Pass B** — `_FACE_NORMALS`/`_FACE_CORNERS` grow from four side faces to six (`+/-X`, `+/-Z`,
  `+/-Y`), each carrying its own real 4 local corners instead of the old 2-corner-plus-tilt-
  widening encoding. The visibility test is fully 3D now — a face's real world normal (including
  its vertical component) against the ray's own real 3D direction, not the horizontal slice alone.
  **Fixes the headline bug:** a part tilted so its local up is horizontal (`Poses.aiming()`'s own
  -45° shoulder tilt, taken further — `Poses.prone()`'s 90° tilt hits this exactly, and
  `test_prone_pose_changes_the_projected_shot_plane_vs_idle` now correctly shows a SECOND real face
  where the old four-face model only ever showed one) used to go edge-on on all four old faces
  simultaneously and vanish; it now projects a real region. A face genuinely facing the shooter
  registers even with a degenerate-height rect (an untilted horizontal face's own true property in
  this plane model — see the multi-level note below); the hollow far-face rule (tb20 C3) still
  emits exactly the entering/exiting pair, not the four extra faces six candidates could otherwise
  leak.
- **Pass C** — `ShotPlane.build` does its own height reconciliation once, at the source: a
  `_shear` step converts every region's `rect.position.y` from absolute world height into height
  relative to the ray's own real path, providing "height relative to here" — the two-path
  duality (`resolve_ray`'s own real-3D-ray path vs. `build`'s ground-heading-only path) never
  fully unified because `build`'s own `(lateral, real world height) x depth-along-ground` plane
  basis is deliberately not a full pinhole camera; `resolve_ray`'s own separate `muzzle.y +
  vertical_slope * depth` reconstruction is gone, replaced by reading a plane already built that
  way. Provably a no-op for every caller except `resolve_ray` (`origin.y`/`direction.y` both
  `0.0` everywhere else, still true after this pass). The dead-vertical bail stays — an honest
  `null`, not an arbitrary basis that would silently rotate the dartboard's own scatter axes.
  **Audited and found correct as scoped:** `DamageResolver`'s own separate `vertical_slope`/
  `_find_next` mechanism (ricochet flights only, `origin_height`/`vertical_slope` both `0.0` for
  every real first-hop caller today) is a genuinely different, self-contained value, not a
  duplicate of the gap this pass retired — flagged as a candidate to reconcile once Pass D's own
  elevation reaches a first-hop shot, not this pass's to touch.
- **Pass D** — `Grid.height` (row count) renamed `Grid.rows` in the same commit that adds
  `Grid.level` (a per-cell integer, defaulting to 0, alongside `terrain`/`opacity`) — the first
  real slice of multi-level maps (docs/PLAN.md). `Unit.level` (cached, synced from the grid at
  `CombatState.add_unit`) drives `UnitGeometry`'s own root-transform Y translation
  (`LEVEL_HEIGHT = 1.0`, docs/PLAN.md's own "two ramps make one full level" math, not a number
  invented here) and a matching raise in `ShotPlane.build` (`BodyProjector` composes a body in
  body-local space and has no notion of cell/level at all — elevation only enters where a cell's
  world position already gets composed in). Deliberately inert in normal play: `MapGen` writes
  nothing (the array's own default is already 0), and `Pathfinder` never reads `level` at all.
  `BoutInjector.set_cell_level` (+ a matching debug-panel entry) is the only way a nonzero level
  exists today — exactly the tool this needs before any movement verb can force a real scenario to
  watch. **Surfaced, not a bug:** an UNTILTED box's own top face is height-DEGENERATE in this
  plane's `(lateral, world-height)` basis — a single point, not a range (`Rect2.has_point` never
  contains any point when `size.y == 0`, confirmed live) — so a shooter standing above a target
  correctly produces a real top-face `Region` (proven in `test_multi_level_geometry.gd` by reading
  the produced Region back, per this file's own testing convention — never re-deriving the
  formula), but "resolving" onto that exact single point via `resolve_ray`'s own query would mean
  solving for one exact slope, not aiming. Only a genuinely TILTED face (this pass's own headline
  case) gains real height extent. **Out of this slice, staying that way:** vertical movement verbs
  (climb/hop-down/ramps/stairs), height-aware pathfinding, fall damage, height-derived combat
  bonuses — the rest of docs/PLAN.md's own multi-level item. **Superseded by tb37 below** — every
  item in that "out of this slice" list except fall damage/height-derived bonuses (deliberately
  still out) is now built.
- **Pass E (in progress, supervisor-driven)** — the view catches up to elevation. `ResolutionPlayer.
  _world_anchor` reads `UnitGeometry.true_height_for_cell` instead of hardcoding Y=0.0, and the new
  `&"climbed"`/`&"hopped_down"` log events (both now carrying the same `"path"` shape a `move` event
  does) route through the exact same `_play_slide` machinery — a climb or hop-down plays as a real
  vertical slide with no dedicated animation code. `HitVolumeView`'s team marker and facing wedge
  offset by `unit.height`. `BoutInjector.force_climb`/`force_hop_down` (+ matching debug-panel
  verbs) let the supervisor trigger either action live — no AI path queues them yet.
  **Root-caused and fixed a "no visual change on raise" bug:** `BoardView`'s ground was one flat
  `PlaneMesh` for the whole grid, never reading `Grid.level` at all. Replaced with `_build_terrain`
  — one flat top quad per cell at its own real height, plus vertical riser quads between
  differently-elevated orthogonal neighbors, a stepped XCOM-style terrace (supervisor's own call
  over a smooth heightmap). `_build_grid_lines` got the same per-cell treatment as a follow-up
  (it was still one flat mesh at a single world height even after the ground itself went per-cell)
  — each cell now draws its own complete border at its own height, so a riser boundary frames each
  side's own step instead of one line cutting through it.
  **Level precision widened, supervisor's explicit choice over two smaller alternatives:**
  `Grid.level`/`Unit.level` go from `int` to `float` — genuinely arbitrary elevation, not just whole
  levels plus a ramp's own fixed `+0.5`. `Pathfinder.MAX_CLIMB_LEVELS`/`MAX_HOP_DOWN_LEVELS` become
  real height caps; climb cost scales proportionally to rise (`CLIMB_COST * rise / LEVEL_HEIGHT`)
  instead of a flat per-level charge. `HopDownAction`'s drop-distance check now goes through
  `Unit.height`/`true_height_for_cell` (ramp-aware) instead of raw levels, converging with
  `ClimbAction`'s own convention. **Real bug found during the level-precision audit, not just
  plumbing:** `ShotPlane.build`'s cover/blocker projection used `grid.get_level(cell) *
  LEVEL_HEIGHT` directly, missing a RAMP tile's own `+0.5` rest offset that `BoardView._spawn_
  blocker` already rendered cover at — a hit on ramp-standing cover could land somewhere the
  rendered box never occupied. Fixed to read `UnitGeometry.true_height_for_cell` like the unit
  projection just above it already did.
  **Cell picking fixed too, a pre-existing gap the terracing exposed rather than caused:**
  `BoardPicker.cell_at_ray`/`plane_hit_t` (taskblock03 D1, predates multi-level entirely) always
  intersected a fixed `y == 0` plane — correct until a cell's own real top face could move off world
  0. Supervisor: "mousing over a cell requires you to mouse over the base of the terrain, not the
  top." Both now take an optional `grid` and iteratively resolve against the real terrain (guess a
  height, find the crossing, look up that candidate cell's own real height, repeat, capped at 4
  passes so a ray skimming a riser boundary still terminates); `grid` defaults to null, so every
  flat-board caller is unaffected. `TacticsController`/`SpectatorOverlay` thread their real grid
  through at every hover/click/debug-panel-pick call site.
  **Still open, per `PLAN.md`:** the camera at height and the wall cutout against elevation, both
  needing the supervisor's own eyes, not headless-verifiable.

**Multi-level: elevation reaches the game (tb37, docs/PLAN.md)** — tb36 built the geometry and left
it wired to nothing; four passes make level mean something. Same "one seeded full-mission bout,
diffed byte-for-byte" proof as tb36 for Passes A–C (an all-level-0 bout can't observe any of this);
Pass D's own `MapGen` change necessarily reshuffles the bout's own generated map, so its seed was
re-picked (12369→12373) instead — the test file's own established convention for exactly this kind
of change, documented five times over in its own header before this one.
- **Pass A** — real muzzle height and vertical direction threaded through all six `ShotPlane.build`
  callers (`AttackAction`/`BurstAction`/`LineOfFire`/`Overwatch`/`Suppression`/`TacticsController`),
  replacing each one's own hardcoded flat `Vector3(x, 0.0, y)`. New `ShotPlane.elevation_for()` is
  the one shared helper every caller now builds its plane from (real level DELTA between origin and
  target cells, never a shooter's raw muzzle height against a target's raw ground height — the
  former cancels correctly under a uniform raise, the latter would double-count the shooter's own
  above-ground muzzle offset). `ShotPlane.build`'s tb36 `_shear` step is now opt-in (a new `shear:
  bool` param, only `resolve_ray` sets it) — it was silently correct only because no other caller
  ever passed real elevation before this pass; once they did, unconditional shear broke every
  caller besides `resolve_ray`. **Real bug found and fixed, not just plumbing:** `DamageResolver.
  _find_next`/`resolve_shot`/`_resolve_slide` assumed a dartboard aim point's height was always
  anchored at depth zero (true only for a ricochet's own fresh continuation plane) — a first hop's
  aim point sits at the TARGET's own real depth instead, so every elevated first-hop shot silently
  resolved to nothing at all until a new `point_depth` anchor was threaded through the whole chain.
- **Pass B (BR36.01)** — fixed at the source: new `PartGraph.walk_with_joints()`/`Shell.
  all_parts_with_joints()` (NOT a change to `walk()`/`all_parts()` themselves — those back
  `living_parts()`'s hp>0 filter, and a joint handle's own hp defaults to 1 and is never touched by
  joint damage, so repurposing them would make every unit's own joints read as permanently-living
  parts). Used by all six self-exclusion call sites and by `DamageResolver._body_of`'s own ricochet
  continuation exclusion. **Live-fire finding:** the seeded bout diverged after this pass alone,
  isolated to the ricochet fix — a shot that deflects off a body could previously re-hit that SAME
  body's own joint region at point-blank range instead of continuing its flight, reachable at level
  0 all along, not an elevation-specific bug.
- **Pass C** — `Pathfinder.move_cost` becomes an edge cost (`from`, `to`), not a per-destination one:
  a new `Enums.TerrainType.RAMP` is ordinary pathing regardless of level delta (1 MP, no special-
  casing); climbing up with no ramp is capability-gated (new `Shell.can_climb()`, an open `CLIMBER`
  tag nothing authors yet) at 4 MP, capped at 1 level; dropping down with no ramp is always legal up
  to 2 levels at a flat 1 MP, no capability gate — the deliberate asymmetry makes one-way routes for
  free. Threaded through every construction site tied to a specific mover; `MapGen`'s own internal
  connectivity check stays at the default (cannot climb) on purpose. tb36's own "Pathfinder ignores
  level" acceptance test is deliberately now false, replaced.
- **Pass D** — new `Unit.height: float`, the real continuous world height (`UnitGeometry.
  true_height_for_cell`: `level * LEVEL_HEIGHT`, plus a fixed `+0.5` on a `RAMP` tile — a ramp's own
  `Grid.level` is authored at its LOWER endpoint, so resting on it is genuinely partway up) —
  `Unit.level` stays the discrete int gating decisions only. New `ClimbAction` (capability-gated,
  4 MP/level or 2 MP/half — the half case is a climb launched from a ramp tile) and `HopDownAction`
  (no capability gate, flat 1 MP, legal to 2 levels) as real queued actions. `MapGen` authors real
  elevation for the first time: a seeded fraction of rooms raised one level, each connected to the
  surrounding network by exactly one `RAMP` tile, backstopped by a general `_repair_stranded_
  elevation` flood-and-flatten pass (a raised room's single ramp can still get sealed by ordinary
  scattered cover landing on its approach tile, or by a wide corridor serving two OTHER rooms
  crossing through it — rather than chase every such topology by hand, anything a non-climbing
  `Pathfinder` can't reach from a real anchor gets flattened back to level 0). No deliberate
  climb-only pockets authored this pass. Height-derived combat bonuses deliberately NOT added — the
  "a shot from higher ground resolves against more of the target" claim is read back and asserted
  (`test_a_shot_from_higher_ground_resolves_against_more_of_the_target`), confirming it's already
  emergent from Pass A's own geometry, matching the taskblock's own explicit instruction not to
  author a bonus on top of it. **Out of this slice, staying that way:** fall damage/knockdown on
  deep drops, parts/perks raising the climb cap, ladders as authored content, arc'd shots and
  thrown-weapon height advantage, no AI path yet queues `ClimbAction`/`HopDownAction` and neither
  integrates with `MoveAction`'s own mid-move overwatch hook, view-layer elevation correctness
  (Pass E, fenced for the supervisor, not started).

**Floor and terrain become parts (tb38, docs/PLAN.md)** — the tb31 wall move, generalised: everything
walkable is a placed `Part` now, not a terrain code. Same "one seeded flat bout (all level 0, no
ramps), diffed byte-for-byte after every pass" guard as tb36/37; ramp-carrying content is
deliberately excluded from that guard and covered by its own dedicated fixture instead.
- **Pass A** — the placement model, consumed by nothing. New `Surface` (part + real world height +
  facing) and `Grid.surfaces` (`Vector2i -> Array[Surface]`, the same container shape
  `field_items` already established) sit alongside `terrain`/`level`, which stay authoritative. New
  `GridPlacement` is the attachment grammar: a part attaches downward (`GROUND` in its own
  `attaches_to`) only to a cell with no surface yet, or sideways to a free, type-matching `Socket` on
  an orthogonal neighbour's own surface — reusing `PartGraph.is_legal_attachment`/`attach` verbatim,
  never a parallel legality check.
- **Pass B** — `MapGen` authors two flyweight floor parts (`ship_floor`, `ramp`) onto every non-VOID
  cell, derived from the just-finished grid rather than rewriting the carve/ramp/repair machinery's
  own internals (the BSP carve legitimately re-visits the same cell more than once, which the
  attachment grammar correctly refuses a second time — `_author_surfaces` runs once, last, mirroring
  the finished terrain/level instead). A `VOID` cell gets no surface at all — "unfloored," not a
  terrain code.
- **Pass C** — height and pathfinding now read a cell's own placed surface, not `Grid.level`/terrain
  directly (`UnitGeometry.true_height_for_cell`, `Pathfinder`'s walkability/move-cost gate). Ramps
  become a real two-tile, 22.5° profile (`+0.5` level per tile, replacing tb37's one-tile 45° rise) —
  `MapGen._connect_with_a_ramp` places an inner (room-bordering) and outer tile with a shared facing;
  new `RampGeometry` pins the settled low/high/lateral edge heights (0 / +0.5 / +0.25), built and
  tested even though nothing renders it yet. Partial climb MP rounds up (a 1.2 MP climb charges 2).
  **Real bug found and fixed:** `_repair_stranded_elevation` never flattened a stranded `RAMP` tile,
  only a stranded `OPEN` cell — invisible under tb37's model (a ramp's own authored level was always
  0), exposed once the corrected model gives the room-bordering tile a genuinely non-zero level; now
  reverts a stranded ramp fully to plain ground. `test_full_mission.gd`'s seed re-picked
  (12373→12383) — the two-tile ramp reshapes which rooms get ramped, the same established pattern as
  every prior generator-reshaping re-pick.
- **Pass D** — scope revised by the supervisor mid-taskblock: not the `Grid.level`/`TerrainType`
  retirement itself (confirmed blast radius: 14–17 production files, 36–37 test files still read the
  pre-placement model directly), but making that retirement safe to run as its own follow-up block.
  New `GridLegacyBridge` consolidates three previously-scattered `surfaces.is_empty()` fallback checks
  into one instrumented seam; a full-suite run tallies **4,318,367** hits across three call sites
  (`Pathfinder._base_cost`/`move_cost`, `UnitGeometry.true_height_for_cell`) via a GUT post-run hook
  (`tools/legacy_grid_bridge_burndown.gd`) — the retirement block's own real acceptance test is this
  counter reading zero, not a grep. **Out of this taskblock, staying that way:** the actual
  `Grid.level`/`TerrainType.{OPEN,WALL,RAMP,VOID}` deletion and the void→lore-only vocabulary sweep
  (both the named follow-up block, `PLAN.md`); catwalks/bridges as authored content; floors
  projecting into the shot plane (BR34.05 stays open — would break this block's own byte-identical
  guard).

**Legacy grid model retired (tb39, docs/PLAN.md)** — the follow-up block tb38 Pass D split out:
deletes `Grid.level`, `Enums.TerrainType`, and `GridLegacyBridge` outright, migrating every
remaining direct reader and fixture onto the real placement model. Full suite ends at 2120/2120,
`GridLegacyBridge`'s own burn-down counter at zero (down from tb38's 4,318,367 hits), and a
grep finds no surviving `Grid.level`/retired `TerrainType` value/`GridLegacyBridge` reference
anywhere, tests included.
- **Pass A** — replaces the old pinned-seed "does THIS scripted mission reach extraction" harness
  (`docs/SUPERSEDED.md` — six re-picks, every one a legitimate mechanics change absorbed as noise
  instead of a signal) with a completion-RATE sampling test (`test_full_mission.gd`) built on the
  same `BoutSetup`/`DeepStrike`/`BoutRunner` path a real "Simulate Bout" menu uses, never a
  hand-rolled turn loop. Measured baseline: 12 seeds at a 100-turn cap, 1-vs-1 AGGRESSIVE
  `a_brand_laborer` bouts, ~80% EXTRACTED; `MIN_COMPLETION_RATE` set to 0.5, well below the
  observed rate but low enough to catch a real collapse — flagged as a tunable, not a design
  number.
- **Pass B** — `MapGen` carves into a private `MapGenScratch` (its own local `terrain`/`level`
  arrays, never `Grid`'s public surfaces API) and emits real `Surface`s once, at the very end
  (`_emit`), rather than authoring onto a real `Grid` mid-carve the way tb38 Pass B did — carving
  legitimately re-visits the same cell many times (splitting rooms, re-cutting corridors, the
  emergency fallback corridor), which `Grid.surfaces`'s attachment grammar correctly refuses a
  second `GROUND` placement onto; scratch has no grammar to fight at all. `MapGenScratch.
  place_surface` is the one shared formula both `as_temporary_grid()`'s mid-generation
  reachability grids and `_emit`'s real final authoring use, so the two can never drift apart.
- **Pass C** — the three legacy-bridge readers (`Pathfinder._base_cost`/`move_cost`,
  `UnitGeometry.true_height_for_cell`) read real placed surfaces unconditionally now, no fallback;
  `GridLegacyBridge`'s counter confirmed at zero across the full suite before deletion. New
  `test/support/grid_fixture.gd` (`GridFixture.flat`/`place_floor`/`place_ramp`/`place_wall`)
  builds real placed `Surface`s for a fixture instead of hand-set terrain arrays — the single
  mechanism used to migrate roughly 55 test files off the legacy model, each proven to still fail
  for its own reason (anti-vacuity) after migration. `Pathfinder._terrain_costs`/`_min_possible_
  cost` and `CombatState.terrain_costs` retired outright as dead weight (only ever read inside the
  now-deleted legacy-bridge branch); `Pathfinder.new(grid, can_climb)` drops the parameter. New
  `Surface.is_ramp_at(grid, cell)` de-duplicates a ramp check `Pathfinder`/`ClimbAction`/
  `HopDownAction` each held their own private copy of. **Two real bugs found via migration, not
  cosmetic swaps:** `test_climb_action.gd`'s ramp-climb test was pinned against
  `GridLegacyBridge`'s superseded flat `+0.5` ramp offset (tb37) — migrating onto a real placed
  ramp `Surface` changed the asserted cost from 2 MP to 3 MP, matching `RampGeometry.
  STANDING_OFFSET` (tb38 Pass C's already-corrected value); the test itself was stale, not the
  game. `test_squad_control_overlay.gd`'s real-raycast click test broke once a wall got real 3D
  geometry — `PartPicker.hit()` can report a closer blocker hit than a unit hit, so a wall on the
  shooter/enemy's shared view-axis column could occlude a click; fixed by reorienting the fixture
  perpendicular to the camera's default view axis, not by weakening the click test.
- **Pass D** — full rename, not a partial one (explicit call): `Enums.TerrainType`
  (`OPEN`/`WALL`/`SPAWN_A`/`SPAWN_B`/`VOID`/`RAMP`) → `Enums.SpawnMarker`
  (`NONE`/`SPAWN_A`/`SPAWN_B`, an explicit `NONE = 0` sentinel since a fresh `Grid.spawn_marker`
  array already defaults every cell to `0`); `Grid.terrain`/`get_terrain`/`set_terrain` →
  `Grid.spawn_marker`/`get_spawn_marker`/`set_spawn_marker`; `Grid.level`/`get_level`/`set_level`
  deleted outright, no replacement field. `MapGenScratch` gets its own local `CellKind` enum
  (`UNCARVED`/`OPEN`/`RAMP`/`EMPTY`) — never reuses `Enums.SpawnMarker`. `TileInspection` gets its
  own local `PhysicalState` enum (`EMPTY`/`OPEN`/`RAMP`) for its tooltip classification, since
  `Grid`'s enum no longer represents any physical fact at all. `GridLegacyBridge` and
  `tools/legacy_grid_bridge_burndown.gd` deleted outright. Vocabulary sweep: "void" retired for
  the physical-absence state everywhere in code/comments (lore-only from here on, e.g. the ship
  setting); "empty"/"unfloored" instead — `MapGenScratch.CellKind.EMPTY`, `AsciiRender.
  CHAR_EMPTY`, `BoardView.EMPTY_BORDER_COLOR`/`EMPTY_FILL_COLOR`/`_build_empty_indicators`,
  `TileInspection.PhysicalState.EMPTY`. **Checked and found correct:** `MapGenScratch` never
  reaches for `Grid`'s public spawn-marker/blocker API outside `as_temporary_grid()`'s documented
  blocker pass-through; `map_gen.gd` touches `Grid.spawn_marker` only inside
  `_place_spawn_zones`/`_mark_zone`, confirmed by the file's own source-scanning acceptance test
  (`test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking`). One test-suite-only bug
  found during the final full-run verification: `test_determinism_check.gd`'s own custom compare
  lambda still read `a.terrain`/`b.terrain` post-rename, a stale reference with no production
  impact (caught by the very first full-suite run after the rename, not shipped).

**"Void" retired from code entirely (tb40 Pass A, docs/PLAN.md)** — tb39 Pass D's vocabulary sweep
left the word alive in ~44 identifiers/comments and left open whether the rule was prose-level or
grep-strict; settled grep-strict, since "voidhulk" is the game's own lore term and a future grep for
it needs to return lore only. Four distinct categories, not one find-and-replace: `WorldPalette.VOID`
(the 3D environment's background color, not tile coloring) → `WorldPalette.BACKDROP`, naming the role
rather than the value; `MapGen._finalize_walls_and_void` → `_finalize_walls_and_empty` (and every
citing comment); the miss-tracer cluster in `ShotResolution`/`ResolutionPlayer` (`void_range`, "void
ray"/"void tracer"/"void endpoint") → `miss_range`/"miss ray"/"miss tracer"/"miss endpoint" — a
distinct concept from physical absence (how far a missed shot's tracer draws), renamed without
touching miss-tracer behavior, ranges, or the deflect path; ordinary-English "void" in comments
("floating in a void", historical quotes of retired spec language) rewritten in current terms, tbNN
provenance tags kept. New repo-wide guard test (`test_void_vocabulary_guard.gd`, modeled on tb39's
own `test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking` file-scan pattern) walks
`src/`/`test/`/`tools/` and fails on any `\bvoid\b` outside a literal `-> void` return annotation —
the acceptance grep as a real test, not a one-off shell command. Full suite: 2121/2121.

**Camera framing across height deltas measured, found sound (tb40 Pass B, docs/PLAN.md)** — "measure
before changing anything," not a blind fix. A height-delta matrix (target displaced ±1/±3/±6 levels
from the shooter, real solver internals — `CameraOrbitState._solve_back`/`_both_fit`, not a
reconstruction from the returned {yaw, pitch, zoom} via trig round-trip, which loses enough precision
right at the fit boundary the solver deliberately lands on to read as a false failure that was never
real) printed as a table and checked against every hard invariant the pass named: both bodies fit at
every delta including ±6, the camera never sits below the lower of the two bodies (it's pinned at
`shooter.y + ATTACK_UP_OFFSET` regardless of target height, so it's structurally always at or above
the shooter), and the solved framing is continuous across the delta-crosses-zero seam (no explicit
height branch in `attack_framing`'s own algebra to discontinue at). The one real number: vertical look
angle grows from ~7° at the same level to ~25–34° at a 6-level delta on a 3-cell horizontal separation
— real, but bounded by the fit search itself, not runaway. **No code change** — per the pass's own
explicit instruction not to assume a defect exists because a pass is named for it; the tilt-angle
number is handed to Pass D as something for the supervisor's own eyes to judge, not fixed on
spec. `sniper_framing` centers the target at any height by construction (`pan_offset = target.center`,
no shooter dependency at all) — checked across the same matrix rather than assumed from the structural
argument alone. New pinned regression guard locks today's same-level solve exactly, so a future height-
anchoring change (if the supervisor ever wants Pass B4's midpoint-anchor idea) is provably a no-op on
a flat map. Full suite: 2125/2125.

**Wall cutout under elevation diagnosed, not fixed (tb40 Pass C, BR32.05)** — reasoned from
`wall_cutout.gdshader`/`WallLegibility.pixel_radius_for_tiles` source against two named cases, no
shader run (headless rendering never executes a fragment shader). Same root cause BR32.05 already
names (no real ray/line-of-sight test), but elevation opens a genuinely new way for the coarse
heuristic to misfire: the Euclidean-depth gate has always doubled as a correct "is this wall really
between camera and unit" proxy specifically because a flat map makes "behind the unit" and "farther
from camera" the same condition — elevation breaks that equivalence (an elevated wall can be
Euclidean-nearer to the camera than a low unit even while sitting horizontally behind it on the
ground plane). No new `docs/BUGS.md` entry opened — same fix BR32.05 already wants (a real ray test or
an angle-based gate) covers this case too; finding appended to BR32.05 instead.

**Checkpoint 8: a loadable multi-level scenario (tb40 Pass D, closes taskblock-37 Pass E)** — "hand
the supervisor a loadable scenario, not a description." Three hand-built scenarios (target above the
shooter, target below, a same-level control), one shared grid shape (`GridFixture` — the same call
`MapGen._emit` makes — a ground floor, a real 3x3 elevated platform, one real destructible wall
between them), loaded through the real `BattleScene.load_battle()` entry point and framed through the
real `CameraRig.ease_to_framing()` "entering aim" call (tb34 Pass D) — never a mock, never a
re-derived formula. `./checkpoint.sh 8` regenerates it; `tools/checkpoints/checkpoint_8.gd` is the
driver, following checkpoint 6's stills-only pattern (`run_visual_checkpoint.sh` case 8). A yes/no
checklist ships in the generated README, folding in Pass B's own measured numbers and Pass C's
finding as something to confirm, not hunt.

Fixed a real bug found wiring this up: `DeepStrike.assemble_reference_humanoid`/`assemble_from_preset`
never set `unit.height` themselves (every assembly path leaves that to the placer — same convention
`BoutInjector.set_cell_level` already follows) — `checkpoint_8.gd` reads it back from the real placed
`Surface` via `UnitGeometry.true_height_for_cell`, never assumed from the level passed to the grid
builder. Also caught and fixed a `BoutRunner` "squad controller(s) never assigned" error on load —
`CombatState.assign_all_to_human()` (tb31 Pass B's own "Control All Squads" shortcut) for a static
viewing scenario nothing should auto-advance.

**A real render surfaced BR40.01, a genuinely new camera-solver limitation no headless matrix could
have caught** — Pass B's own height-delta matrix only checks two bounding SPHERES against the FOV
cone, with no scene geometry in the harness at all to occlude against. Rendering the "target below"
scenario for real showed almost nothing: the solved camera position sits *past the far edge of the
platform the shooter is standing on*, because `_solve_back` pushes the camera backward far enough to
fit both bodies' angular footprint with no awareness that "backward" can walk it off a small stand's
own edge — the platform's own solid mass ends up between the camera and everything else. Filed as
`BR40.01` (`Active`, owner `CC`, since CC found and root-caused it, source not yet promoted), not
fixed — out of both Pass D's own scope (build a scenario, not fix the rig) and Pass B's own fence (a
missing occlusion check, not an anchor-height problem B4 would have touched). The checkpoint's own
"target below" screenshot doubles as this bug's live repro rather than being reshot to hide it.

Incidental: restored `out/checkpoints/06/` (`board_wide.png`/`cyborg_closeup.png`/
`twelve_arm_rig.png`/`README.md`) after an exploratory `rm -rf` clobbered them mid-session while
confirming this sandbox's GPU/X11 setup could run a visual checkpoint at all (`git checkout --`
recovered them byte-identical; flagged here since CLAUDE.md's own safety protocol is "run `git
status` before any command that could discard uncommitted work" and this one skipped that step).
Also found, in the process: both existing visual checkpoint scripts (`checkpoint_6.gd`/
`checkpoint_7.gd`) crash outright (`Identifier "UnitView" not declared`) — `UnitView` was renamed to
`HitVolumeView` in an earlier taskblock and neither script was updated, since visual checkpoints
aren't part of `run_tests.sh` and nobody had re-run them since. **Not fixed** — out of this pass's own
scope; `checkpoint_8.gd` uses the current `HitVolumeView`/`load_battle()` path throughout, so it
isn't affected, but 6 and 7 need their own follow-up pass before they'll run again.

**Failure model & joints** (tb09, joint depth tb26 D) — five failure modes: `MANGLE` (¼ residual
DT, stays attached), `DISABLE` (inert, attached), `DETONATE` (replaces cook-off), `FRAGMENT`,
`MELTDOWN`. Child-owned joint HP, no modes; depleting one drops the intact subtree. Joints aimable
(the precise-elbow shot). Spill-through: penetration damages the plate fully, spills
`damage − effective_dt` onward. **Joint HP default raised 1→3** (tb26 D) — a weaken-then-sever
gradient instead of any hit reaching a joint severing it outright; per-part overrides still win.
**Joint cladding** (`Socket.joint_cladding`, tb26 D) — an optional Part authored directly on the
socket owning the joint it protects; `BodyProjector` projects it as an ordinary Region in front of
the joint's own region, so it absorbs/deflects through the existing part/DT/spill machinery (tb20's
layered-body cladding model, reused verbatim) rather than a new damage mechanism.

**Armor, damage & weapons** (tb09/10/13/23) — DT from a `dt_curve` table; penetrate/stop-dead/
deflect by real geometry, incidence/reflection read a region's real 3D surface normal (tb23 C, not
a flattened one); ricochet retention `lerp(0.90,0.25,bend)`; crits bypass-or-bonus; bonus-pen as a
DT-discount (penetration only, negative for buckshot). Ammo owns the payload (`AmmoDef`); gun is a
modifier (`WeaponDef`). Cartridge chambering (family + length). Two scatters: dartboard (aim) vs
spread pattern (mechanical). Burst = N independent pulls, recoil accumulates. Recoil computed.
**Audited (tb19 H): burst-fire-sometimes-produces-no-shots** — the suspected cause (`is_legal`/
`apply` reading different `burst_size` sources) never existed; a 200-seed sweep against the real
`chaingun.tres` confirmed every pull always fires — the reported symptom is the chaingun's own wide,
outer-weighted scatter genuinely missing often, even on pull 0 before any recoil (a data/balance
fact, confirmed with the project owner, not silently retuned). New `&"burst_pull"` combat-log events
(hit/miss + running `landed_so_far` tally) make "did all N pulls execute" directly observable.

**Layered bodies & power** (tb20/22) — bodies as cladding/skeleton/organs; knowledge-gated occlusion
of internals (source stubbed to "known"); penetration traversal (DT attenuation, overpen = 0°
deflect, `hollow` flag, lodged-inside wounds); **wounds** as non-terminal repairable per-part state;
penetration-driven deflection resistance (closed the angle-lock stalemate); power drives AP through
an authored diminishing curve (tb20 F, revised tb22 B) with coring; the reaction window
(perk-gated, default none). A unit that can neither move nor act may voluntarily **shut down** —
inert, still occupying its cell/occluding the shot plane, excluded from turn order (tb22 C).

**Range** (tb19) — effective / max / min with a linear sub-1 accuracy band in the effective→max
range; discrete min-range failure (explosive duds); AI movement is range-aware. Internal-targeting
shots (tb20 B) were audited against this pipeline (tb20 G, confirm-only — no separate code path) and
confirmed to run through it unchanged: an internal aim just shifts `AttackAction`'s dartboard center,
so it inherits the same effective→max accuracy band and never bypasses range banding.

**Repair** (tb22 E) — `RepairResolver`/`RepairAction`, five authored battery parts + the Arc Welder,
repair-with-scrap (1:1, up to 3 HP per use, 4 AP; scrap's own resource id is the damaged part's
`material` field). Reachable via a right-click "Repair with Scrap" item and an action-bar Repair
button. **Partial**: logically complete and tested, but not yet reachable in natural gameplay — no
existing part's `salvage_yield` produces the `material`-field scrap namespace repair reads, since
that's a new id space kept deliberately separate from the existing `salvage_yield` categories
(`metals`/`organics`/`reactives`). A follow-up authoring pass is needed before a scavenged scrap pile
actually feeds a welder.

## Melee (tb25, keystone 1)

**Delivery** (tb25 A) — reach = `weapon_def.weapon_length` (free, no exposure) +
`Shell.shell_reach` (leanable exposure budget). A strike needing shell lean poses the torso
forward (`Poses.lean`, the same `ROOT_SOCKET_ID` seam `Poses.down()`/`prone()` already use) — no
melee-specific exposure system, the existing overwatch torso check fires against the leaned
geometry unchanged. Beyond `shell_reach + weapon_length`, a reach-gated step-in
(`MeleeDelivery.find_step_in_cell`) reuses `StepOutPlanner`'s own move-assembly structure.

**Resolution reuse** (tb25 B) — `StabAction`, a point-payload strike sharing
`ShotResolution.resolve_and_log_point`/`DamageResolver`/`ShotPlane`/`RangeModel`/`Dartboard`
verbatim with `AttackAction` (structurally a sibling, never a parallel resolver). Legality is
reach-gated (`MeleeReach.in_reach`, a real 3D distance via `UnitGeometry.bounding_sphere` — a
sword can't hit someone 1 up, a polearm hits at √2) instead of range/LoS-gated. The ranged
accuracy pipeline is reused unchanged — melee's own tight dartboard is point-blank range through
the existing curve, not a special rule.

**Three payloads, one deflect seam** (tb25 C) — `DamageResolver.resolve_shot` gained an additive
`deflect_mode` (default `&"ricochet"`, every prior caller unchanged): `&"slide"` (stab) retries
once against a laterally-nudged point on the same plane instead of ricocheting; `&"none"`
(slash/hold, per point) stops outright, no bounce. `SlashAction` — a line payload
(`MeleeLine.sample`, horizontal/vertical/45°, `slash_length` long) hitting everything along it; a
vertical line spreads along `Region.rect`'s own real-height axis (tb23) for free. `GrindAction`
(armed as action id `&"hold"`; the class name avoids colliding with tb19's own "defer to next
ally" `HoldAction`) — `weapon.burst` doubles as hit count, each hit's `bonus_pen` stacks raw and
uncapped (`base * i`), `DamageResolver`'s own existing PENETRATE spill cascade already gives
"continues through cladding" for free.

**Spherecast** (tb25 D) — `ShotPlane.disc_overlaps_rect` (radius ≤ 0.0 is exactly
`rect.has_point`, every point-only caller unchanged): a stab's own `weapon_def.stab_width` disc
can't thread a gap narrower than it, the same sniper gap-fall-through inverted. A stepping stone
to a real shapecast — the shape math lives in exactly one place.

**Suppression un-stubbed** (tb25 E) — `Suppression.resolve_opportunity_attacks` fires the
attacker's own real melee weapon (`ActionCatalog.provider_for(attacker, &"stab")`) through the
identical `ShotResolution` pipeline `StabAction` itself uses, replacing the flat unarmored stub
hit; gated on `state.is_preview` now that the outcome is RNG-driven, matching `AttackAction`.

**AI** (tb25 F) — PSYCHOTIC (prefers melee, closes to minimize distance, never flees) and TURTLE
(flees rather than melee — `Suppression.is_suppressed`-gated, otherwise an ordinary
cover-weighting planner) fold into `UnitAI`'s existing dispatch; `_preferred_firing_action_id` now
also recognizes `&"stab"` (purely additive), so AI weapon choice reads the same
`ActionCatalog` seam every other firing pick already does. The baseline "punch" (a POWER-capable
part providing its own `&"stab"`, no weapon needed) is proven at the engine level; authoring it
onto shipped content (and a real `shell_reach` per shell template) is unauthored balance work, not
invented here.

## Combat structure & AI

**Turn structure** (tb06, docs/09) — TACTICS/RESOLUTION re-entrant loop; `resolve_until →
COMPLETED|STOPPED(reason,refund)`, interrupt when the next action is illegal; overwatch (torso gate,
visible as a 30° slice, tb19) — the AI can now genuinely weigh and hold it, not just react to it
(tb24 C); one-stream combat log, folded into hierarchical action-level summaries at render time
(tb22 F). **Combat-log shot geometry in text, not just data** (tb28 C) — `ShotResolution`'s own
impact/miss logging (made public: `log_impact_result`/`log_miss_result`, were `_log_impact`/
`_log_miss`) folds the real origin/hit geometry `data` already carried (tb22/23) into `text` too, so
`out/combat.log` shows it directly — `LogEvent._to_string()` only ever rendered `text`, so the
geometry was invisible outside a live playback or a `data` inspection until this. `Overwatch._fire`'s
own separate, hand-rolled `&"impact"` event (no geometry, no crit/wound/destroy/salvage cascade at
all) now routes through the same shared path every other firing action uses — no parallel logging
system, and overwatch misses are logged for the first time. **Per-tile move facing** (tb16 A) —
`MoveAction.apply_stepwise` faces before each step, not once at the end (`FaceAction.face_for_free`
per tile, free); a curved or interrupted path faces correctly mid-move, and an interrupted move is
left facing its actual direction of travel at the interrupt point, not its start facing. **Round**
(tb17-1 A, audited and already correct — no code change needed) — `CombatState.round_number`,
incremented exactly when turn order wraps back to the front, not once per unit's turn; the boundary
future per-round effects and the Hold action (tb19 F) key off. **Hold action** (tb19 F) —
`HoldAction` defers a unit's turn to after the next ally acts, still within the same round; carries
all held AP/MP forward, regenerates none; available to AI and player — the AI holds instead of
taking a clearly bad action (e.g., facing uselessly when its own ally blocks the firing line).

**Resolution speed** (tb18) — `Matrix.personal_speed` (flat bonus to everything); unified
resolution-speed formula (lower resolves first); re-validating ordered resolver; initiative;
equal-speed simultaneity (`CombatState.simultaneous_group()` — a logic-level grouping query only;
turn order/`advance_turn()` still hand back one unit at a time, and skipping the inter-turn pause
during playback for a simultaneous group is a flagged `BoutRunner`/`ResolutionPlayer` follow-up, not
yet built); **Step Out** (auto-assembled orthogonal move/fire/return through the
resolver, dies-exposed on interrupt). Both legs are free — `MoveAction.free` costs no MP/AP either
direction, for the AI's own `StepOutPlanner` usage and the player alike (tb27 B2, docs/SUPERSEDED.md
— previously a deliberate "real cost, no discount" choice). The player's own Step Out flow now
matches the intended sequence: confirming a cell queues only the free out-leg and opens ordinary
aim mode from the stepped-out position (camera/dartboard follow the queued move for free via the
existing preview machinery); firing appends the free return leg; canceling aim mid-step-out undoes
the queued out-leg (tb27 B). **Queue panel** (`QueuePanel`, rebuilt BR27.08 — `docs/SUPERSEDED.md`)
— the in-turn readout of a unit's own queued actions; each entry is a real row (What/AP/MP labels)
carrying its own "Resolve" button, wired directly to `TacticsController.resolve_to_marker(index)` —
resolves the queue's prefix through exactly that entry on press, no separate select-a-row-then-press-
a-global-button step and no persisted marker state. Rebuilt this way after the prior `Tree`-based
mechanism (click a row to set a marker, a separate global button to fire) could never be made to
reproduce a real, supervisor-confirmed "nothing happens at all" failure in this environment — replaced
with the same primitives every other reliable click surface in this codebase already uses.
**Resolving to an earlier point keeps what's queued after it** (supervisor follow-up,
`docs/SUPERSEDED.md`) — `SelectionController.keep_queue_suffix()` replaces the old `reset_turn()` call
`resolve_to_marker()` used to make after a partial resolve, which discarded the entire remaining queue
along with the prefix that actually resolved. The same queued `CombatAction` objects replay unmodified
against the just-updated real state — safe because every action already re-validates itself against
whatever `state` it's actually handed (docs/09), not a captured reference. **A `MoveAction`'s own row
text drops its unbounded path** — `CombatAction.short_describe()` (new, defaults to `describe()`
unchanged for every other action) is what a queue row actually shows; `MoveAction` overrides it to keep
everything `describe()` already says except the `path=...` term (`"MoveAction(unit=%d)"`, matching every
sibling action's own `ClassName(unit=%d, ...)` style), since that term alone — not the row's format in
general — was what stretched the readout across the whole display. The full path still reaches the
hover tooltip, as an extra "Detail" row (`TooltipBuilder.for_queue_entry()`).

**AI** (tb14/16/17-1/24) — `UnitAI.plan_turn`, deterministic, human & AI emit the same queue,
firing derived from the same `ActionCatalog.build_firing_action` seam a weapon's own
`provides_actions` governs for both (tb24 A/B — `is_legal` enforces it as an engine rule, not a UI
convention); the AI can weigh other provided, non-firing actions the same way, overwatch the first
consumer (tb24 C). Playstyles: AGGRESSIVE (never holds overwatch), COVER_SEEKER (only from cover),
SKIRMISHER (~5), MARKSMAN (~7+, prefers it), PSYCHOTIC (prefers melee, closes to minimize
distance, never flees), TURTLE (flees rather than melee — tb25 F). Line-of-fire safety (won't
shoot through allies); reachability-aware targeting. **Suppression** (tb19 E, un-stubbed tb25 E) — a
`two_handed` weapon is illegal to fire while its wielder is adjacent to a living enemy
(`Suppression.blocks_weapon`), and leaving an adjacent tile draws a free melee attack
(`resolve_opportunity_attacks`, a flagged stub hit until tb25 E gave it a real weapon); this alone
keeps the AI from crowding into face-to-face range with no melee system built. **Engagement
positioning** (tb27 C1) — when no reachable cell has real line
of sight this turn, `_engagement_score` now scores primarily on `LoS.obstruction_count` (opaque
cells between a candidate cell and the enemy), which strictly decreases as a unit works around a
corner even while raw distance plateaus — a real, measured improvement (a 60-real-map sweep's
never-reaches-LOS seed count dropped 16/60 → 8/60), not a complete fix: a corridor requiring
temporary backward movement before a gap appears can still trap this per-turn greedy scorer.
**Line of fire, not line of sight** (tb33, `docs/SUPERSEDED.md`) — fixed the corridor case above and
closed BR30.10's own 81%-into-walls finding in one stroke: `LineOfFire.has_clear_line_of_fire`
(new, `src/logic/line_of_fire.gd`) resolves the exact same `ShotPlane` a real shot fires through
(sharing one first-hit resolution with the refactored `_ally_in_firing_line`), rather than trusting
`LoS.has_los` — opacity-only by design, and blind to the cover-Part walls became (tb31 C). Threaded
through `_plan_ranged`'s fire gate (`clear_from_here`/`final_blocked`) and `_engagement_score`'s own
line check (`any_reachable_has_los` → `_has_lof`, `NO_LOS_PENALTY` → `NO_LOF_PENALTY`); a
weapon-range prefilter (`_any_reachable_has_lof`) keeps the added `ShotPlane.build`-per-cell cost off
cells that can't fire anyway (BR26.02). **Closes BR32.10** (AI stuck on U-shaped/concave maps): when
nothing reachable this turn has a shot, `LineOfFire.approach_path` Dijkstra-floods (new
`Pathfinder.nearest_matching`) to the nearest cell that would, truncated to this turn's own MP budget
(new `Pathfinder.truncate_to_budget`) — the fallback re-fires turn over turn until a reachable cell
genuinely has one, unsticking the exact "moves away before it gets closer" detour a per-turn greedy
scorer structurally can't make. `LoS`/`LoS.obstruction_count` are unchanged and still opacity-based —
only the AI's own fire/standoff *gate* moved from sight to fire; genuinely sight-based questions
(`is_covered_from`) still read `LoS`.

**Depth floor on shot resolution** (tb35 Pass B, BR34.06/BR27.02) — `ShotPlane.build`'s own
depth-sort has no floor at zero, by design (a region behind the ray's own origin is legitimately
present, the aim window reads it) — but `LineOfFire._first_hit_excluding`, `ShotPlane.
resolve_projectile`, and `DamageResolver._find_next` are three independent "walk the depth-sorted
plane, return the first match" implementations that all inherited that same unfloored sort with no
floor of their own, so a wall many tiles behind the shooter (still in the plane on purpose) could
sort first and win almost every resolution. This was BR27.02's own logged 12/12-chaingun-pulls-
DEFLECT-on-a-wall-behind-the-shooter case, and — post tb31's dense walls — the same defect made
`has_clear_line_of_fire` read "no clear line" almost everywhere, which was BR34.06 (the AI passing
every turn in bouts). Fixed by flooring the RESOLVING path only, opt-in (`resolve_projectile` gained
a `floor_at_zero` parameter, default false — every raw/body-local-plane caller is unaffected;
`self_obstruction`/`region_at` opt in; `resolve_ray` and `_find_next`, always fed a real
shooter-anchored plane, floor unconditionally) — `ShotPlane.build`'s own sort and the aim window's
`window_depth` reading are untouched. **Second, distinct fix once LOF was genuinely correct:**
`LineOfFire.approach_path` (tb33 Pass B) is capped at `weapon.max_range + APPROACH_MARGIN`, so a unit
starting genuinely far from the nearest real LOF cell still found nothing and held. New
`LineOfFire.closing_path` — real A* toward a cell next to the enemy, no LOF requirement — is the
fallback for that case; deliberately not a greedy per-turn distance scorer (reproduces BR32.10's own
concave-wall freeze; real A* just routes around).

**AI decision log** (tb35 Pass A1) — `plan_turn` was unwatchable: "the AI is broken" and "the game is
slow" were supervisor adjudications, not greppable evidence. New `AiDecisionLog.emit` (`src/logic/ai/
ai_decision_log.gd`, kept out of `unit_ai.gd` itself to stay under its own file-length cap) writes one
`&"ai_decision"` event per unit-turn through the ordinary `CombatState.combat_log` — which branch
`_plan_ranged` took (`fired_in_place`/`repositioned`/`approach_fallback`/`closing_fallback`/
`no_lof_no_route`/`stepped_out`/`overwatch`), whether it fired, and if it held, why
(`no_weapon`/`ally_in_line`/`no_clear_lof`/`out_of_range`/`other`) — read back off a `MemorySink` in
tests, the same convention `test_combat_log.gd` already uses. A diagnostic side-channel only, never
read back by any planner, so `plan_turn`'s own purity/determinism contract is untouched.

**Two framerate dumps, in the combat log** (tb35 Pass A1, BR26.02) — "the reason this bug has
survived three passes is that CC cannot see a framerate" gets an actual fix: **Aim FPS**
(`TacticsController._dump_aim_fps()`, once per `_enter_aim_mode()` transition, 200ms later, past the
entry transient) and **Turn FPS** (new `FpsDumpSink`, watching `combat_state.combat_log` for
`&"turn_start"`, wired in `BattleScene.load_battle()` alongside `file_sink` so every bout gets one
regardless of overlay) both emit `&"fps_dump"` events with a `context` tag, greppable straight out of
`out/combat.log`. `Engine.get_frames_per_second()` only means something inside a real running client,
so the headless coverage here only proves the plumbing fires on schedule — the actual before/after
numbers still want a live session.

**Per-turn LOF memoisation** (tb35 Pass A3, BR27.09) — `_any_reachable_has_lof` and
`_engagement_score` each independently resolved `LineOfFire.first_hit` for the same (unit, enemy,
cell), doubling the real `ShotPlane.build` cost of every reposition-or-hold turn. New
`LineOfFire.cached_first_hit` (opt-in `Variant` cache param, `null` default — every other caller
unaffected) backs one per-turn `Dictionary` threaded through `_plan_ranged` →
`_any_reachable_has_lof`/`_pick_engagement_position`/`_engagement_score`/`_ally_in_firing_line`, so
each cell resolves once. Measured on a real 60-turn bout: average reposition/hold-turn cost dropped
2023ms → 974ms. Not a full fix for BR27.09 — the remaining per-cell `ShotPlane.build` cost is real and
this memoisation can't remove it further without a bigger algorithmic change.

**The `body is Unit` / `Grid.blockers` assumption audit** (tb35 Pass C) — tb31 C turned walls into
full-height, dense `Grid.blockers` Parts; this pass checked every place written for the old
sparse/small-cover shape. **Audited and found correct as-is** (the `is Unit` distinction in each case
does exactly what it should regardless of wall density): `attack_action.gd`/`burst_action.gd`/
`stab_action.gd`'s own muzzle self-obstruction redirect (a static obstruction, cover or wall, should
redirect aim onto it; an ally blocking should not — that's the player's own informed risk, not this
codebase's call); `shot_resolution.gd`'s `target_unit_id` falling to -1 for a non-Unit body (every
consumer already treats -1 as "no unit hit," unaffected by what kind of non-unit thing it was);
`UnitAI._ally_in_firing_line`'s own `region.body is Unit` check (asks specifically "is an ally
blocking," correctly false for a wall — wall-blocking is `has_clear_line_of_fire`'s own separate,
already-correct concern); `Pathfinder.move_cost` (an O(1) dict lookup, density-proof by construction);
`tile_inspection.gd` (a single-key lookup, same reason); `los.gd`/`inspect_panel.gd`/
`world_palette.gd` (no `grid.blockers` reads at all).

**Fixed:** a destroyed wall (or any blocker) never cleared `grid.opacity` — `Pathfinder` already
treated a destroyed blocker as passable (its own `hp > 0` check), but `LoS.has_los` kept reading the
same cell as permanently opaque forever, since nothing at combat time ever touched the `opacity` array
map-gen set once. New `Grid.cell_of_blocker(part)` (a reverse lookup, only ever run on the rare
destruction event, never per-frame) backs a new clear in `DamageResolver.
_resolve_destruction_consequences` — a no-op for ordinary destructible cover, whose own cell was never
opacity-flagged to begin with. **Fixed:** `BoardView._build_wall_indicators`'s own flat gray-tile-plus-
cross marker checked `TerrainType.WALL`, a condition confirmed (via a real generated bout) to never
match any cell on a live map anymore — `MapGen._finalize_walls_and_void` gives every real, exposed
wall cell `OPEN` terrain plus a genuine blocker Part instead. Not a live-game bug (the wall's own mesh
already makes "can't walk here" obvious), but the loop's own doc comment was stale and the condition
could still double-draw on a hand-authored/debug grid that sets `TerrainType.WALL` directly — guarded
against that narrow case and corrected the comment.

**Re-derived, not fixed: BR32.07** ("burst cannot aim at a wall"). Traced the full aim-entry chain
(`TacticsController.click_cell` → `PartPicker.hit` → `_enter_aim_mode` → `aim_state()` →
`AimController.resolve()` → `ShotScatter.for_shot()`) end to end — every step is generic over action
id, and a new regression (`test_tactics_controller.gd::
test_arming_burst_and_clicking_a_wall_enters_aim_mode`) confirms arming burst and clicking a real wall
cell correctly enters aim mode headlessly. No code-level break found; recommends a live re-check
before further digging (the same class of headless-vs-live gap BR27.08 hit).

**Found, not fixed — logged as BR35.01/02/03:** `PartPicker.hit()` scans every `grid.blockers`/
`field_items` entry on every mouse-move hover, not just cells near the ray (real perf cost, now that
blockers number in the hundreds); `SpectatorOverlay`'s tile-inspect click resolves via ground-plane
math alone, with no check for an intervening wall — a click can silently inspect a cell hidden behind
one; every debug-panel verb application triggers a full `sync_board_view()` rebuild, not just ones
that can touch `blockers`/`field_items`. All three have a clear fix shape but real risk if rushed
(geometry correctness for the first two, an exact debug-verb-id list for the third) — left open rather
than guessed at.

**BR33.01 left untouched** — no supervisor policy call has been made yet on the aim-scroll-cycles-
walls question; per the taskblock's own instruction, not guessed at.

**Fixed: the wall-cutout feed-refresh boundary (tb35 Pass D, BR32.01/03)** — `BoardView.
wall_cutout_units` was set in exactly one place in the whole codebase, `SquadControlOverlay._on_
battle_loaded()`; `SpectatorOverlay` (the default overlay every fresh bout starts in) had no handler
that ever touched it, and `BattleScene.load_battle()` itself never re-pointed it either. Starting or
reloading a bout while staying in Spectator mode left the feed pointing at whatever it held before —
null on first launch, the previous bout's own orphaned units on any later one — exactly "a stray
cutout with no unit there" (BR32.01) and "carried over from a previous bout" (BR32.03, the same
defect, not a separate one). Also explains why clicking "Assume Control" always fixed it: that's the
only path that ever installs a real `SquadControlOverlay`, the only code that ever set the feed.
Fixed by moving the assignment into `BattleScene.load_battle()` itself, once, for every overlay.
**Root-caused, not fixed: BR32.04** (cutout snaps to the destination ahead of the move animation) —
confirmed `ResolutionPlayer._play_slide` animates a unit's own `HitVolumeView.position` directly every
tween tick, while `update_wall_cutout()` recomputes from the model's own already-resolved `unit.cell`,
never reading the view's own current transform. Fix direction is clear (a per-unit "current display
position" `Dictionary` written by the tween, read before falling back to the logical cell) but
correctly scoping its own lifecycle wants a dedicated pass, not a rushed one here.

**Mission & meta** (tb07, docs/07) — no win state (EXTRACTED/TERMINATED/STRANDED); enemy count never
an ending; gather→extract/terminate; asymmetric, whole-squad, visible extraction — the player squad
must get everyone to a team-coded tile, can't self-extract early (tb22 A); bout-setup places each
side's extraction tiles on the *opposing* side, forcing the teams through each other (tb23 E1);
pseudo-persistent hulks; loot overlap; deep strike.

**Squad control gets an `UNASSIGNED` state** (tb31 B) — `SquadController` was a hard `{HUMAN, AI}`
binary, so `CombatState.controller_for()`'s fallback had to silently pick a side (BR30.09's root
cause). `UNASSIGNED` is now the zero-default; `BoutRunner._init()` hard-errors if any squad on the
board is still unassigned when a runner is built, so an ill-defined bout can't run at all.
`assign_all_to_human()` / `assign_rest_to_ai(human_squads)` are the visible authoring shortcuts that
replaced the old hidden HUMAN default; `_seed_battle` assigns explicitly.

**Every action arms from the bar the same way** (tb31 D) — `ActionDef.requires_target: bool` (two
shapes) became `Enums.TargetingMode` (`BOARD`/`NONE`/`PART_PICKER`); `ActionBar` dispatches by mode, so
overwatch (`NONE`, its first real UI call site) and repair (`PART_PICKER`) reach the bar directly
instead of bolted-on `SquadControlOverlay` buttons. `ActionCatalog.ap_cost_for` extended to
overwatch/repair — each had the same fixed-cost-vs-part-cost drift BR30.11 fixed for burst, caught on
first wiring.

**Wall occlusion cutout shader** (tb32 A, supersedes tb31 C — `docs/SUPERSEDED.md`) — replaces tb31 C's
one-wall-at-a-time GDScript alpha-blend
(`BoardView.WALL_FADE_ALPHA`/`_set_wall_alpha`) with a lit, per-fragment dithered `discard`
(`wall_cutout.gdshader`, one shared `ShaderMaterial` for every wall). `BoardView.update_wall_cutout()`
projects every unit in `wall_cutout_units` to a screen position/depth/tile-derived pixel radius
(`WallLegibility.pixel_radius_for_tiles`, new pure helper) and feeds them as uniforms each frame; the
shader decides per-fragment whether to discard. Cuts around every unit at once now, not one focal unit;
spectator never feeds any units, so the cutout simply never fires there (unchanged, flagged as trivial
to wire later). **Friendly fade in aiming view** (tb32 B, redesigned after live testing —
`docs/SUPERSEDED.md`) — a friendly
standing between the camera and the active (shooter) unit fades gray. The first version drew a
separate ghost overlay in `BoardView`, leaving the friendly's own real `HitVolumeView` fully opaque
underneath it — confirmed live to read as "something faint happening," not an actual fade. Redesigned
to fade the friendly's own real body instead: `HitVolumeView.set_occlusion_faded()` swaps every body
mesh instance's `material_override` to a translucent gray (never touching the ground marker/facing
wedge, `set_active_turn()`'s own concern, or `highlight_part()`'s `mesh.material.next_pass` chain,
which lives underneath, untouched). The occlusion decision itself moved to `BattleScene._process()`
(the one place holding both the live camera and every `HitVolumeView`), reusing Pass A's
`occludes_on_screen`/`pixel_radius_for_tiles` unchanged against `BoardView.aim_active_unit`; friendly-
only, never the active unit, only while `tactics.aiming_at != null`.

**`PartPicker`: target anything, not just enemies** (tb32 C) — a click can now resolve to a non-unit
Part (`Enums.HitKind.PART`, new): scatter cover, a wall, a downed bot's shell, a loose field item, not
just a live unit's own body (`Enums.HitKind.UNIT`, unchanged) or bare ground (`CELL`). `PartPicker.hit()`
generalizes `UnitPicker` (still the unit-ray-test path underneath) to also ray-test every
`Grid.blockers`/`field_items` Part via the same boxes `BoardView` renders
(`UnitGeometry.assembly_placements`); `TacticsController.aiming_at` is now an `AimTarget` (unit-or-part
+ cell, `ShotPlane.center_of_part`/`UnitGeometry.bounding_sphere_for_part`/`CameraRig.
ease_to_attack_framing`'s new sphere-Dictionary signature all branch on it) so the dartboard/camera
frame a Part exactly like a Unit. This reaches all the way into RESOLUTION, not just the click: `Attack
Action`/`BurstAction.is_legal()` no longer hard-require a live unit at `target_cell` — a blocker/field-
item Part (`Grid.shootable_part_at`) is enough — `apply()` re-derives whichever is actually there and
computes the aim point via `center_of_part` when there's no unit. Ranged weapons only this pass;
`Stab`/`Slash`/`GrindAction` still require a real target Unit (`MeleeReach.distance_3d` needs one) — see
PLAN.md's own follow-up note.

## Tooling, data & view

**Data layer** (tb10/11) — all definitions in `.tres`; `DataLibrary` (res:// builtin + user://
override, user wins); `DataValidator` (named errors, shared editor-save + game-load). Resource
Editor: standalone-scene tuning tool, survives reboots, writes user://, tree-table with
sort/filter/dropdowns/undo/rotating preview. (Layout/resize/column/preview bugs fixed
2026-07-18 in 713f411/1bff29b/944d019 — see BUGS.md; landed outside the taskblock cadence, logged
here retroactively.)

**Test suite** (tb12) — audited for over-granularity (1,026 funcs, 38% single-assert) by measuring
directly rather than assuming: only 3 genuine same-setup clusters existed
(`test_grid`/`test_map_gen`/`test_selection_controller`, 7→3 funcs, 0 asserts lost) — the taskblock's
own ~394→~120 merge estimate did not hold at this suite's actual granularity, and the remaining
single-assert funcs are correctly-scoped distinct scenarios, left untouched rather than force-merged
to chase the estimate. **Audited and found current:** `test_body_projector.gd`/`test_damage_resolver.gd`
(~25% of test LOC, covering systems rebuilt box→per-face→ray and exposure-table→DT→failure-modes)
read test-by-test against the live projector/damage model — no dead-shape test survived from a
replaced model; one redundant pair folded into its survivor instead of deleted.
`test_data_migration_losslessness.gd`'s hand-typed `EXPECTED_PARTS`/`EXPECTED_MATERIALS` fixtures
(previously checked only against themselves) re-verified against the real pre-migration
`DeepStrike.default_part_pool()`/`MaterialTable.default_table()` output, restored from git history —
0 mismatches across 22 parts/8 materials. Assert count unchanged throughout (2333→2333).

**View** (tb15/22, docs/10/10a) — 3D HL2-era; render is hitbox; two palettes; attack camera solves
framing (orbits target); poses = socket overrides; `HitVolumeView` permanent; per-part `mesh_scene`
(mixed assemblies). One `BattleScene` + swappable control overlays. Found and fixed a real ordering
bug in the merge (tb15 A): `BattleScene._ready()` used to call `new_battle()` (which emits the
session-start log line) before any overlay — and its log sink — existed to catch it, silently
dropping the first on-screen log line; fixed by installing the overlay first and having it react to
a new `battle_loaded` signal, which `load_battle()` now emits synchronously before session-start.
**Fix: two playback perf hitches (tb19 I)** — `ResolutionPlayer`'s per-frame tween callback re-ran a
full linear-scan unit/view lookup on EVERY FRAME of every slide/facing animation, now resolved once
per event; `refresh_unit_views()` rebuilt every unit's entire mesh subtree on every turn advance, and
`SquadControlOverlay._on_turn_ended()` called it three times per player turn (one fully redundant) —
new `LogPlayback.affected_unit_ids()` narrows the rebuild to just the units a turn's events actually
named. Playback animation
(slide/facing/shot-fade-to-tracer), animation-gated in the view only, tunable timings; every shot
and ricochet hop draws its own tracer at its real, fully 3D logged position, not one guessed
segment pinned to a constant height (tb22 D, real height tb23 D). **Ground-overlay height ladder**
(tb27 C2) — team marker / extraction tile / overwatch arc / facing wedge each hold a distinct,
deliberately-ordered depth band (`0.010 → 0.06 → 0.09 → 0.17`) instead of one marker bumped in
isolation per report; found and fixed a real, previously unreported co-planar pair (team marker vs.
extraction tile) no prior fix or test had ever checked. **Turn indicator** (tb27 D2, redesigned tb32 D
per BR27.07 — `docs/SUPERSEDED.md`) — originally recolored the active unit's facing wedge/team marker
to a distinct `ACTIVE_TURN_COLOR`; retired once the highlight was found landing on the wrong unit.
`HitVolumeView.set_active_turn()` now shows/hides the whole marker assembly instead — team marker AND
facing wedge together (the supervisor's own correction: "facing marker" meant the whole disk+wedge,
not the wedge alone) — for the active unit only, no recolor at all; presence, not color, indicates
whose turn it is. `BattleScene.refresh_unit_views()`'s `apply_highlight` parameter defers the flip
until after the resolution animation actually finishes (the ordering half of BR27.07 — the highlight
used to jump to the next unit mid-animation). **AP-gated action bar** (tb27 D3, fixed tb30 by BR27.05's
own fix below) — a slot the unit can't afford dims and refuses
to arm, reusing `ActionCatalog.provider_for`'s own `ap_cost`. **Camera reset after aiming** (tb27
D4) — `CameraRig` snapshots the pre-aim orbit state and eases back to it once aiming ends, via a
shared `_ease_to()` helper. **Wall tiles non-inspectable** (tb27 D5) — a wall click is a real
no-op, same posture as a miss; `InspectPanel`'s own null-root branch also resets stale isolate-view
state so it can never leak a live-board render slice into a "nothing to show" case regardless of
caller. **Spectator/player parity** (tb27 D1a/D1c) — the spectator log no longer word-wraps
(matching the player log); spectator view gained inspect-on-hover (`UnitPicker.hit()` driven off
mouse motion, mirroring `SquadControlOverlay`'s own highlight wiring but with no "selected unit"
gate, since spectator has no selection concept) — previously it had no hover feedback at all.
**Fix: turn controls swallowed clicks behind a stale tooltip** (BR31.01) — a tooltip left over from
hovering the 3D board right before the cursor crossed onto a `turn_controls_column` button never
cleared, since `TacticsController`'s own hover tracking lives in `_unhandled_input`, which a
`MOUSE_FILTER_STOP` `Button` never lets fire while the cursor sits over it. Each turn-control button's
own `mouse_entered` now hides the stale tooltip first — the same fix `QueuePanel`/`ApMpPipRow` already
needed for the identical reason.

**Bouts** (tb14) — watchable AI-vs-AI with pacing controls, a seed, a bout-setup menu. The
verification rig. **Bout roster as an expanding list** (tb16 E, tb17 D) — no count field, list
length *is* the count; each row is `[Bot ▾][AI ▾][D][-]` — a per-bot AI dropdown (moved from
per-team to per-bot), a `[D]` duplicate (copies preset + AI choice, inserted below its source), `[-]`
to remove; `BoutSetup.build_bout` takes an `Array[BoutRosterEntry]` (preset + AI choice) per
team. **The `[AI ▾]` menu listed playstyles until taskblock-46 Pass E below, which retired that
vocabulary — it now lists the `UtilityProfile` `.tres` files themselves, so a new profile is a file
and no code edit.** **Map generation** (tb16 C, grid-size fix tb17 A) — BSP room/hallway split with tunable knobs
(`MIN_ROOM_SIZE`, `MIN_LEAF_SIZE`/`MIN_CHILD_SIZE`, `CORRIDOR_WIDTH_MIN`/`MAX`, grid width/height);
rooms ≥ 7 on their min dimension, hallways 3–5 wide, deterministic per seed. `BattleScene`/
`BoutSetup` grid sizes (40×30 / 32×24) are derived off `MapGen.MIN_LEAF_SIZE` so the BSP reliably
splits 2–3 times per axis — tb16 raised `MIN_ROOM_SIZE` without raising these, silently collapsing
every real battle/bout to a single room with no hallways until tb17 A caught it (`BR17.01`,
`docs/BUGS-ARCHIVE.md`); new tests pin each caller's grid constants against `MapGen.MIN_LEAF_SIZE *
2` so a future threshold raise fails loudly instead of collapsing every map again. **Audited (tb19
J): headless vs. watched bouts already share one path** — found the taskblock-14/15 split already
correct: one `BoutRunner` drives every path, `ResolutionPlayer`/`refresh_unit_views()` only ever read
`combat_state`, never mutate it — no merge needed. Locked in with a direct regression test asserting
playback never mutates a unit's own real fields. **Seeded variant generation** (tb28 A) — `VariantFamily`
(DataLibrary-loaded: `variation_amount`, `omittable_sockets`, `swap_pool`, open StringName data, no
per-family code) + `VariantGenerator` produce structurally different bots from one base `BotPreset`,
deterministic per seed; `BodyAssembler` gained a `&""` Loadout-override sentinel ("leave this socket
bare") variant generation uses to omit armor/cladding without erroring. `JunkBot` ships as real
content — a small template with independently addressable per-limb ARMOR/CLADDING sockets (the
reference humanoid's own arm/leg sockets share generic ids across L/R by design, so per-limb variation
needed new content, not a retrofit). **Kits & instant equip** (tb28 B) — `BotPreset.kit` (null =
unchanged pre-existing behavior) names a container socket, what's stocked into it, and the weapon that
equips out of it into a grip socket via the existing `Inventory`/`PartGraph` ops, no parallel attach
path; chambers ammo through `WeaponResolver.try_chamber` like any other load. `KitEquipper.equip` reads
an `Enums.EquipMode` defaulting to `INSTANT` — `VISIBLE` is declared as the seam a future "watch them
arm up" mode slots into, no behavior behind it yet. `BoutSetup._spawn_squad` runs it for any kitted
roster entry right after assembly — a bout of kitted units starts fully armed at turn 1, proven against
shipped content (`kitted_chaingun.tres`). **Bout injection** (tb29, `src/debug/bout_injector.gd`) — the
debug scalpel: `BoutInjector` mutates a LIVE `CombatState` from outside the turn loop so a specific
scenario can be forced and watched. Every verb goes through one gate — reject outright while
`CombatState.is_resolving` (true only for the synchronous span of an active `resolve_until()` call, a
mid-resolution mutation is forbidden, docs/09's own two-phase-turn discipline applied to the debug
channel); otherwise mark `CombatState.was_injected` (set for good, never cleared — an injected bout is a
deliberate determinism break) and log a distinct `&"inject"` event before anything else runs. Verbs:
`spawn_unit`/`set_position`/`hand_weapon`/`equip_from_kit` (the tb28 self-arming path, forced mid-bout)/
`set_part_hp`/`inflict_wound` (reuses the inspect panel's own `WoundEffects.apply_if_status_crosses_
threshold`)/`set_ap`/`set_mp`/`set_facing`/`set_pose`/`force_current_unit`/`force_overwatch_arm`/
`force_action` (`CombatState.try_apply` — reuses the real legality check, never bypasses it);
`set_therms` is a flagged stub (therms aren't built). RNG needs (a spawned unit's matrix id) draw from
the bout's own `rng`, so the same injections in the same order on the same seed stay reproducible-given-
the-injections. **Tooling misstep, tried and reverted (tb30)** — investigating BR27.06 by reproducing
it outside the headless suite, a raw `SceneTree` driver script (`tools/investigate_br27_06.gd`,
copied from the pre-tb28/29 `checkpoint_6/7.gd` pattern of hand-rebuilding `BattleScene` internals and
driving `TacticsController` programmatically) crashed Godot outright — it referenced `UnitView`, a
class renamed to `HitVolumeView` since `checkpoint_7.gd` was written, and the resulting parse error
dropped Godot into its interactive script debugger, which then SIGSEGV'd under a real Vulkan/X11
context with no stdin attached. No lasting damage; the script was deleted, not reworked. Two things
were missed before writing it: `BoutInjector` is deliberately hard-gated out of player-controlled
bouts (tb29 Pass C) — Step Out is a `SquadControlOverlay`/player-input mechanic, so reaching for
injection here was a category error before any script got written; and the intended division of
labor is "CC scripts/forces, the supervisor watches" — for a player-input-only bug, the correct
non-headless step is the real game with the supervisor at the wheel, not a bespoke driver script
reinventing what the overlay system and `BoutInjector` already provide. **Injection reaches a
player-controlled bout too (tb30)** — `bout_injector` moved up to
`BattleScene` itself (built once per `load_battle()`, survives a spectator ↔ player overlay swap via
`toggle_blue_control()`, since `CombatState` was always the one shared source of truth regardless of
which overlay is installed). Both `SpectatorOverlay` (hover-targeted — spectator has no selection
concept) and `SquadControlOverlay` (selection-targeted — a player bout has a real one) offer the same
`[*]` Inject menu (`InjectMenu`, one shared item list/dispatch — no parallel copies of "what does
Inject do"), calling the exact same API programmatic use does. The real safety property — no
*ordinary* click/action can ever trigger injection — now lives at `TacticsController`/`ActionBar` (the
actual gameplay-input classes, a source-level routing test proves neither references `BoutInjector` at
all), not at "which overlay happens to be installed"; `SquadControlOverlay`'s own Inject button is
additionally gated behind a real `OS.is_debug_build()` check (never even constructed in a release
export), not just the `[*]` naming convention every other debug menu in this codebase still only has.
**Debug control panel (tb30, rolled in from a planned tb31)** — three more `BoutInjector` verbs
(`attach_part`, general case behind `hand_weapon`'s existing `_attach` helper; `remove_unit`, wraps
`CombatState.kill_unit`; and tile edits `place_cover`/`clear_cover`/`set_passable`, real
`Grid.blockers`/`set_terrain`/`set_opacity` writes, no parallel spatial model). `InjectMenu` (one
shared item list/dispatch) is retired, replaced by **`DebugControlPanel`** — a generic,
data-driven click-to-force UI: `DebugVerbSpec` (id/label/typed params/apply `Callable`) rows,
`DebugVerbs.all()` the full table, `DebugControlPanel` builds its form from that table alone, so a
new verb is a new row, never new panel code (deliberately excludes `force_action`/`equip_from_kit`/
`set_therms` — no generic widget can build an arbitrary `CombatAction` or authored `Kit`, and therms
aren't built). A "Pick" button next to a Unit/Cell field arms a one-shot board-click capture via a
new duck-typed `board_clicked` signal / `input_capture_mode` flag on both `TacticsController` and
`SpectatorOverlay` — same shape on both, so "Pick on Board" works identically in a player bout and
spectator, and neither gameplay-input class needs to import the panel or `BoutInjector` to expose
it (the source-routing test from the tb29 paragraph above still holds against both). Both overlays'
Inject button now opens/closes this one shared panel instead of a per-target popup menu.
**Fix: debug panel had no anchor, sat on top of the pre-existing top-left HUD (tb30 follow-up)** — a
freshly opened `DebugControlPanel` defaulted to the top-left corner with no anchor set at all,
landing directly on top of `controls`/`tunables` (both already anchored there in both overlays). New
`_center_top()` (horizontal center, a fixed `TOP_MARGIN` from the top) runs once after `setup()`'s
layout settles and again on every `get_viewport().size_changed`, so a mid-session window resize
doesn't leave it off-center; `test_debug_control_panel.gd` pins the real node's `position` back
rather than re-deriving the centering formula.
**Active-target memory + move-object (tb30 follow-up)** — the panel now keeps an "active target":
every board click while it's open (not just a field's own "Pick") updates it and a label above the
panel's own control column shows it, via the same `board_clicked`/`input_capture_mode` hook, now
armed/disarmed against the panel's own visibility instead of per-pick. `BoutInjector.move_object
(target, to_cell)` generalizes `set_position` (unit-only) to move whatever a hit-shaped `{kind, unit,
cell}` dict points at — a unit (delegates to a shared `_move_unit` helper `set_position` also fronts,
the same split `_attach` already uses, logged under its own verb name), or a cell's `Grid.blockers`/
`Grid.field_items` contents (a real dictionary re-key, preserving the Part's own state, never a fresh
duplicate). A new `DebugVerbSpec.ParamType.OBJECT` always resolves from the active target, never a
manual-entry widget. Move Object keeps its `to_cell` param's ordinary manual X/Y entry and adds a
"Move On Next Click" button — snapshots the active target, then applies the move the instant the next
board click lands, no separate Apply press. The verb picker itself is now a scrolling `ItemList` on
the panel's left side; selecting a verb populates a "control panel" column on the right with that
verb's own param rows, Apply, and status — the panel's whole layout, not just its verb table, stays
data-driven off `DebugVerbs.all()`.
**Fix: a debug-spawned unit rendered nothing (tb30 follow-up)** — `BattleScene.unit_views` was only
ever populated once, in `load_battle()`'s own build loop; `BoutInjector.spawn_unit` adds straight into
`combat_state.units` with no view ever constructed for it. New `BattleScene.sync_unit_views()` diffs
the two and builds the missing `HitVolumeView`(s), mirroring `load_battle()`'s own construction; both
overlays' `_on_debug_panel_applied` call it before `refresh_unit_views()`. Confirmed fixed by the
supervisor. (An initial theory that a reported "move also doesn't visually work" was the same bug,
tested against an already-invisible just-spawned unit, was WRONG — the supervisor had tested move
first, separately; still open, see docs/BUGS.md/the taskblock report.)

**Fix: debug `remove_unit` never actually looked dead (tb30 follow-up)** — `HitVolumeView.is_downed()`
(the one thing `refresh()` checks to pick the DOWN pose) reads `Unit.resolve_matrix() == null`, never
`alive` directly — the same thing a REAL kill leaves behind (`DamageResolver.eject_matrix_if_needed`
nulls the hosting part's own `hosted_matrix`, drops it as a loose `Grid.field_items` entry, THEN calls
`kill_unit`). `remove_unit` only ever did the `kill_unit` half, so `resolve_matrix()` kept finding the
still-docked matrix and the view never changed. Now ejects the matrix the same way first — a debug
removal reads exactly like a real kill instead of a flag flip nothing checks.
**Renamed `kill`; `spawn_object`/`remove_object` generalize the rest (tb30, same-day follow-up)** —
the supervisor split debug removal into two distinct verbs: `kill` (this fix above, unchanged
behavior, renamed) is a REAL narratively true death; new `remove_object(target)` is debug-only
cleanup that makes whatever the active target is — a unit, cover, or a loose item — vanish ENTIRELY,
no corpse, via the same hit-shaped `{kind, unit, cell}` dict `move_object` already consumes. A unit
hit calls `CombatState.kill_unit` (bare, no matrix ejection); a cell hit erases both `Grid.blockers`
and `Grid.field_items` there at once. `BattleScene.remove_unit_view()` is the view-layer half
(`BoutInjector` itself can't touch the SceneTree) — destroys the unit's `HitVolumeView` and tracks its
id in `_removed_unit_ids` so a LATER debug verb's own `sync_unit_views()` pass never resurrects it
(reset on every `load_battle()`). New `spawn_object(cell, part_id, pool, as_cover)` generalizes
`place_cover` to also cover the loose-item half of `Grid` (`field_items`) — `place_cover`/`clear_cover`
refactored into shared raw `_place_cover`/`_clear_cover`/`_spawn_field_item` helpers (no parallel
logic), still directly callable, just no longer separate panel rows next to their own generalization.

**Fix: `Grid.field_items` had zero visual representation anywhere (tb30 follow-up)** — a real,
pre-existing `Grid` concept (loose dropped Parts/Matrices — a real kill's own matrix ejection, a
severed limb, or now a debug `spawn_object` loose-item drop) that nothing ever drew, in debug tooling
OR real gameplay. `BoardView.build()` now also iterates `grid.field_items`: a loose Part reuses
`_spawn_blocker`'s own box geometry (same "render is hitbox" contract, just never registered as a
movement/LoS obstruction); a loose Matrix (no `volume`) gets a flat placeholder marker. `board_view.
build()` was also only ever called once, at `load_battle()` — the exact same gap `sync_unit_views()`
already closed for units, unnoticed for cover. New `BattleScene.sync_board_view()` re-triggers
`build()` (already a correct full clear-and-rebuild) after any debug verb touching blockers/
field_items, called from both overlays' `_on_debug_panel_applied` alongside `sync_unit_views()`.

**Fix: action-bar affordability read the raw unit, not the queue preview (BR27.05)** —
`ActionBar.refresh()`/`_on_box_gui_input()` both compared against `tactics.selection.selected_unit.ap`
directly. Per docs/09's own "queuing mutates nothing," `unit.ap` never drops for an action that's
merely queued this turn, only once it resolves — so an action already committed to the queue (e.g. a
move that burned AP once MP ran out) was invisible to a LATER slot's own affordability check, which
kept reading the unit's full starting AP and stayed clickable regardless. Both call sites now read
`tactics.selection.previewed_unit()` instead — the same source `reachable_cells()` already uses for
the identical reason.

**Fix: Step Out evaluated cover from the shooter's stale pre-move cell (BR27.06)** — same bug class as
BR27.05, one file over. `TacticsController._enter_aim_or_step_out_mode` read `selection.selected_unit`
directly; per docs/09's "queuing mutates nothing," that stays at the shooter's turn-start cell until
the queue resolves, so a player who moved toward/into cover and THEN armed a shot had cover evaluated
from the stale pre-move position — silently falling through to ordinary aim mode instead of the
step-out the shooter's real, about-to-be-true position warranted. Root-caused by first disproving a
standing hypothesis from this taskblock's own earlier BR27.06 investigation ("the trigger condition
may just be too rare on real maps"): a 60-seed sweep of real `MapGen` maps driven through full
AI-vs-AI bouts found ~1850 genuine covered-with-a-candidate encounters, and `MapGen._scatter_cover`
never sets `grid.opacity`, so most of those are plainly visible/clickable too — not rare, and not an
LOS edge case. Swapped to `selection.previewed_unit()`, the same fix shape as BR27.05.

**Pass D: audit of `selected_unit` staleness across the rest of tactics-phase view code (BR30.07/
BR30.08)** — BR27.05 and BR27.06 turned out to be the same bug in two places, so tb30 audited every
other `selection.selected_unit` read that feeds position/AP-dependent state (not identity) per a
supervisor-authored suspect list. `TacticsController._confirm_step_out()` computed its outbound path
via `Pathfinder.astar(shooter.cell, firing_cell)` off the raw cell — `MoveAction.is_legal()` requires
`path[0] == actual.cell` against the unit's real (previewed) position, so a move queued before
triggering step-out silently failed to enqueue and fell through to `cancel_step_out()`, invisibly.
`TooltipController.refresh()` passed the raw unit into `TileInspection.inspect()`, whose
`visible_from_selected` field runs a real LOS check from the selected cell directly — stuck showing
visibility from the turn-start position after a move was queued. Both swapped to `previewed_unit()`,
each verified failing without the fix and passing with it first. `step_out_exposure()`/
`_refresh_overlay()`'s own `Overwatch` calls were ALSO flagged as suspects but, after tracing (and an
empirical probe), turned out not to matter — `would_trigger_at()`'s general-case branch always
re-resolves the mover by id and relocates to the candidate cell regardless of the passed reference's
own stale `.cell`, so no fix was needed there.

**Fix: shots resolved straight through walls (BR30.10)** — `LoS.has_los()` and `ShotPlane.build()` read
entirely disjoint data: `LoS` reads only `grid.opacity` (correctly opaque for wall cells, gating
tactical aim/step-out decisions), while `ShotPlane.build()` only ever projects `state.units` and
`state.grid.blockers` — never `opacity`. `MapGen` never wrote a `blockers` entry for WALL cells (only
scattered cover got one), so a real wall had an opacity flag but no Part, no mesh, nothing in the shot
plane — invisible to actual hit resolution even though it correctly gated the UI. `MapGen` first gave
every exposed WALL cell a `blockers` Part so a wall registered in the shot plane at all (BR30.10).
**tb31 C then reworked the model** (`docs/SUPERSEDED.md`): a wall is now a **destructible** high-DT
cover `Part` (`data/parts/wall.tres`) on an otherwise-passable `OPEN` tile — not an indestructible
terrain flag — and the negative space past a wall's ring is a new `Enums.TerrainType.VOID`
(non-navigable, opacity 0, no Part: a shot passes into it, nothing to hit). `Pathfinder.move_cost()`
now clears a **destroyed** blocker (`hp <= 0`), so a blown wall — or any dead scatter cover — opens its
tile to movement, one mechanism for both (mangle/rubble states deferred, `docs/PLAN.md`).
`MapGen._finalize_walls_and_void()` resolves this in two passes (classify every cell's exposure
against the untouched grid, then mutate) so exposure can't cascade through solid rock. **Wall
legibility** (`WallLegibility`, `BoardView`) fades a wall occluding the player's selected unit —
screen-space projection (`unproject_position` + depth), real alpha blend kept lit — so walls stop
hiding the action without vanishing; VOID cells render black with a dark-gray border.

**Fix: burst shown as affordable without enough AP; step-out silently dropped the shot (BR30.11)** —
`ActionBar._can_afford()` compared AP against the providing weapon's plain `ap_cost` for every action
id, but `BurstAction` has always charged its own, usually-higher `weapon_def.burst_ap_cost` when
authored. A unit with enough AP for the plain cost but not the real burst cost saw (and could arm)
BURST as affordable, only to have the shot silently rejected at `enqueue()` time — including after a
free step-out move, which read as "step out doesn't work with burst" even though step-out's own entry
logic is genuinely action-id-agnostic (verified directly, no fix needed there). New
`ActionCatalog.ap_cost_for(action_id, provider)` is the one seam both `ActionBar._can_afford()` and
`BurstAction._ap_cost()` (now a one-line delegate) read, closing the drift.

**Inspect panel** (tb21/22/23/26) — the current inspect surface: rotating bot viewer, matrix area,
sorted inventory tree (weapons→containers→parts), info panel + item viewer, status/wound column,
dead-zone hold, right-click debug menu (debug-only items `[*]`-prefixed; inflict-status/create-part
submenus, tb22 G). The one inventory surface in player view too — `InventoryPanel` retired (tb22 I).
Click-to-pause-inspect in spectator, id+squad+variant in the header (tb26 C3). The isolate camera
(single-unit preview) shows the model standing on real ground, correctly lit, not floating in a
void (tb23 E2). **Tile/object inspector** (tb26 E) — `InspectPanel.open_tile(cell, root)` wraps a
tile's blocker Part (or null, a bare tile) in a matrixless, shell-only synthetic Unit and drives it
through the same display path a real unit uses, no parallel inspector; spectator's click-to-inspect
falls through to `BoardPicker.cell_at_ray` when a click misses every unit's own body.

**Transparency** (docs/08) — one `StatResolver`, provenance on every value, tooltip == damage from
one call.

**Control-surface consolidation** (tb31 A) — `TopLeftControls` (a shared `HBoxContainer`) is the one
construction path for Inject / New Battle / Watch across `SpectatorOverlay` and `SquadControlOverlay`,
where each overlay previously built its own copy; grouped top-left, clear of the debug panel's anchor.
The keybindings display now defaults off, toggled by a `Keybindings` button alongside the existing
H-key. Fixed a latent click-passthrough bug found while wiring it (the shared container's
`mouse_filter` defaulted STOP, swallowing clicks in the gaps between buttons).

**Aim view: truth & legibility** (tb34) — the dartboard was quietly lying: `AimController.resolve`
(the drawn board) called `Dartboard.resolve_scatter` with no range multiplier while every real shot
(`AttackAction`/`BurstAction`/`StabAction`) correctly widened with distance, so the board shown was
always the weapon's best-case accuracy and understated spread more the farther you fired. New
`ShotScatter.for_shot` is the one place `range_cells → RangeModel.dartboard_radius_scale →
Dartboard.resolve_scatter` gets assembled now — every consumer calls it, so the drawn and fired boards
can't independently drift again. Fixed the cache landmine this creates: `AimView._rings_match` now
keys on ring-to-outer-ring ratio instead of absolute radius, so a pure range change resizes the decal
instead of rebuilding the 128x128 ring image pixel-by-pixel every frame (`DartboardTexture.build`
already normalizes by `outer_radius`, so a uniform rescale is byte-identical). Two previously-invisible
spread sources now draw: a burst's later pulls widen the board cumulatively
(`RecoilResolver.widen`), but only pull 0 ever showed — `AimController.recoil_bound_radius` draws the
widest pull's own bound as a crisp outline, baked into the same texture (its ratio to the outer ring is
weapon-constant, so the cache invariant survives); a pellet round's mechanical spread pattern
(`SpreadPattern.pattern_radius`, made public) doesn't scale with range, so it's drawn as a genuinely
separate, un-cached overlay circle (`DartboardTexture.build_solid_dot`) rather than baked in. **Part
tooltips in aim view** — new `TacticsController.update_aim_hover` maps the cursor to an aim-plane point
and finds the Region there (`ShotPlane.region_at`, a thin public alias for the internal
`resolve_projectile`), writing only `aim_hovered_part`, never the reticle or `resolves` — hovering
reads, it never re-aims, split into its own function so that's structural, not just documented.
`AimView` renders the hit part's tooltip in-world via a `Label3D` coplanar with the aim window
(`TooltipView.to_plain_text`, a third host for the same `TooltipData` shape `to_bbcode` already
renders, since `Label3D` has no BBCode support). **Sniper framing** — beyond
`CameraOrbitState.SNIPER_FRAME_DISTANCE` (5 cells, a tunable), the attack camera frames the target
alone (`sniper_framing`) instead of shooter-over-shoulder (`attack_framing`): this rig's own topology
(the camera always faces its own pivot) means panning directly onto the target's center puts it
dead-center on screen at any yaw/pitch, so no dual-sphere BACK solve is needed, just a closed-form
single-sphere zoom. Both framings ease through the same shared tween
(`CameraRig.ease_to_framing`/`_ease_to`). **Fix: BR26.02, low framerate while aiming** — two real costs
removed: the cache-invalidation fix above, and a redundant `AimView._process()` override (found
2026-07-21, applied here) that unconditionally called `refresh()` every single frame while aiming even
though `refresh()` was already fully wired to `tactics.aim_changed`; deleted outright once every
mutation path was re-confirmed to emit it. `docs/BUGS.md`'s own scroll-layer-cycles-walls finding
(BR33.01) is deliberately still open — a policy call, not a mechanism one, left for the supervisor to
decide having now seen this block's finished aim view.


### Diagnostics: the log becomes the instrument (tb41 Passes A–D, F, docs/09)
**Render coalescing (Pass A, BR27.09 cost #1).** `emit()` updates the model and marks dirty; the
`RichTextLabel` draw happens at most once per frame, driven from `ControlOverlay._process`. New shared
`UiLogSink` base; both `UISink` and `HierarchicalUiSink` extend it. **BR27.09's own prescribed fix —
incremental `append_text` — was overridden with the supervisor's approval and NOT taken**: it fits the
flat sink but cannot fit the folding one, where a new event routinely rewrites an existing group's
summary rather than appending a row. Coalescing is correct for both, and its real value is that render
cost stops scaling with event count *at all*, which is what makes Pass D affordable.
Measured on BR27.09's own scenario (200-line scrollback, 3v3, peak 29 events), real classes against a
real label in a real tree: `UISink` 4845µs → 225µs on a peak turn, `HierarchicalUiSink` 10058µs →
870µs. **`HierarchicalUiSink` had never actually been measured and is ~2× the sink that had been** —
~10ms on a peak turn in the sink both live overlays use, not the ~5ms BR27.09 estimated from the flat
one. Headless and a real x11 display agreed within ~2%. **The several-second hitch survives, as
expected** — its mechanism is the synchronous AI batch, untouched here; BR27.09 stays `Active`.

**Engine and script errors on the same stream (Pass B).** `EngineErrorTap` is a real Godot `Logger`
(`OS.add_logger`); every error becomes a `LogEvent` of kind `diagnostic` on whichever `CombatLog` is
current. `LogSink.wants()` is the opt-out, checked once in `CombatLog.emit()`. **The reachable set was
observed, not assumed**: `push_error`/`push_warning`, GDScript runtime errors *with the real script
file and line*, and engine-internal C++ `ERR_FAIL_*` all reach it; **a hard crash never will**, and
that boundary is stated in docs/09 rather than left implied. One engine failure can produce several
callbacks as the C++ chain unwinds — reported faithfully, not deduplicated. `_log_message` is
deliberately not hooked (`print()` routes through it and `StdoutSink` prints every event — an
unbounded loop).

**Commands paired with outcomes (Pass C).** `CommandLog` emits a `command` event before every attempt
and a `command_outcome` after, carrying a machine-readable `reason`. Pass B covered every rejection
that already went through `push_error`; this covered the remainder — **~40 bare `return false` paths in
`BoutInjector` that were silent even to the console**, each now naming its cause. Shared helpers stopped
answering only "no": `_move_unit`/`_place_cover`/`_clear_cover`/`_spawn_field_item` return a reason and
`_attach` returns `{part, reason}`, because three different failures collapsing into one null left
callers unable to say which happened. A refusal while queueing and a refusal at resolution read
differently. `try_apply` no longer refuses silently and `resolution_stopped` names the action that
could not run. **Reverses tb29's "a rejected call is a true no-op (no log entry)"** — the mutation and
RNG halves stand, the silence does not (`SUPERSEDED.md`). **Not done:** a per-action legality *reason*
would mean changing `is_legal`'s signature across every action; deliberately out of scope, so
`try_apply` reports `action_illegal` plus the action's own `describe()`.

**Deliberate verbosity and the bout-build log (Pass D).** `BoardView.build()` narrates itself in
construction order — terrain, grid lines, empty tiles, extraction tiles, walls, cover, field items —
each with its own count and a running index, counted where they are built rather than re-derived from
the grid. Plus `unit_assembled` (listing parts in socket-tree order) and `overlay_activated`/
`overlay_deactivated`. **"bot constructed, part attached" is logged where a unit ENTERS the world**, not
inside `DeepStrike`/`BodyAssembler`/`PartGraph.attach`: those are pure static logic with no `CombatLog`
in reach, and threading one down would push a diagnostic concern into the deepest layer for a per-socket
event nobody asked for. **The wall cutout is deliberately NOT logged per frame** — it runs every frame
on every wall while the camera orbits and `FileSink` flushes per line, so it logs only when the cut set
meaningfully changes. `LogFold` folds the new high-volume kinds into one counted row per run;
`diagnostic` is pointedly excluded, because collapsing an error into a quiet counted row is the
opposite of what an error is for.
*Fixed a regression this pass caused:* the build log displaced `session_start` from the log file's
first line, breaking docs/09's "replayable from its own log file alone". `load_battle` now takes an
optional header event emitted between attaching the sinks and building anything, and the active
overlay's log sink attaches explicitly at that point (`ControlOverlay.attach_log_sink`) instead of as a
side effect of `battle_loaded`, which fires at the *end* of the load and missed everything.

**The log becomes a window (Pass F).** `CombatLogPanel`: title bar, minimize, drag-to-resize, a real
background, scroll hand-off at the content's ends, and a live FPS readout in the title bar.
`FpsMeter` and `LogScrollHandoff` hold the real rules and are headlessly tested; the chrome is
plumbing, deliberately untested, and this pass is **a session opener, not a definition of done**.
docs/09 now records that `FpsDumpSink` and this readout are *supposed* to disagree and must not be
reconciled — the gap between them is the only signal separating BR26.02 from BR27.09. **BR34.02 is
answered structurally (the panel has a real background) but NOT closed** — it is `SUPERVISOR`-owned.
*Two layout bugs were found by rendering, not by testing*: a `PanelContainer` sizes every child to
fill, so the readout stacked under the log instead of overlaying it; and `PRESET_TOP_RIGHT` bakes
offsets from a zero-width Label, so it grew off the panel and over the board. Neither was visible to
any headless assertion. `SpectatorOverlay` still uses its own bare label — converting it belongs to the
live iteration this pass opens.
*Supervisor follow-up, same block:* panel widened to a self-declared 520px (it previously inherited
~260px from the surrounding column, which cut most lines off), and **the scroll hand-off was fixed —
it had never actually worked.** `LogScrollHandoff` was correct and unit-tested throughout; the rule was
simply never consulted, because Godot marks a mouse event handled whenever it reaches a
`MOUSE_FILTER_STOP` control under the cursor, whether or not that control calls `accept_event()`. The
`RichTextLabel` consumed the wheel before `_gui_input` on the panel ever ran. Handing off therefore
**`BR34.02` closed `Resolved` by the supervisor** — the panel's real background was one of the two
changes that entry asked for; the `mouse_filter` sweep it also wanted is still outstanding.
*Then the scroll behaviour was reversed outright on supervisor correction*, and the reversal is the
more useful record: Pass F's spec said the wheel should fall through to the camera at the content's
ends, **which is the behaviour `BR30.05` already reports as a bug** for the debug panel — so building
it as written reproduced a known defect somewhere new. The log now absorbs the wheel whenever the
cursor is over it. Two implementation attempts were wrong before the third worked, both because
`MOUSE_FILTER_STOP` does less than it appears to: it consumes clicks (which is why left/middle/right
always behaved) but a wheel still reaches `_unhandled_input`, and `RichTextLabel` scrolls without
consuming. The panel now scrolls explicitly in `_input` and calls `set_input_as_handled()`.
`LogScrollHandoff` and its unit tests are deleted — the rule they encoded no longer exists. **A
cautionary case worth keeping:** that class was correct and green throughout, while the feature it
served did nothing at all, because nothing ever asked it. Only a spy at the real input stage showed
it (`test_combat_log_panel.gd`), and that test carries a deliberate control case so it cannot pass
vacuously.

**`BR30.05` — the same two defects in the debug panel, fixed (`Pending`, `SUPERVISOR`-owned).**
Clicks: `DebugControlPanel` was `MOUSE_FILTER_IGNORE` on taskblock-07 Pass B4's "a plain container
has no click of its own" rule — but it is a `PanelContainer` with an opaque `HulkTheme` background,
so the rule does not fit it; scoped to genuinely invisible containers and this panel set to `STOP`
(`SUPERSEDED.md`). Scroll: the 2021 diagnosis blamed `ItemList` not marking the wheel handled *once
it can't scroll further* — the real fact is broader and was measured, **`MOUSE_FILTER_STOP` never
blocks a wheel from `_unhandled_input` at any scroll position**. The panel consumes it explicitly.
The wheel is **forwarded before being consumed** rather than swallowed: consuming wholesale would
have silently deleted `SpinBox`'s wheel-to-adjust, which several verb forms use, so the event routes
to whatever is under the cursor first (verb list scrolls, `Range` steps) and only then is marked
handled. The forwarding hit-tests by position rather than reading
`Viewport.gui_get_hovered_control()`, because hover is only bookkept from real mouse *motion* and is
null whenever a wheel arrives without one — caught by the `SpinBox` test failing against the hover
version. The entry's own request for a repo-wide `mouse_filter` sweep is **not** covered.

### Checkpoints return as an ordinary tool (tb41 Pass E, docs/09)
The **gate** was retired, not the capability: no hard stop, no permission step. `./checkpoint.sh N`
runs `tools/checkpoints/checkpoint_N.gd` against a real display; the driver is generic and **the
scenario owns its own README and checklist**, so the description cannot drift from the code (three
heredocs were ~200 of the driver's 224 lines).
**The parse guard is the load-bearing piece.** Visual checkpoints sit outside the headless gate by
necessity, so nothing re-runs them — which is how a `UnitView` rename orphaned two scripts for ~15
taskblocks with nothing going red (`BR40.02`). Rendering can't happen in CI; parsing can.
`tools/checkpoints/parse_guard.gd` fails the build on a parse error or a script that stopped being a
`SceneTree` entry point. **It is a script, not a GUT test, and that was found the hard way:** written
as a test first, it worked — but `run_tests.sh` runs GUT with `-d`, and under the debugger a parse
error raises a break that *waits for input*, so the guard would have hung the build instead of failing
it. It now runs without `-d`, ahead of GUT. Proven both ways by reintroducing BR40.02's exact
`UnitView` reference and watching each behave.
`checkpoint_{6,7}.gd` **deleted** rather than repaired — updating two dead scripts so they could then
be removed is work with no product. `BR40.02` closed as **`Obsolete`, not `Resolved`**: nobody
verified a fix, because there was no fix. `out/checkpoints/` is local-only now (`.gitignore` plus
`git rm -r --cached`; the ignore alone does not untrack), with `out/checkpoints-kept/` tracked so
keeping an image is a copy rather than a forgotten `git add -f`. **The durable artifact is the answers,
not the images** — they go in `reports/`. The old GUT-based checkpoints 1–5 left `checkpoint.sh`
entirely: they were never checkpoints, just regression tests, and now live under `test/baselines/` with
names that say so.

### Both views share one combat log (supervisor request, post-tb41)
`SpectatorOverlay`'s bare `RichTextLabel` is retired for the same `CombatLogPanel` the player view
uses, so the title bar, drag-to-resize, `[-]`/`[+]` minimize, real background, wheel absorption and
FPS readout stop being a player-view-only privilege — two views with two log widgets is how they
drift apart every time one is improved.

The panel writes its height through **both** `custom_minimum_size.y` and `size.y`. The overlays lay
it out completely differently — a column child in the player view, absolutely positioned against the
bottom-left corner in the spectator view — and each situation respects only one of those, so writing
one leaves drag-to-resize silently inert in whichever view the author wasn't looking at.

**`fps_dump` joined `LogFold.PLUMBING_KINDS` off the back of it, and that was a real bug nobody had
reported.** Rendering the converted spectator log showed eleven identical `Turn FPS ... 74.0` rows
filling the panel and pushing every combat event out of view: `FpsDumpSink` emits one per turn, and
Pass D never added the kind to the fold list. Folded, not dropped — `out/combat.log` is unaffected,
folding being presentation only (tb22 F2). **The same flooding was live in the player view**; the
spectator view only made it obvious because it runs turns continuously.

Checkpoint 9 (`./checkpoint.sh 9`) authored for the conversion under Pass E's own no-permission
policy — and it earned the parse guard its keep immediately: the first draft called a
`DataLibrary.bot_presets()` that does not exist, and the guard failed the run and named the file
before anything rendered.

### Bug hunt: the turn-boundary hitch, measured (tb42 Passes A–E, BR27.09/BR26.02)
**Partial by design; F and G are not started.** The block's result is a diagnosis, not a fix.

**Pass A — the instrument.** BR26.02's 2026-07-23 revision, unbuilt since. Two dumps per turn:
`turn_boundary` at **0ms** (the boundary cost itself — the number BR27.09 is about, which did not
previously exist at any offset) and `turn_settled` at **2000ms**. The boundary dump is emitted
**synchronously**: any await would push it past the transient it exists to catch. The aim-entry dump
moved to the same delay and reads the shared constant.

**Passes B–C — costs #2 and #3 cut, and they are small.** `HitVolumeView.refresh()` freed and
re-instanced every child even when only a transform changed: 858µs → **351µs** on the move path,
795µs → **267µs** on the aim path. The cheap path **refuses** on any node-set difference rather than
enumerating safe cases. Turn start walked the socket tree five separate times (instrumented and
confirmed — BR27.09's "5–6" was right): 118µs → **40µs**, threaded rather than cached, because a
stale power reading is a silent wrong number. **Both together are under 1% of one AI step.**

**Pass D — the batch yields, and the hitch survives.** `advance_ai_turns` had no `await` at all; it
now yields a frame between units, so input stays alive and each unit's move is visible instead of the
opposing team teleporting. **But a single `BoutRunner.step()` costs ~1672ms** — 24 steps of a real
3v3 bout is 40.1 seconds of pure planning. Yielding between steps buys one responsive frame every
~1.7s. **The several-second hitch is ONE `UnitAI.plan_turn` call, not an accumulation**, so this
relocates the bug rather than fixing it: the remaining work is per-candidate-cell pathfinding/LOS/
cover scoring in `unit_ai.gd`, which tb35 Pass A3 halved once and which has grown back.
**⇒ SUPERSEDED in part by "AI planning cost" (tb43) below — that naming of the remainder was right
about the file and wrong about the function.** The candidate scoring is ~25% of a planning turn;
`_any_reachable_has_lof`'s prefilter scan over the whole reachable set is ~70%. Determinism
verified — a seeded bout is identical through the yielding path and a tight no-yield loop.
Coalescing fork settled as "refresh only the units that step touched", which is proportional to what
changed rather than tb19 I2's measured whole-board waste.

**Pass E — the debug path.** Every debug verb triggered a full `BoardView.build()`, including the ~20
that touch one unit's AP or facing; `DebugVerbs.affects_board()` is now the one authority both
overlays read (BR35.03, `Pending`). Also fixed: `BoutInjector._move_unit` set `unit.cell` without
re-deriving `unit.height`, so a debug move onto a raised cell rendered at the old elevation —
invisible on a flat map, which is why every flat fixture missed it. **Not a fix for BR30.02**, whose
symptom still does not reproduce. `BR35.01` deliberately untouched and said so.

### AI planning cost: cut the search, and find out the search was not the cost (tb43 Passes A–D, BR27.09)

**The block did what it set out to do and disproved its own premise doing it.** It is scoped as
"attack the candidate count and the work per candidate", on the standing assumption — carried by
tb35, tb42 and this block alike — that `UnitAI._pick_engagement_position` is where an AI turn's
seconds go. Passes A, B and D all attack it. **It is about a quarter of a planning turn.** The
measurement that says so is in Pass D below, and it retargets BR27.09.

**The instrument first.** `tools/bench_ai_planning.gd` — 5 seeds x 12 steps of a 3v3, headless and
repeatable, reporting ms per AI step, the Pass B difference rate, a per-role cost split, a branch
census, and a `--profile` breakdown of one turn. Every number here comes from it. **The earlier
~1672ms/~1498ms figures in this bug came from a bench nobody kept and are not part of this series** —
this one starts at ~745ms for the same work, and only differences within it mean anything.

**Pass A — exact early-out in the scorer** (landed in a prior session, `8ebca0e`). Every term in
`_engagement_score` is a non-negative penalty except `cover_bonus`, which is bounded by
`COVER_SCORE_BONUS`, so a cell whose cheap terms already put its ceiling at or below the best
complete score cannot win and skips both line walks whole. `<=` rather than `<` because selection is
strict `>`: a cell that can at best tie never wins. Acceptance was identical output, not speed.
**~1672ms → ~1498ms on the old bench (~10%).**

**Pass B — the candidate rectangle** (`src/logic/ai/engagement_rect.gd`). Scores only the reachable
cells inside a box with two corners on the unit and its target, padded 2 laterally and, on the far
side beyond the unit, by the weapon's own standoff distance. **The asymmetric half is the load-bearing
half**: a unit that wants to back off finds its cells behind itself, exactly where a symmetric pad is
thinnest, and `MIN_COMPLETION_RATE` would very likely still pass while the optimisation shoved
long-range units into knife fights. **~745ms → ~674ms (~9%), keeping 64.9% of candidates
(95.7 → 62.1 per decision), chosen cell differing in 7 of 60 decisions (11.7%)** — much of that being
cells that *tie*, since on open ground a whole arc sits at the standoff distance and scores
identically. The LOF prefilter deliberately still sees the **whole** reachable set: culling before it
would flip which branch runs, not just which cell wins inside one.

**Pass C — batch plumbing.** `Unit.batch_id` (0 = independent, and every generated mission leaves it
there), a `set_batch` injector verb and debug-panel row, a round-scoped `BatchPlan` on `CombatState`,
and a board badge (`B2`, `B2*` for the leader) whose text is decided by a headless logic-layer
function so what it says is testable without a screen. Explicitly **not** `squad_id`: that is the
team, and overloading it would make every batch a second team.

**Pass D — leaders plan, followers follow.** First member of a batch to take a turn claims the lead
and pays for the full search; later members that round read its destination and scan the ≤9 cells
around it. Leadership is **derived, never stored** — no `leader_id`, no promotion logic, nothing to
desync; a leader dying mid-round leaves its record intact so the squad finishes the manoeuvre and
reorganises next round when the record ages out.

**Pass D's own acceptance is NOT met, and that is the block's most valuable output.** It asks for a
follower to be dramatically cheaper and says that if it isn't, the local scan is too wide. Measured:
**leader ~330ms, follower ~317ms, about 4%** — and the scan cannot be narrowed below radius 1. So the
turn was profiled rather than the constant tuned, and per repositioning turn (means over 60):

| | ms |
|---|---|
| `_any_reachable_has_lof` | **271.9** |
| `_pick_engagement_position` | 98.3 |
| `_nearest_living_enemy` | 15.0 |
| `Pathfinder.reachable` | 2.5 |

**The LOF prefilter scan over the whole reachable set is the real remaining cost**, and it is paid by
leader and follower alike. Branch census over the same 60 turns — `repositioned` 23,
`no_lof_no_route` 15, `followed_leader` 10, `closing_fallback` 4, `fired_in_place` 5, `stepped_out` 2
— shows **19 turns in 60 end with no reachable cell having a line at all**, each having scanned every
reachable cell to find out. The cheapest exact attack is ordering that scan nearest-the-target first,
since it early-returns on the first hit and currently walks BFS-from-the-unit order. **Deliberately
not built**: this block is triage with a stated scope. It is in `PLAN.md` and on BR27.09.

Whole-bout effect of batching one squad of three: **~671ms → ~646ms per AI step.** BR27.09 stays
`Active`; nothing here closes it.

### AI v2, part one: measure, invert, seam (tb44 Passes A–D, BR27.09/BR44.01)

**Every performance figure this project had ever recorded came from a tools binary**, and nobody had
checked how much of the hitch was GDScript's debug per-line overhead. Now measured, on the same bench
and seeds throughout: `editor_debug` ~686–712ms → `exported_release` ~530–554ms per AI step,
**~1.29×**. Roughly 78% of the cost survives into a real player build, so the planning cost is
genuine. `src/debug/build_identity.gd` classifies the running build and is stamped into the bench's
first line and every `fps_dump` event, so a number never again needs its provenance explained in
prose. `tools/bench_release.sh` runs both builds and refuses to report unless the binary itself
declares `build=exported_release`.

**Getting that number required fixing BR44.01, and it is the more consequential find: the first-ever
export of this project loaded no data at all** — no parts, ammo, presets, materials or variant
families. `DataLibrary._load_dir` filtered on `ends_with(".tres")`, true in the editor and false in
every export, since `convert_text_resources_to_binary` ships `crab.res` + `crab.tres.remap`. It
presented as a bare SIGFPE with no message, because an empty pool makes `i % pool.size()` an integer
modulo by zero that a release build traps at the CPU. Two structural consequences: an export template
**ignores `-s res://...`** (confirmed by passing a nonexistent script and getting the identical
crash), so the bench needed a main-scene entry point behind a `bench` feature tag; and the bench body
moved to `AiPlanningBench` so the debug and release entry points cannot drift.

**The line-of-fire query is inverted** (`src/logic/visibility_field.gd`). One `VisibilityField` per
target per turn, `PackedInt64Array`, flat `i = x + y*W + z*W*H`; each candidate's question becomes a
bit test. **~700ms → ~525ms per AI step (~24%)**, ~412ms release. It is a conservative **prefilter** —
one obligation, never report "no line" where one exists — and `ShotPlane` stays final, so acceptance
was identical output. It deliberately over-includes on cover, on units, and across elevations. The
occluder test is opacity **and** a blocker the plane would actually resolve against
(`BodyProjector.projects`, extracted so there is one answer): opacity alone is *wrong*, not coarse,
because `Grid.opacity` is never cleared when a wall dies. The all-negative case — 19 of 60 turns in
taskblock-43's census — now costs **exactly zero** `ShotPlane` builds.

**Where the cost went, which is the pass's real output.** `any_lof_scan` 271.9 → 77.8ms, new
`field_build` 4.2ms, but `engagement_search` 98.3 → **251.2ms**. The scorer did not get slower; it was
being subsidised by a scan that built a plane for nearly every reachable cell and left them in the
per-turn memo. The remaining cost is per-candidate casts inside `_engagement_score`.

**The `WorldView` seam** is the planner's entry point; `CombatState` reaches it only through
`canonical_state_for_resolvers()`. Today it returns everything — a pass-through with a doorway in it,
byte-identical across a seeded bout. **The boundary is not `CombatState` versus not-`CombatState`: it
is knowledge-about-units versus everything else, and that line runs THROUGH `Grid` and THROUGH
`BatchPlan`.** Geometry is free; occupancy is not geometry (`Grid.occupant_id` would leak every unit's
position past the filter, so the guard forbids it); the team blackboard is a Trained-and-above tier
capability, so batch plans are observer-gated on both read and write. The resolver door may appear
only as a bare argument, never followed by a dot — greppable, and enforced, because a prose rule with
no enforcement is what BR40.02 was. Restriction is stubbed behind a disabled flag with staleness
derived rather than maintained, and an anti-vacuity test proves a restricted view changes what a unit
decides.

**A unit's turn is now navigable rather than frozen.** The planner yields mid-plan every `chunk`
candidates and the acting unit is named on screen while it thinks. This makes nothing faster and is
not meant to: taskblock-42 Pass D yielded *between* steps, which bought nothing, because one step is
the entire think. The chain became coroutines because GDScript rejects a conditional-await single
implementation at parse time and a second planner would be two paths deciding one thing. A hard turn
budget backs the label, since a thinking state that never ends is worse than a freeze; aborting is
safe at any iteration because the incumbent is the unit's own cell until strictly beaten. Frame
boundaries do not change decisions, asserted directly.

### AI v2, part two: the utility planner replaces the branch cascade (tb45 Passes A–E, docs/PLAN.md)

**The engagement-score planner is deleted.** `src/logic/ai/unit_ai.gd` — 1369 lines, eight
`max-file-lines` bumps, every one justified by "part two replaces this file" — is gone, and the
linter cap is back at its default 1000. `test/unit/test_retired_planner_sweep.gd` greps `src/`,
`test/` and `tools/` for the retired name and asserts the 1000 directly, so neither can drift back
silently. Full retirement note, including the measured before/after, in `SUPERSEDED.md`.

**The model** (Pass A). `ResponseCurve` / `ConsiderationDef` / `UtilityActionDef` / `UtilityProfile`
as data; `UtilityScorer` as the maths. Considerations MULTIPLY, so one zero vetoes outright; the
IAUS compensation factor keeps a 5-consideration action comparable to a 2-consideration one at equal
quality. **The compensation is not exact and the residual is documented rather than hidden** — it
shrinks the dimensional penalty from "five inputs retain 51%" to "89%", and the remaining ~11% is an
accepted cost, not a tuning problem.

**Selection over the existing action layer** (Pass B). `UtilityActionDef.executor_id` names one of
the twenty tested classes in `src/logic/actions/` through `UtilityExecutors`; nothing was
reimplemented. `UtilityContext` is the seam that turns a candidate cell into the `{input_id: 0–1}`
dictionary the scorer consumes — and is the only place in the planner that knows what a grid, a
weapon or a line of fire is.

**Actions and profiles are `.tres` files**, under `res://data/utility_actions/`,
`res://data/utility_profiles/` and `res://data/batch_objectives/`, loaded by `DataLibrary` like every
other content type. `PLAN.md`'s claim that the rest of the tier table "needs preconditions and a
consideration set, not new machinery" is now literal. `tools/author_taskblock45_ai.gd` authors them.

**Intelligence gates information, and the gate is load-bearing.** `WorldView.MEMORY_TIERS` makes
remembered sightings a tier capability: `MINDLESS` sees only what its own eyes currently reach and
stops knowing an enemy exists the moment line of sight breaks, where `TRAINED` acts on what it wrote
down. The two tiers decide differently on the same board and the two profiles decide differently with
tier held constant — both asserted directly, because a tier that silently does nothing is the failure
this design is most exposed to.

**A floor is not a preference — the most consequential authoring lesson of the block.** In a product
model, a consideration whose curve can reach 0.0 does not express "prefer this", it expresses
"refuse everything else". A plain linear `standoff_match` therefore meant "refuse to act more than
eight cells off the preferred distance", which would stop a rifleman with a thirty-cell weapon ever
taking a long shot, and nothing about the arithmetic announces it. Every consideration expressing a
preference is now floored; only `line_of_fire`, which expresses a genuine impossibility, can reach
zero.

**The batch objective, built dormant** (Pass C). A leader runs one coarse utility pass over four
authored objectives and the answer is injected as a consideration input for every follower — squad
coordination without a squad planner, replacing taskblock-43 Pass D's copied destination. Standing
rule 5 is untouched: the objective is computed once per batch per round and reused, never a licence
to resolve units together. **Dormant publishes an all-ones neutral vector, never all-zeros** — zeros
would veto through the product and every `batch_id == 0` unit, which is every unit in play today,
would stop acting.

**The objective damping floor had to be lowered to do anything, and that was found by testing rather
than by reading.** At 0.5 the batch had an objective, the log recorded it, every follower read it,
and **not one decision changed** — `shoot` carries a higher base weight and is served by `hold`
alone, so `advance` and `withdraw` damped it identically. At 0.25 the three cases separate. A
mechanism that is wired end to end and still inert is exactly the "silently does nothing" failure,
arriving on the batch axis instead of the tier one.

**Head to head, then the flip** (Pass D). The same seeds through both planners, 24 of them, re-taken
at the end of the block from one standalone probe with the old planner run from a worktree:

| | old | new |
|---|---|---|
| seeds 0–11 | 9/12 (75.0%) | 5/12 (41.7%) |
| seeds 12–23 | 12/12 (100%) | 8/12 (66.7%) |
| **combined** | **21/24 (87.5%)** | **13/24 (54.2%)** |
| mean turns to complete | 23.6 | **10.6** |
| per-unit plan cost, mission bout | 139.90 ms | **86.51 ms** |
| per-unit plan cost, 3v3 combat bout | 485.16 ms | **131.25 ms** |
| `ShotPlane` builds per turn | 29.1 | **0.0** |

**The speed win is large and the play regression is real but smaller than it first looked.**
`ShotPlane` builds per turn falling to exactly zero is the structural claim, not a speed tweak — line
of fire is a bit test against one `VisibilityField` per target per turn, and the canonical resolver is
consulted only when an action is actually enqueued.

**It is not uniformly worse: when it finishes, it finishes in less than half the turns.** The dominant
failure is `TERMINATED`, the turn cap running out — mostly not losing fights, failing to finish. Two
structural causes were tested and ruled out: the information restriction (identical 33.3% with the
view forced unrestricted) and the candidate-set cull (no change). **Seeds 1, 2 and 6 fail under both
planners**, so three of the eleven failures predate this block and the incremental regression is
eight seeds.

**`MIN_COMPLETION_RATE` went 0.5 → 0.25 → 0.35.** It was landed at 0.25 against a mid-block reading of
37.5%; re-measuring at the end put the real figure at 54.2% and the floor came back up to one seed
below the window the test actually samples. **This is the block's most repeatable lesson: a
measurement taken once, mid-change, is not evidence.** Three numbers here were reported before they
were true, and re-taking them cost minutes and moved the headline by seventeen points.

**A combat-only pool cannot finish a mission, and the head-to-head is what made that concrete.** The
first measurement returned **0% completion** against the old planner's 75% — not because the planner
played worse, but because completion means EXTRACTED and nothing in the Pass B pool could gather an
objective or walk to an extraction tile. The fix was four more `.tres` rows (`seek_objective`,
`gather`, `seek_extraction`) plus the mission inputs to score them over. It also exposed a real
defect the tests had not: candidate cells were computed only when an enemy was known, so a unit with
nothing in sight could not move anywhere at all.

**Three real planner defects, all found by reading the decision log rather than the code.** Each had
survived a green test suite, and each is the kind that a completion rate alone reports only as a
number:
- **A candidate is a (cell, action) pair, and the planner only moved to the cell when the action was
  itself a move.** So `shoot@(3,0)` — chosen because (3,0) sits at a good standoff — was fired from
  wherever the unit already stood. Two units traded shots across a corridor forever, neither closing.
  The log is what exposed it: every entry read `shoot@(3,0)` while the unit sat at (1,0), and the
  mismatch between those two coordinates is the whole bug in one line.
- **A unit standing on its destination scored every OTHER cell as a perfect approach.** `_closes_to`
  returned a flat 1.0 when the distance-to-target was already zero, so a unit that reached its
  extraction tile walked off it and back, every turn, forever — two units alternating onto one tile
  for a whole turn cap, neither ever standing still long enough for the hold to mature.
- **A refused action ended the turn instead of falling through.** `ActionQueue.enqueue` is the only
  thing that knows what a unit can afford from where it will actually be standing, so "the scorer
  wanted this and the executor said no" is ordinary. Stopping there meant a marksman whose own shot
  was unaffordable picked `shoot`, had it refused, and ended its turn — never reaching the overwatch
  it should have held, because overwatch was simply never scored again.

**Holding turned out to be the hardest single action to author, and it broke three different
things.** `HoldAction` keeps the unit CURRENT — that is what deferring means — so anything that lets
it win by default livelocks a bout:
- **It was offered after the unit had already acted.** A unit that spent its whole turn on six shots
  then "held", which is a contradiction: holding is a substitute for acting, not a coda to it. Only
  offered while the turn is still empty.
- **The planner appended `EndTurnAction` behind it.** Hold means *do not end my turn yet*; ending it
  anyway threw the deferral away. `UtilityActionDef.ends_turn` marks the actions nothing may be
  queued behind — data, not an `is HoldAction` branch, for the same reason `repeatable` is.
- **It won by forfeit whenever the candidate scan was short.** The retired planner only held when the
  shot was genuinely blocked; offered unconditionally, hold is what is left when everything else is
  out of range or out of reach. **The view's own `PlanPacer` budget shortens the scan**, so a watched
  bout could livelock where a headless one did not — the worst kind of difference. `lof_blocked` is
  published as an explicit inverse predicate (preconditions are an all-must-hold list with no
  negation) and hold now requires it.

**A missing `await` in the view, exposed rather than caused by this block.**
`SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` fire-and-forget. It is a
coroutine, so the handler returned the instant the planner first suspended and the AI batch completed
some frames later, unobserved. It had no visible effect while the old planner happened never to
suspend on small boards; the utility planner yields through `PlanPacer` on any real candidate set, and
the batch then ran after whatever came next had already read the turn state. Both call sites are
awaited now.

**`hold_position` needed `enemy_known`, which is subtler than it looks.** Holding means "defer to the
next ally, who may open a line" — a combat reason. Offered with no enemy known it broke extraction
outright: `HoldAction` ends the turn itself, so a unit on its extraction tile that chose to hold never
reached the trailing `EndTurnAction` whose hold-check is what matures a hold into a real extraction.
It sat on the tile holding, correctly, forever.

**The candidate rectangle is drawn toward the enemy, and a unit has somewhere else to be.** Culled
alone, a unit that could see an enemy could not consider a single cell toward its resource node or
extraction tile — it could fight or travel, never both. The cells that genuinely close on a mission
destination are added back, at most one per destination.

**Precedence became a weight instead of a branch.** The old planner had a hard "combat first"
ordering above a non-combat branch. Every combat action requires `enemy_known`, so with nothing in
sight the mission actions are the only ones offered and win by default; with an enemy in sight both
compete and the authored weights decide.

**Shots per turn are decided by AP, not by a constant.** `MAX_SHOTS_PER_TURN = 3` is gone; `shoot`
is authored `repeatable` and a turn fires until `ActionQueue.enqueue` refuses the shot it cannot pay
for. `MAX_SELECTIONS` is a backstop deliberately set ABOVE the AP ceiling — it sat exactly at it for
one commit, where the two were indistinguishable, and a test now keeps them apart.

**Moved out of the planner so they could outlive it**: `Cover.is_covered_from` (read by
`StepOutPlanner` and `TacticsController` for the player's own step-out affordance),
`ActionCatalog.preferred_firing_action_id`/`provided_firing_action_id` (a question about the weapon,
not the plan), and `AiPlanner.PLAYSTYLES` (the vocabulary outlives the planner; retiring it is still
`PLAN.md`'s). **~~`AiPlanner.PLAYSTYLES`~~ — overwritten by taskblock-46 Pass E below: the vocabulary
is deleted outright and a bout names a `UtilityProfile` id directly.** `EngagementRect` survived untouched — it was always pure candidate-set geometry with no
planner state in it, which is why it separated cleanly in taskblock-43 and cost nothing here.

**Found and fixed on the way: the AI planning bench had been unable to compile since taskblock-44**
(BR45.02). taskblock-44 Pass C changed the planner's helpers to take a `WorldView` and Pass D made
`_pick_engagement_position` a coroutine; the bench called all of them and was updated for neither.
Nobody found out until Pass D tried to use it. **This is BR40.02's failure mode one directory over**,
so the fix is the class rather than the instance: `tools/checkpoints/parse_guard.gd` now parses every
`tools/*.gd`, not only `tools/checkpoints/checkpoint_*.gd`.

**The guard was wrong before it was right, and the wrongness is the point.** `load()` returns a
`GDScript` object for a script that failed to COMPILE — the resource loads and the compile fails, and
they are separate events — so the widened guard reported "16 script(s) OK" with a deliberate syntax
error sitting in the tree. It checks `reload() == OK` now, and it is verified in both directions:
a deliberate break makes it fail, removing the break makes it pass. `tools/migrate_data.gd` carries
an `@retired-tool` marker — it is a taskblock-10 migration whose own doc comment records that the
generators it walks were deleted by the pass that landed its output, so it can never parse again and
reporting it every build would be noise.

### A performance readout, because the mean was the number that lied (tb51)

**`PerfStats` (logic) and `PerfPanel` (view), to the supervisor's own specification.** The reason is
taskblock-51's own record: one session read **min 7.5, avg 140.1**, and four framerate defects were
found in that block without the mean ever pointing at one of them. Uncapped, this game tops out the
monitor, so a session mixing 8 fps stalls with 160 fps idling reports a healthy average and feels
terrible.

**Five figures:** instant; rolling (a true rate — frames ÷ seconds over 2 s, republished on that
cadence, never a mean of rates); the single worst frame; **1% low** as the mean of the slowest 1% of
frames, which is the hardware-review reading the supervisor confirmed; and **the average with the
fastest 1% of *speeds* removed** — the cut sits at **0.99 × the fastest frame seen**, chosen by the
supervisor over a proportion-of-range reading because the two diverge on narrow spreads. That last
figure reports **what fraction of frames survived the cut**, because a number computed after
discarding data should say how much it discarded.

**Arithmetic correction, recorded because it strengthens the case:** the supervisor's worked example
said the plain mean would read "~40fps" — it is **59.9**. The figure they asked for reads **10**, so
the mean overstates by 6×, not 4×. Both numbers are pinned in the test.

**A bug the tests caught while building it:** 120 frames of `1.0/60.0` sum to 1.999999…, so a bare
`>= 2.0` window check never fired and six seconds reported two ticks instead of three. Fixed with an
epsilon, and the remainder now carries rather than being discarded so the cadence cannot drift.

**"UI Element Control" is a list entry, and the toggles live under it** (supervisor). The readout's
switch does not escape the two-column layout — it belongs to a *category*, so the category gets a row in
the verb list and its checkboxes fill the same right-hand pane every verb uses. `DebugUiElements` is the
table behind it: **a new toggleable element is a row there, not UI code**, the same shape `DebugVerbs`
already had one layer down. Ids are open `StringName`s; the table names elements and the overlays own
the nodes, so the panel never learns what a performance readout is. One `ui_element_toggled(element,
shown)` signal replaced `perf_panel_toggled` — a signal per element would have re-created the coupling.
The entry sits **after** every verb, so `_on_apply_pressed`'s existing index guard already declines it,
and Apply is additionally **disabled** while it is selected rather than pressable-and-inert. Switch
state is held on the panel, not in the checkbox: the pane is rebuilt on every verb switch, so a box
holding its own state would forget while the readout stayed on screen.

**Superseded twice before landing — both attempts are recorded below because each was a different
mistake.**

**The toggle was in the wrong column, and captioned every verb.** It was first added beside the
active-target label, inside the pane that shows the *selected verb's* controls — so a panel-scope
checkbox read as the heading of every entry in the list, and the supervisor saw "Performance Monitor"
captioning `Make Current`. It now sits in the panel's own chrome above the verb split. The regression
test asserts **parentage**, because the checkbox was labelled correctly and emitted correctly while
broken; no test of its behaviour could see it. Verified by re-breaking the layout and watching the test
fail.

**Two placement bugs, and the second one passed a test.** Anchoring right and setting `position` put the
panel at x = -16 — hard against the left edge with only its right sliver showing. Replacing that with a
lone `offset_right` left `offset_left` at the anchor, so it resolved to the **full 1904-pixel screen
width at x = 0** — and an assertion checking "left edge on screen, right edge on screen" was satisfied
by a panel covering the whole display. All four anchors and offsets are pinned now, and the layout test
asserts **the width**, which is the property both broken versions actually violated. The toggle is
labelled **"Performance Monitor"** rather than "Perf readout", which named the implementation instead of
the thing.

**The panel is offered by the debug panel and outlives it.** Toggled from inside `DebugControlPanel`,
owned by the overlay — closing the debug panel does not take the readout down, which is what was asked
for. Present in both player and spectator views, since it is tied to debug rather than to a mode. It
samples every frame and **redraws only on the rolling tick**; a profiler that costs frames measures its
own overhead. An opt-in checkbox dumps the figures to the combat log on that same cadence, emitted by
the panel and *written by the overlay*, so no view reaches into a `CombatState` to log.

**The aim-session dump now reads `PerfStats` rather than its own min/frames/seconds.** That second
implementation is how the log came to report 161 fps for a session the supervisor experienced as 8 —
one measurement now, and the session dump gained the 1% low and the trimmed average, since a bare min
and mean were exactly the pair that hid four defects. **The single worst frame was kept** alongside the
1% low rather than replaced by it: the supervisor has been reading a session minimum all block and it
is the figure that matched what they were feeling.

### The aim view's framerate: four defects, one symptom (tb51)

**113 504 usec per mouse motion → 8 878.** 8.8 fps to 113, measured through a real `SquadControlOverlay`
on a 214-blocker board. `BR26.02` is **paused, not closed**, by supervisor decision.

**What it actually was, in the order found — each fix revealed the next:**

1. **`TacticsController.aim_state()` rebuilt the shot plane and cloned the state on every call**
   (35 258 usec), and was called twice per motion plus once per aim-view redraw. Memoised on the
   plane's real dependencies and **deliberately not on `reticle_offset`**, which is the one value that
   changes constantly and cannot affect the plane.
2. **The memo's own cache key cloned the state**, by asking `previewed_unit()` for the previewed cell.
   `CombatState.dup()` measures **26 083 usec** — `Grid.dup` deep-copies 214 blocker parts and 768
   surfaces. Replaced with `ActionQueue.revision`, a counter bumped on every queue change.
3. **`update_aim_hover` still emitted `aim_changed`.** The signal split into `aim_changed` (state) and
   `reticle_changed` (cheap) had converted three emit sites and missed the one that runs on every
   motion — and which `aim_reticle_at_screen` calls internally, so both paths still reached
   `SquadControlOverlay._on_selection_changed`, which previews twice.
4. **The reticle ran per motion *event*, not per frame.** A 500–1000 Hz mouse against a 60–160 fps game
   backed the queue up so the reticle drew stale positions — *"the dartboard almost seems to lazily
   follow the cursor"*. Coalesced to the newest position, applied once in `_process`.

**Two caches were tried and reverted, and the reasons are in the code:** an empty-queue fast path
(callers mutate the previewed unit, so handing back the live one corrupted the board — three step-out
tests), and a per-frame preview memo (state changes *within* a frame when a resolution spends AP — four
action-bar tests).

**`CombatState.dups` is now a profiled work counter**, because a 26 ms call reached several times per
mouse motion was invisible to every budget. The suite reports ~7 155 clones a run.

**Instrumentation was wrong for three passes, and that is the lesson worth keeping.** `fps_dump` took a
single `Engine.get_frames_per_second()` reading two seconds after entering aim — while the mouse was
still — and reported 161 fps for a session the supervisor experienced as 8. **Their report was correct
throughout and was the evidence the instrument was broken.** It now samples every frame and reports
min, average and frame count on leaving aim.

**Side effect, measured: `BR27.09` improved** — turn-start FPS 38.0 → 91–147. Not closed.

**Also landed:** `set_part_hp` takes an object target so it can reach blockers and field objects
(`BR51.02`); `kill_unit` advances the turn when it kills the current unit (`BR51.04`/`BR51.05`, closed
by the owner); a `CHOICE` param type so a debug verb can carry its own dropdown options as data; and
per-element `set_aim_visual` switches that let the supervisor bisect a GPU cost CC cannot measure —
which cleared every aim visual and the wall cutout as suspects.

### The suite under five minutes: seeds_to_first_win, two corpora, failure-first ordering (tb50)

**Full gate 446.8 s → 290.4 s (35%), 2462 tests.** The five-minute acceptance is met, and thinly:
three clean runs measured 288.4 / 288.8 / 290.4 s, while a run sharing the machine measured 313.5 s.
**~290 s on an idle machine** is the defensible number.

**Pass E2 — a shared map corpus, and it is what closed the gap.** `test_map_gen.gd` and
`test_map_gen_raised_rooms.gd` ran **14 independent seed sweeps** regenerating ~650 maps to ask 14
questions about 50. Every sweep was checked first — **none mutates its grid** — so `MapCorpus.read()`
returns the cached `Grid` with no copy at all, and `copy()` is there for anyone who needs to mutate.
**22.7 s → 11.2 s** and **16.2 s → 5.6 s**, more again across the full gate since both want the same
maps.

**The corpus sets a trap, and it caught its own author.** Two tests compare *two independent
generations of one seed*; through `read()` they receive the same object twice and pass
unconditionally — silently deleting the suite's only check that generation is reproducible. The bulk
conversion did exactly that and was caught by reading the diff. Those two sites keep calling
`MapGen.generate`, and a test now pins that `read()` returns identity.

**Pass E1 — failure-first ordering, and nothing is ever skipped.** `SuiteOrder` ranks scripts by how
often and how recently they have failed; the runner enumerates the scripts itself and hands GUT an
ordered list. **It is a permutation, asserted as one** — the pass forbids skipping, because an
indicator that passes while the thing it indicates is broken makes the suite greener than the code,
which this project has hit four blocks running. The order is printed each run so a failure can be
replayed exactly. History lives in `out/suite_failures.json`, **gitignored**: it must update on
ordinary runs to learn anything, and committing it would churn every diff and make one machine's
flakes everyone else's run order.

**Pass F — a baseline beside each failure, a chime, and a triaged ledger.**
`ReplayCatalog.handles_with_baselines` queues each failure with its script's own known-good fixture,
opted in through the existing `replay_handle_for` hook via a `BASELINE_TEST` sentinel — so nothing
changes for the ~250 scripts exposing no handles. Not the default, and the cap counts *failures* so
context never costs coverage. The finish chime is two synthesised tones, rising for green and falling
for red, guarded so no audio device can fail a run. **The ledger triage went in the block's report,
not `docs/BUGS.md`** — that file's header argues against derived indexes and category sections, and
31 headings were diffed before and after to prove no status moved.

**Passes E3/E4 — the eight name defects renamed, and the seed-list trim found already done.** Eleven
renames rather than eight: the `pass_b_` prefix cited an anonymous taskblock pass on four names in one
file. `test_the_flank_test` became
`test_a_shot_from_behind_reaches_the_thin_rear_plate_a_frontal_shot_cannot`;
`test_the_unbuilt_tier_table_rows_are_still_unbuilt`, which reads the utility *action pool* and never
touches the tier table, became `test_the_four_utility_actions_with_no_executor_are_still_unauthored`.
The audit CSV's keys moved with them, so the classification survived. **`description` is now empty
across all 2441 rows** — the defect list is closed. E4 needed nothing: Pass D had already taken
`test_full_mission` from eight bouts to one, so there was no fixed seed list left to trim.

**Pass A — `HULK_` retired from tooling identifiers.** `HB_FAST_GATE`, `HB_TEST_ROOT`,
`HB_FORCE_TEST_FAILURE`. `LootTable.HULK_SOURCE` keeps the prefix and is allow-listed by name — loot
sourced from the hulk is the word meaning what it means. The guard bans the **screaming-case prefix**,
not the word: `Hulk`, `HulkTheme`, `hulk_seed` are the domain vocabulary and a case-insensitive sweep
would have flagged hundreds of correct uses. It scans `.sh` as well as `.gd`, because the retired names
were environment variables and `run_tests.sh` is where they were read.

**Pass D — `seeds_to_first_win` replaces the completion rate**, and this is the change that mattered.
`CompletionSampler.seeds_to_first_win` plays seeds until one completes, capped at `FIRST_WIN_CAP = 9`,
drawing lazily so a healthy run never generates the maps it did not need. **`test_full_mission.gd` went
15.2 s → 1.5 s, 8 bouts → 1.** Cost now scales *inversely* with health: a regressing AI makes the
measurement more expensive, which is the right shape.

The cap is derived, not picked: at the measured 0.72 rate, nine straight losses is 0.28⁹ ≈ one run in
180 000. It is a **collapse detector by design** — at 0.20 it fails about one run in seven, at 0.10
about one in three, and a mild regression not at all. The reported count is the signal (1 healthy, 4
worth a look, 9 a failure), because a threshold on a small integer count is exactly what put
`MIN_COMPLETION_RATE` a fraction of a seed from red and got it lowered twice. **That constant is left
in place and unused by the test that read it**; retiring it is proposed, not done.

**This closes `BR49.01` as a side effect.** The fixed eight-seed sample made total turns swing 970 /
1305 / 961 across three runs with no code change, flapping the work budget and making every other
saving unmeasurable underneath it. The corpus now plays one bout in the healthy case.

**Pass C — `ScriptedCorpus`, and a measured finding that there is nothing to migrate onto it.** A board
built through `BoutSetup` (real presets, real assembly, a real generated map) with both squads `HUMAN`,
driven by an authored queue through the same `CombatState.resolve_until` the AI's own output uses. It
**provably never plans** — asserted on `AiPlanner.plans`, the counter the profile reports — with a
companion test proving that counter does move when something really plans.

**The migration it was built for does not exist, and the survey says why.** All **137** hand-built test
files reference specific `Vector2i` cells, so none can take a shared generated board without changing
what they assert; and **117 of the 137 are already under 1 s with zero bouts**, so there was no cost
there to recover. `test_work_counters.gd`, the obvious candidate, asserts that a hand-driven turn builds
*no* bout — migrating it would build one and delete the assertion. **The corpus is therefore a fixture
for new tests and for the `test_tb38_flat_bout_guard.gd` pattern, not a saving.** The audit outcome the
pass was hunting — *hand-built is quietly wrong* — went unfound, which is a result rather than a gap.

**Pass B — partial, and its premise was wrong.** The pass expects thirteen bout-building files to move
onto `BoutCorpus` for ~200–250 s. The corpus hands out **outcome records**; those files need **live
boards** — which `BoutCorpus`'s own header has said since taskblock-48 built it: *"a test that needs one
builds its own, which is what the eight other bout-building files already do and why they are not
candidates for this."* Two files moved:

- **`test_completion_sampler.gd` 94 s → 41 s** — not by adopting the corpus, but by making **sample
  size a parameter** on `CompletionSampler.sample`/`draw_seeds` and on the `sample_completion` verb.
  The test drives a verb that samples for itself, and every assertion in it is about the *shape* of the
  report. One seed witnesses that exactly as eight do.
- **`test_watched_run.gd`** — the one genuine corpus adoption. It played a seed headless *and* watched
  to compare them; the headless half is what the corpus already recorded.

**`run_seed`/`run_seeds` take a turn cap.** Bounding the horizon is not the move taskblock-48 refused:
that was seed-shopping for a cheap map, which makes the fixture unrepresentative. Here the seed is
unchanged and the run stops earlier, which is sound for any property true at any horizon.

**Recorded because it shaped the ordering:** adopting the corpus makes a *targeted* run of a corpus
reader slower — `./run_tests.sh test_watched_run.gd` went 18.2 s → 49.3 s, since in isolation that file
becomes the corpus's first toucher. Pass D then shrank the corpus and the regression vanished. Corpus
adoption before Pass D would have degraded the edit loop for every file it touched.

### The suite indexed per test, and classified by the rule each test defends (tb49 Passes A–B)

**Full gate 487.5 s, 2431 tests, 255 files.** The artifact is `test/suite_audit.csv`, one row per test,
produced by the procedure in `docs/TEST-AUDIT.md`. **Nothing was cut** — the block produces evidence;
acting on it is a later block under the cut rule.

**Pass A — per-test granularity.** `run_suite.gd` already snapshotted the work counters at script
boundaries; it now does the same one level down and emits `origin_file,test_name,description,usec,bouts,
turns,candidates,floods,plans,shot_planes,rule_guarded`, sorted by file then declaration order because
the procedure fills the judgement columns file by file. **Where setup lands is stated rather than
assumed:** GUT fires `start_test` *before* `before_each`, so a shared fixture is charged to the test that
triggers it, and `before_all`/script load are charged to nobody. That unattributed remainder was measured
at **8.4 s of 496 s — 1.6%**.

The acceptance the taskblock names — per-test counts summing to the file-level counts — is **arithmetic,
not corroboration**, and the test says so: taskblock-47 made a file's counters the sum of its tests'
precisely because the outer window was corrupted by `before_each` resets. The independent check is the
row count against `func test_` read off disk.

**Pass B — 2431 rows classified, 328 distinct rules (13.5%).** `description` is filled on 8 rows (0.33%),
each a name defect: two cite deleted taskblock documents, one asserts "three scatter rings" as though
ring count were a rule (`docs/00`: **N rings, never 3**), one is drifted outright
(`test_the_unbuilt_tier_table_rows_are_still_unbuilt` reads the *action pool*, not the tier table), and
four are vague. The full list is in the block's report.

**What the classification shows, stated plainly because it is not what the procedure predicted.** The
largest clusters are cross-cutting invariants rather than redundancy — *"a degenerate input yields an
empty result, never an error"* is 89 tests across 60 files and costs **1.1 s in total**. Cost concentrates
in individual rows instead: the four most expensive (**102.3 s**, **62.6 s**, **49.8 s**, **20.0 s**) are
49% of the 476 s attributed to tests. Each has cheap clustermates, and in every case checked **the cheap
peer does not cover the expensive one** — the cheap one guards the rule at unit level, the expensive one
guards it end-to-end through a real bout. That is a coverage ladder, not duplication, so the cut rule
would not license the cuts the procedure expected to find. The lever the data does offer is per-rule:
whether a given rule needs a bout-level rung at all.

**`CsvLine` (`src/logic/`) — one CSV codec for the writer and the reader.** Rules are written as full
sentences, so 711 of them contain a comma; the writer quoted correctly and the reader split on `,`,
shifting every numeric column one place right and reading `bouts` as **8697** against a true **56**. The
alternative considered and rejected was a comma-free label vocabulary — letting the storage format
dictate the classification. A second hand-rolled splitter is the same bug waiting again.

**Two junk counters removed from the profile.** Pass A's per-test rows carry `test` (the name) and
`order` (the declaration index), and file rows are the key-wise sum of their tests' — so both were
summed as though they were work, into every file row and into `totals`, where the run reported
`order: 2,953,665` and `test_smoke.gd` reported `order: 1705`. Nothing gated on them, which is why a
green suite carried them for a whole block. The aggregation now excludes one named `IDENTITY_KEYS` set
rather than three inline key checks that had drifted apart, and `test_suite_budget.gd` asserts the
shape — every key in the profile is a non-negative count and no identity field reaches `totals` — so
the next bookkeeping field added to a row cannot leak the same way.

**Regeneration no longer erases the audit.** Pass A's writer emitted both judgement columns empty every
time, so the next `WRITE_PROFILE=1` run destroyed 2424 hand-filled cells with a green suite either way;
it now merges them forward on `(origin_file, test_name)`. The bug behind it appeared **twice, in two
languages** — `FileAccess.open(path, WRITE)` truncates before the renderer reads the old file back,
exactly as `open(path, "w")` did in the Python helper an hour earlier. The carry-forward is demonstrated
rather than asserted: a full `WRITE_PROFILE=1` gate ran and the file came back 2431/2431 classified.

### Three rungs, a window on the run, and the collapse (tb48 Passes A–D, docs/TOOLING.md)

**Full gate 1493 s → 450 s across taskblocks 47–48**; fast gate ~126 s; a targeted run ~3.7 s.

**Pass A — three rungs, one runner.** `./run_tests.sh <file.gd>` joins `fast` and the full gate; a bare
filename resolves by search, and two files sharing a name prints both and exits 2, because that is a
repo mistake to fix rather than a case to disambiguate. The fixed floor was measured before deciding
what to skip: `gdlint src test` 6.14 s, import 2.32 s, parse guard 0.82 s, GUT startup ~1.2 s. A
targeted run lints only its target and skips the checkpoint parse guard; **the import step stays**,
because it registers a `class_name` and skipping it makes a new script invisible in a way that looks
like a broken test.

`tools/profile_suite.gd` became `tools/run_suite.gd` and is the **only** entry point. There had been two
into one suite and **only one of them failed the build** — `gut_cmdln.gd` passed `-gexit` while the
profiler called `quit(0)` unconditionally after writing its JSON. Artifacts are opt-in via
`WRITE_PROFILE`; counts print on every run, and a targeted run also prints its delta against the
committed profile.

**The turns budget was gating on luck**, found here rather than assumed: three full runs measured 1680,
1578 and 1385 turns — a 19% spread against 15% headroom — and all of it comes from
`test_full_mission.gd`, which seeds from the clock *on purpose*. Its turns are excluded now, in
aggregate and per-file; its bouts stay gated because that count is exactly `SAMPLE_SEEDS`.

**Pass B — a window on the run.** `SuiteRun` launches `run_tests.sh`, tails it live and can kill it;
`SuiteRunPanel` is the surface, mounted under both overlays beside the combat log. The feed is the real
output of the real script: filtering narrows what is *drawn*, never what is stored. Completion is
decided by an exit marker rather than by a process disappearing.

`WatchedRunOverlay` was **deleted** — it had been a fifth `SpectatorOverlay` subclass, and the reasoning
that produced it is the reasoning that produced the hierarchy `PLAN.md` exists to dissolve. It is a
panel now, so the block ended with one fewer subclass.

**Killing had to reach the grandchild.** `run_tests.sh` spawns Godot, and killing the shell left it
running: a full-gate run started by a test left **79 orphaned Godot processes**. Runs go under `setsid`
and the whole process group is signalled — through bash, because `kill` is a builtin and `OS.execute`
fails *silently* when it cannot find a binary, which is how the first fix appeared to work and did
nothing. Separately, `test_suite_run.gd` launched the full gate, which runs `test_suite_run.gd`:
unbounded recursion that reached **107 concurrent Godot processes** before it was obvious.

**Pass B2 — replay failures in the game.** The suite runs as a subprocess, so its maps live in that
process's memory and the launcher could only ever be a terminal in a window. `ReplayHandle` is a seed or
a callable returning `{state, mission}` — exactly what `BattleScene.load_battle` already takes — and
`ReplayCatalog` asks a failed test's script for one via a static `replay_handle_for`. A script without
the method has no visual form and is skipped; **"nothing to show" is the right answer for most of the
suite** rather than a fault. `WatchedRun` was folded onto handles, so a failed map sweep and a failed
completion seed queue in one list with one set of controls.

**And none of it was wired.** `offer_failures`, `bind` and `on_bout_finished` had zero callers in `src/`;
the panels sat holding `run = null`. Every piece was tested and proven to work *when called* and nothing
asserted it got called — `docs/11`'s named failure mode. Two further reasons nothing appeared: the panel
kept whatever bout was already on screen, so a working replay and a dead one looked identical (the board
is purged on launch now); and **`failures()` could not read a single real run**, because GUT colours its
output and every prefix check missed an escape sequence. That went unnoticed because the tests fed it
hand-written lines with no escapes — **input tidier than reality is worse than no test.**

**One shared path caused two more symptoms.** `SuiteRun`'s log name carried a `static` counter, which
restarts at 0 in every process — so the nested `SuiteRun` inside `test_suite_run.gd` truncated the file
the game's panel was tailing. A forced fast gate reported *"PASSED — 20 passing, 0 failing"* (that is
`test_grid.gd`'s count) and appeared to stall on whichever file was on screen when the log rewound. The
pid is in the name now.

**Pass C — a shared bout corpus.** `BoutCorpus` draws one random sample per suite run, plays it once and
hands out deep copies. **The draw stays clock-seeded**, which is the whole constraint: taskblock-46
established that a pinned window measures the pessimistic corner of the seed space, so sharing fixed
seeds would have undone that while the test kept passing. Records only, never live state — a mutated
cached `CombatState` would surface as a failure with no connection to its cause.

`test_completion_sampler.gd` went **24 bouts → 10**: three of its four bout-playing tests run on canned
records, because the shape of a report is a pure function of the records behind it. The end-to-end test
lost its duplicate sample — it had replayed the same eight seeds purely to compare two renderings of one
formatter. `test_full_mission.gd` plays none of its own.

**Pass D — both outliers diagnosed, and the budget grew eyes.** `test_ai_batch_yield.gd` measured 18.4 s
per bout and the guess was that the pacer's frame yields paid for it. **Measured false:** same seed,
tight 18485 ms against paced 19660 ms, 54 turns either way, 344 yields — the pacer is **6%**, about
3.4 ms a yield. The cost is bout *length*, 54 turns against the sampler's ~13. Nothing incidental, so
nothing cut.

`test_spectator_overlay.gd` costs 32.5 s with **zero bouts**, which no budget could see because every
gated counter measured AI work. `HulkTheme.ui_builds` closes that: every overlay's `_build_ui` calls
`HulkTheme.build()` and nothing in `src/logic/` does, so it moves for a view test and stays put for a
headless bout — asserted both ways. It measured **344**, and immediately named the file the pass was
about: `test_spectator_overlay.gd` tops it at 70 builds across 35 tests.

### The suite: measured, budgeted, tiered, watched, cut (tb47 Passes A–E, docs/TOOLING.md)

Tooling debt, raised because taskblock-46 was ~45 minutes of coding and ~2 hours of testing. The suite
had gone ~355 s → ~1370 s across one block and had never been profiled, tiered or audited.

**Pass A — profiled, changed nothing.** `tools/profile_suite.gd` drives `GutRunner` directly and
snapshots deterministic work counters at each script and test boundary, writing a committed
`test/SUITE-PROFILE.md` (for reading) and `test/suite_profile.json` (for the budget). New counters where
nothing was counting: `Pathfinder.floods`, `CombatState.turns_resolved` and `CombatState.bouts_built`.
**Turns are counted at `advance_turn`, not in `BoutRunner`** — a turn is a turn whether a runner drove
it or a test did, and a runner-side counter would have reported Pass E's scripted rewrites as free.

The findings contradicted the framing twice: **11 of 242 files build a bout, not 23**, and
`test_full_mission.gd` was not the expensive one — `test_completion_sampler.gd` was, at 730 s and 88
bouts, three times the integration test. Its own header, written the previous block, called it
"deliberately cheap … at most a handful of bouts, and most run none at all". Four tests were 995 s of
1493 s; the worst spent **252 s and 20 full missions asserting that a unit had not moved.**

**Pass B — budgets on counts, not seconds.** Measured justification rather than assertion: two runs of
identical work came out at **1286 s and 1493 s** while the work counts were identical to the integer.
Counts also name the cause — taskblock-46's search-memory fix took turns per bout 19.1 → 26.8, so a
turns budget goes red on the commit that did it where a seconds budget goes red three commits later.
`candidates` and `shot_planes` are reported but deliberately **not** gated: they move with how the
planner scores rather than with how much the suite asks of it, and an AI change failing a suite-cost
test is the false positive that gets budgets deleted.

**Pass C — two gates.** `./run_tests.sh fast` (119 s) skips the bout-building files; `./run_tests.sh`
(537 s) is everything and remains the rule before a pass commits. **The tier is a file list, not a
directory**: ten of eleven bout files live outside `test/integration/`, so a directory rule would have
declared the fast gate bout-free while it played most of the bouts. `SAMPLE_SEEDS` re-derived 20 → 8.

**Pass D — the watched run.** `WatchedRun` sequences a seed list; `WatchedRunOverlay` extends
`SpectatorOverlay` so a watched bout has exactly the controls a normal bout has. **No artifact**: a
seed is already a complete reproduction handle, so bouts are rebuilt rather than replayed.
`CompletionSampler.build_for_seed` was split out so the watched and headless paths cannot build
different bouts from the same seed — asserted, not assumed.

**And that split surfaced the block's most important finding.** `CompletionSampler` was still passing
`&"AGGRESSIVE"` as its profile id, a playstyle taskblock-46 Pass E retired. An unknown id does not
throw — the scorer falls back to unweighted — so **every completion rate measured since that pass ran
with no profile weights at all**: 56/100 unweighted against **72/100** weighted, mean turns 26.8
against 13.5. Against the retired planner's 75% on level ground the gap is **3 points, not 19**, which
re-frames most of `BR45.03`. `MIN_COMPLETION_RATE` deliberately left at 0.35 — out of this block's
scope, and moving a floor the day the number moves is how this project got into trouble with that
constant before.

**Pass E — retarget, merge, cut, in that order.** Turns 2651 → 1578, bouts 79 → 62, gate 930 s → 537 s,
**with the assertion count unchanged** (103192 → 103187 against two fewer test functions), which was
the acceptance: a large drop in assertions would have meant coverage left with the redundancy.

- *Retarget*: `test_frames_pass_during_the_batch` played an entire mission to prove one frame passed —
  and was not even exercising the case `advance_ai_turns` exists for, since an all-AI bout never
  reaches its `wants_turn_for` exit. Squad 0 is HUMAN now.
- *Merge*: the two in-window verb tests each paid for a full sample to make two assertions about one
  invocation. For a bout test the fixture is the cost.
- *Cut*: `test_the_batch_still_runs_to_completion` — 178 s and a 400-turn bout to assert
  `round_number > 0`. **Covering test: `test_a_yielding_batch_produces_the_identical_bout`**,
  demonstrated by sabotaging `advance_ai_turns` to strand its loop and confirming the fingerprint test
  went red on its own. Sabotage reverted before the cut.

### Search verbs get a memory; one-way ground found underneath them (post-tb46, BR46.01/BR46.02)

**`ROAM` and `HUNT` oscillated between two cells for a whole mission, and it shipped.** Both score
`travel_fraction` — go as far as you can — which is memoryless: the farthest reachable cell from A is
B, and the farthest from B is A. A unit with no enemy in sight walked to the edge of its reach and then
shuttled between two tiles until the turn cap. Found in a supervisor's real combat log, where **every
unit on both squads decided `roam` on every turn and covered two or three distinct cells for the entire
bout**; reproduced on an open board as 6 distinct cells in 14 turns with ten of those turns spent
alternating between `(19,23)` and `(31,23)`.

**taskblock-46 Pass C had already written the fix down and applied it to one verb only.**
`SearchRoute`'s own comment says oldest-visit-wins "cannot ping-pong between two while a third is
ignored" — true, and `PATROL` was the only verb with a route to hang that on. `Unit.recent_cells` now
generalises it: a bounded trail (`RECENT_CELLS` = 8, flagged) written for **every** unit every turn,
not only while searching, because a unit that fought across a room and then lost its target must not
treat that room as unexplored. `UtilityContext.INPUT_UNVISITED` grades it by recency rather than as a
binary visited/not — a binary makes every cell outside the trail identical and permits the same
oscillation with a longer period.

`roam` and `hunt` score it unfloored, so ground just left can reach zero; **`putter` scores it floored
(0.5) on purpose**, because puttering is meant to stay local and an unfloored memory would quietly turn
it into a slow roam. After the fix the same probe covers 15 distinct cells in 14 turns. Regression-
tested as ground covered *and* as an explicit A-B-A-B alternation count, since "it moved a lot" and "it
stopped looping" are different claims and only the second is the defect.

**It did not improve completion, and the 20-seed reading that suggested it had was a lucky draw.** The
deterministic 100-seed escalation after the fix returns **56/100 (56.0%)**; a sample run had shown
14/20 (70%). There is no clean before/after at this sample size — the last 100-seed reading was 60% and
predates Pass E, so it measures a different action pool, and comparing the two would be comparing
builds rather than behaviours. **What the fix demonstrably changed is the failure mode:** `TERMINATED`
— bouts that simply never end, the oscillation's own signature — fell **27 → 20**, while `STRANDED`
rose **13 → 24**. Units that cover ground find each other and some of those fights are lost. The fix is
justified by the behaviour being correct, not by the completion rate, and the remaining gap points at
combat quality rather than at another search gate.

**The escalation also got slower**: it now exceeds 900 s where it used to fit, because bouts run longer
when units actually travel. Mean turns to complete went 19.1 → 26.8.

**Chasing the other half of the same report turned up a bigger, separate problem: 16 of 40 generated
maps contain ground a unit can walk into and never leave** (`BR46.02`, open). Descent is free; climbing
reads a `CLIMBER` part tag that **no part in the repo carries**, so every lowered region is a one-way
door for every unit that exists. Worst seed has 216 such cells.

**A symmetric connectivity check cannot see this, which is why it was never caught** — spawn zones are
mutually reachable on 60 of 60 seeds, so the maps read as fine. The defect only appears under
*asymmetric* reachability: flood out from a spawn, then flood back from each cell reached and ask
whether the spawn is still in the set. Deliberately not fixed here: the direction is a design call
between authoring a `CLIMBER` part, constraining `MapGen` to guarantee two-way connectivity, and having
the planner refuse a one-way step. Recorded with the measurement and the options rather than picked.

**BR32.10 had been misattributed twice and is now split.** "The AI is stuck on a concave map" is a
symptom with at least three unrelated causes: no path to a firing cell (the original, fixed in tb46
Pass C), no memory of where it has been (`BR46.01`), and no way back out of where it went
(`BR46.02`). The combat log distinguishes them; the screen does not.

**BR40.03 and BR40.04 closed `Resolved` by the supervisor.** Worth stating what that does *not* cover:
the sweep behind them measured pit *depth*, not *escapability*. No pits, and still somewhere to get
stuck.

### AI v2, part three: the tier table filled, and the playstyle vocabulary retired (tb46 Passes A–F, docs/11)

**Pass A — nothing sinks into a raised room's floor (BR40.03/BR40.04).** One cause, two entries.
`MapGen._repair_stranded_elevation` floods with a real `Pathfinder` and flattens every unreached `OPEN`
cell to level 0, and `Pathfinder._base_cost` returns `-1.0` for any cell carrying a live blocker — so a
cell a scattered crate had just landed on was **unreachable by construction** and got flattened
regardless of whether anything about it was stranded. For spawn cells the flatten fired and then
`_mark_zone` erased the blocker, leaving a correctly-marked tile a full `LEVEL_HEIGHT` below its own
room; since no part in the repo carries `CLIMBER`, a unit spawned there had exactly one reachable cell
and spent the battle in it. Blocker cells are now deferred out of the flatten and levelled against their
neighbours afterwards.

**The fix was wrong once first, and the miss is the useful part:** the deferred pass checked only
orthogonal neighbours while the flood is 8-way, which left **1 sunk crate out of 9,279** — a single
cell across a 40-seed sweep, invisible to anything but a total count.

**And the tests were vacuous until they were told not to be.** Every assertion in the file is free on a
flat map ("no cell sits in a pit" is trivially true if nothing is ever raised), so a change that quietly
stopped generating elevation would have turned the whole file green while deleting the feature it
guards. `test_the_generator_still_authors_raised_rooms` pins the other side: 30/40 maps still author a
raised room, 3,996 of 22,938 floored cells sit above level 0.

**Pass B — the completion number became re-takeable.** `test_full_mission.gd` sampled seeds 0–11 every
run, which was the *pessimistic* window: 41.7% there against 66.7% on seeds 12–23 on the identical
build, a 25-point spread the test could not see. `CompletionSampler` draws `SAMPLE_SEEDS` random seeds
per run and prints every one, so a run is reproducible after the fact; on a dip it reports the exact
command for the deterministic 100-seed escalation rather than running it automatically.

`SAMPLE_SEEDS` is **sized from the measured escalation cost, not by feel** — at a 0.54 rate against a
0.35 floor, n=10 escalates 1 run in 9 and n=20 escalates 1 in 38 for four seconds more in expectation.
Note the non-monotonicity that makes intuition useless here: n=12 is *worse* than n=10 (0.126 vs 0.114),
because the threshold is an integer count and `ceil(0.35 × 12) = 5` demands 41.7% where
`ceil(0.35 × 10) = 4` demands 40%.

**Pass C — the search verbs, and a bug fixed twice in the same place.** Four behaviours (`ROAM`,
`PATROL`, `HUNT`, `PUTTER`) for a unit with nothing in sight, plus `SearchRoute` for the one verb with
state. Routes are derived lazily from wherever the unit stands, deterministically and without an RNG,
and scheduled by **oldest-visit-wins** — no authored order, no index to advance, so every point gets
visited, it cannot ping-pong between two while a third is ignored, and an unreachable point ages out of
contention on its own with no detect-and-remove step.

`LineOfFire.approach_path`/`closing_path` were deleted here (see `SUPERSEDED.md`); what replaces them is
not a branch at all but path distance from one flood rooted at the target.

**The candidate-cell early-out was wrong for the second time.** `UtilityContext.build` gated computing
candidate cells on having something to move toward, which taskblock-45 Pass D had already found wrong
for the mission actions and this pass found wrong again for the search verbs — for which "nothing in
sight" is the entire trigger. Whatever the list of reasons to move is, it is never complete, and a unit
whose reason is missing from it silently gets a candidate set of one cell. The gate is gone rather than
extended.

**Pass D — `Panic`, the named give-up.** A utility planner can genuinely rate every option at or below
the veto floor, which the branch cascade it replaced could not even express. Panic emits a named event
with a **reason**: `nothing_offered` says the pool has a hole in it for this unit, `all_vetoed` says the
pool covered it and every option scored zero, `budget_aborted` says the clock ran out. Those want
different fixes and used to be the same silent shrug — "the AI just stood there" and "the AI panicked"
look identical from outside.

**It re-broke a guard the retired planner had carried with a comment saying it had been caught live:**
a unit holding its own extraction tile looks identical to a stalled one from the scorer's side, and
panicking it into a shutdown takes a unit that was about to extract cleanly out of the mission.
`EndTurnAction.is_holding_position` is checked first now, and
`test_a_winning_bout_runs_to_a_terminal_state` caught it again — which is the argument for that test
existing rather than for trusting the reasoning.

**Pass E — the tier table, and the playstyle enum retired.**

- **Tier gates.** `shoot` and `take_cover` at Grunt-and-above; `overwatch`, `flank` and `suppress` at
  Trained-and-above. `flank` and `suppress` were the only two tier-table rows whose executors already
  existed — `item`, `call help`, `bait` and `ambush` are **not built**, and `call help` has no mechanism
  at all (a unit cannot influence another unit's plan today). They are `PLAN.md` items, not authoring.
- **Setting a batch objective is Elite-only**, where reading one stays Trained-and-above
  (`WorldView.OBJECTIVE_SETTING_TIERS`). A Trained batch is a real configuration; it just has nobody in
  it who makes the call.
- **`UtilityLookahead` — Elite's depth 2–3 search.** Depth 2 is the enemy's shot from where it stands
  (one visibility field per known enemy, reused across every cell); depth 3 is the enemy moving first
  and then shooting (one field per cell, so it runs over a fixed shortlist of the best-scoring cells).
  It is expressed as **one normalized input** rather than as a minimax beside the scorer, because a
  utility AI has one place to put "this option is worse than it looks" and two ways to decide is the
  no-parallel-systems rule broken. Measured on the reference board: a cell in a wall's shadow predicts
  0.00 threat at depth 2 and 1.00 at depth 3, because the enemy can walk around the wall — cover that
  can be stepped around is not cover, and that is the whole behavioural difference between Elite and
  Trained.
- **The playstyle vocabulary is deleted, bridge and all.** See `SUPERSEDED.md` for what it was; the
  short version is that six names selected between two profiles, five of them landing on the same one.

**Four rows of the table played identically before they were made not to, and both causes were
methodological rather than mechanical.** Elite and Trained had the same action pool, so the comparison —
which read only the pool — declared Elite decorative when its entire difference was in the world-model
and depth columns. And `defensive` withdrew exactly as readily as `cowardly` because it had **no stated
weight** for `seek_extraction`: an absent weight is a neutral opinion, and "defensive" is not neutral
about retreat.

**Two test boards were not the boards their comments described.** Both used `place_floor` plus a
hand-assigned blocker, which is cover that everything can see straight through — sight is blocked by
`Grid.opacity`, which only `GridFixture.place_wall` sets. Fixing that then exposed the opposite error:
a wall drawn *across* the firing lane hid the enemy outright, every combat action fell out of the pool,
and all four profiles returned the single verb they had left. **A board that cannot express a difference
is not evidence that there is none.**

**Completion across the block**, all measured after the fact rather than quoted from a prior pass:
taskblock-45 end 54% → Pass A/B re-baseline 50% (24 seeds) / 54% (100 seeds) → Pass C 60% → Pass D 60%.
The retired branch planner sat at 75% on 24 seeds of fixed ground, so `BR45.03` is narrowed, not closed.

**The one thing this block did NOT establish, stated plainly:** `Unit.intelligence_tier` defaults to
`TRAINED` and **nothing authors it** — not a preset, not a matrix, not a roster entry. Every rate above
is an all-Trained rate, and the Mindless, Grunt and Elite rows, the memory and blackboard gates, and the
entire Elite lookahead are reachable from tests and by hand only. The tier table is built and unshipped;
authoring tiers onto units is `PLAN.md` NEXT item 2.

## Economy

**Inventory & economy** (docs/05) — mass/bulk/RAM; discount once at the worn layer (body-attached
floor 0.8); rigidity (soft collapse, rigid don't); body-carry as inert cargo; 7 resources;
`salvage_yield` on parts. Field objects (scrap_pile, goo_barrel, crate, pillar, forklift w/ POWER
socket, barrel_pallet) — on-board resource/cover, block movement, project into the shot plane.

## Matrices

**Matrices & surrogates** (docs/04) — logic vs intelligence; base/link split; docks into `MATRIX`
socket; surrogates dock like parts (tier DAG); matrices never lost; `Matrix.ai_profile` carries AI
personality (**was `Matrix.playstyle` — renamed by taskblock-46 Pass E, which retired the playstyle
vocabulary; it now names a `UtilityProfile` id**). *Frozen — no more depth.*
