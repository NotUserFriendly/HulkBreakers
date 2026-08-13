# Taskblock 69 Report — a blocker's facing reaches everything that reads a blocker

Passes A, B, C and D landed in order. Full gate green: **3615 tests, 0 failures, 198 s, within the
work budget, no fallback** — re-taken at the push, after the close-out and the ramp addendum. The
438 s figure this report first carried was measured before both and is superseded; the spread is the
corpus draw, not a speed-up (`bouts` 81 against 86, `turns` 643 against 855).

**Appended after the supervisor asked what ramps are doing.** They were right to: a `ramp` is a flat
slab identical to `ship_floor` that nothing reads a facing from, and I had justified a real decision
in this block with a stale docstring that said otherwise. The correction is in *Decisions*, the
finding is in *Open questions*, and the stub is now flagged in the part and guarded by a test rather
than left to the comments that went stale in the first place.

**The parity result, which is the block's deliverable.** One resized `wall` on one board at a
quarter turn, and a probe point that is solid **only because the wall is turned**. Every consumer
that builds blocker geometry was asked, and every one agrees: the accessor,
`RayCaster.cast_geometry`, `RayCaster.obstructed`, `RayCaster.blocker_obstructed_among`,
`SightSpans`, `PartPicker.hit`, and `BoardView`'s real drawn meshes. The mirror test asks the same
consumers about the point the wall occupies only when it is **not** turned, which is the half a
double rotation or a mirrored convention would pass. `ClaimResolver` and `Detonation` — the other
two the acceptance names — have their own cases, and so does `CameraFramingModule`.

**No existing board moved.** No authored map or section changed, and none carries a non-zero facing
(checked across `data/maps` and all of `data/sections/*.tres`). The only `data/` change in this block
is the ramp stub flag added at the close-out, which is a `display_name` string on a part. The byte-identity
claim is asserted rather than assumed: `test_blocker_facing_render.gd::test_a_facing_of_zero_draws_
exactly_what_it_drew_before` compares the accessor's transforms and boxes directly against the
pre-existing `assembly_placements(part, cell, 0.0, null, height)` expression, across three cells
including a raised one.

---

## Decisions made without asking

**The taskblock's table of nine call sites had two wrong rows and omitted a tenth site. I fixed
the ten that are real.** Checked line by line before starting:

| the table says | what is actually there |
|---|---|
| `detonation.gd:92` feeds blast reach | the **unit** assembly walk, already passing `unit.orientation`. Detonation's blocker branch (`:99`) returns a cell centre and builds no boxes at all |
| `claim_resolver.gd:358` feeds section claims | already passes `placement.facing` — it works from a `MapPlacement`, not from `Grid.blockers`, so it never had the discarded-facing defect |
| — | `camera_framing_module.gd:86` builds blocker boxes at a literal `0.0` exactly as the nine did, and the table does not name it |

The alternative was to do the nine named and report the rest. I took the acceptance line — *"every
blocker consumer uses it"* — as the authority over the table, because a fix that left one consumer
building its own boxes would have failed the very property the block exists to establish. Both
misattributions and the tenth site are recorded at the code and in `CHANGELOG.md`.

**Detonation is left alone, deliberately.** Its blocker branch answers the blocker's own cell
centre and `resolve` measures reach in whole cells; a rotation about a cell's vertical axis does not
move that centre. Routing it through the accessor would have been a behaviour change (the geometry
centre, not the cell centre) that nobody asked for. Pinned as a fact instead —
`test_a_rotated_blocker_detonates_from_the_same_place_it_always_did`. The real limit there is that
`MapPlacement.offset` **does** displace a blocker from its cell centre and that branch does not read
it; that is `PLAN`'s *a cell holds one blocker* territory and is named in the test rather than left
to be found.

**Two consumers were measuring rotated boxes as axis-aligned, and I fixed that too.**
`CameraFramingModule._absorb` and `ClaimResolver.placement_aabb` each built a box's AABB as
`centre ± size / 2`. That is the same answer only while every transform is a pure translation,
because a box's centre does not move when the box turns about it — so a three-cell wall framed and
claimed as three cells wide on X however far round it had been turned. Both now go through
`UnitGeometry.placements_aabb`. This is strictly wider than "read the facing", and I judged it in
scope because without it the facing reaches those two consumers and then gets measured away, which
would have made the acceptance true in the code and false in effect. `CameraFramingModule`'s own
header says the bounds must never be *"a second formula"*; it was one.

**The derivation fills in blockers and field items, and leaves surfaces on the panel's value.** The
taskblock did not say where the derivation stops. The kinds it fills in are the ones whose facing
**every consumer discarded until Pass A**, so no author has ever been able to mean anything by the
panel value on one. Asserted both ways
(`test_a_ramp_still_takes_the_authored_facing_from_the_panel`), and it is one line in
`EditorModule.placement_facing` to reverse.

> **Correction, after the supervisor asked what ramps are doing.** The reason I first gave for this
> carve-out was wrong. I wrote that *"a ramp's direction is a thing an author states"*, taking it
> from `MapPlacement.facing`'s own docstring — *"Surfaces only: radians... What makes a ramp
> directional"* — which is pre-tb60 and false. **A ramp's facing is read by nothing.**
> `RampGeometry.edge_heights` has no production caller, `ramp.tres` is a flat slab byte-identical to
> `ship_floor`'s, and `Surface.facing` never reached the pathfinder. There was no live ramp
> behaviour for the carve-out to protect.
>
> **So the carve-out is inert today, and I reported it as load-bearing.** The editor's placeable
> surfaces are the GROUND-attaching parts — `ramp` and `ship_floor` — and neither's facing is read.
> The one `Surface.facing` that means anything is the **mag lift pad**, where it is a *pairing
> record* naming the partner pad's cell rather than a direction (`Surface.mag_lift_destination`) —
> and a pad attaches at `LEDGE`, so `EditorTools.kind_for` makes it a blocker and it never takes the
> surface path anyway.
>
> **I would still keep the carve-out**, at much lower confidence than I first stated: it costs
> nothing, and deriving a *direction* into a field that is a pairing record for one part and inert
> for the rest is the kind of thing that is cheap to skip and expensive to unpick. But it protects
> nothing today, and that is the honest version. The stale docstring is corrected, along with
> `Surface.RAMP_TAG`'s claim that a ramp rides a sloped profile.

**A bottom-face click derives nothing.** The taskblock names a side click and a top click. A click
on the underside of a thing implies no edge, so it keeps the author's own value rather than snapping
to whichever axis the arithmetic reaches first. Same for a pick that reported no face, and for a top
click whose pick reported no point.

**`BR69.01` was logged, not fixed.** `ClaimResolver.placement_aabb` never applies
`PlacedVolume.placed_part`, so a section claim measures the library part and ignores
`MapPlacement.size` — a `3 x 1 x 1` wall claims a `1 x 1 x 1` footprint. Found while writing the
parity test, which could not have been written honestly against a resized wall without asserting the
defect away (it uses `ledge_veneer`, whose authored box is asymmetric with no resize needed). It is
`size`, not `facing`, and no authored section carries a non-zero size today, so it is latent. Fixing
it is one line and changes what section geometry claims, which deserves its own measurement rather
than riding along in a block about a different field.

**`GridPlacement.place` held a second copy of the `GROUND` rule** and Pass D found it: the function's
doc comment said *"places `part` at `cell` if `can_place` allows it"* while its `GROUND` branch
spelled the occupancy test out again. Loosening `can_place` alone left `place` refusing, which is how
it surfaced. It calls `can_place` now — in scope because the pass could not otherwise be correct.

**Two named tests were rewritten rather than relaxed.** The taskblock asks for one:
`test_ground_still_refuses_a_second_placement_on_an_occupied_cell` → `..._at_the_same_height`. The
second turned up in the gate — `test_editor_controller.gd`'s surface-stacking test asserted that a
second surface at 2.5 is *warned about*, which Pass D makes wrong. It now asserts two decks are not
warned and that two at one height still are, which is the opinion-versus-refusal distinction it
really guards.

---

## Tests that failed, then were corrected

**Five failing test cases before correction, across four causes. All were the test being wrong, not
the change.**

**1. `test_blocker_facing_parity.gd` — the probe points were outside the box (2 tests, 8 asserts).**
Written against a wall resized to `(3, 1, 0.2)` at cell `(3, 3)`, with probes at ±2 cells. A
three-cell wall centred on a cell spans ±1.5, so both probes sat in empty air and every consumer
correctly answered "nothing there". Moved to ±1 cell.

**2. Same file — a 0.2-thick wall cannot register in `SightSpans`, by design.** With the probes
fixed, the `SightSpans` assertions still failed. `SightSpans` registers only the cells a box **fully**
covers on X and Z; its own header calls that the safe direction and states outright that a
sub-cell-thick wall blocks the real march without appearing in the spans. So the fixture was asking
one of the consumers under test a question it answers "clear" to for reasons having nothing to do
with facing. The wall is one cell thick now, and the file's header says why a thinner one — the
better shape — does not work.

**3. Same file — the camera-framing assertion failed and the code was wrong, not the test.** The
turned wall framed as three cells wide on X. That is `CameraFramingModule._absorb`'s
centre-and-size AABB, above. **This is the useful one:** the test was written expecting the
accessor to be enough, and it found a second place where the facing arrives and is then measured
away.

**4. `test_parts_list.gd` — the spinbox snaps, and the test asserted the unsnapped value.** The
facing field has a 0.01 step measured from its own `-TAU` minimum, so setting `PI / 2.0` stores
**1.56681469**, not 1.5707963. The test asserted the placement carried `PI / 2.0`. Corrected to read
the panel back and compare against that — the panel is the authority on what the author asked for,
so it is asked.

**5. `test_editor_controller.gd::test_a_second_surface_on_one_cell_is_still_placed_and_still_only_
warned` — the fixture held the assumption Pass D deliberately overturned.** Caught by the fast gate,
not by a targeted run. Rewritten, per the decision above.

**6. `test_battle_scene.gd::test_new_battle_logs_the_seed_at_bout_start_to_both_sinks` — a race in
the suite, found by the pre-push full gate** (`BR69.02`). Not caused by this block: the same gate had
been green 317 s earlier on the same tree, and the file passes in isolation. `FileSink` defaults to
`res://out/combat.log` and **all eight shard processes append to it concurrently**, while the test
took the **last** `bout_start` line in that shared file and compared it to its own — so it read
another shard's `seed=0` against its own `seed=2`. It now searches for a line **equal to** this
scene's own header, which is what *"the same event reached both sinks"* asserts and cannot be raced.
Demonstrated non-vacuous by feeding the two sinks different events. **The hazard itself is left
open** — eight processes writing one live log is a property of the sharded gate, and any future test
reasoning about that file's contents as a whole will race the same way.

---

## `SUPERVISOR`-owned entries moved to `Pending`

None. No `SUPERVISOR`-owned `docs/BUGS.md` entry was touched this block.

---

## Open questions

**The gizmo has no rotate handle, so one acceptance line is unmet.** *"A side click and a top click
each derive a facing; the gizmo overrides it and the override persists"* — the first and third
clauses are built and tested; the second cannot be driven, because `Gizmo.Handles` is `TRANSLATE,
RESIZE` and nothing else. The taskblock and the supervisor's decision table both refer to the
manipulation gizmo as though it already rotates, so this reads as an assumption rather than a
descope.

What is built is the property an override depends on: the derived facing is **written into the
record at placement time and never re-applied on read**, asserted by writing an adjustment straight
onto the record, saving, reloading and re-rendering — and asserting the redraw is *not* where the
derived facing would have put it. So the value would hold; there is simply no UI that changes it.
Queued as `PLAN` NEXT item 1 with the two real costs named (angular drag is a genuine addition to
`GizmoDrag`, and how an author reaches a third handle set is a question `EditorTools.GIZMO_TOOLS`
should answer as data). **Flagging rather than building it** — a third gizmo verb is its own pass,
and inventing one inside this block is the kind of unasked design call the report's first section
exists to catch.

**Is leaving surfaces off the derivation the right line?** See the correction in the decisions
section: the evidence is much thinner than I first reported. The carve-out protects nothing today,
because no editor-placeable surface has a facing that anything reads. It is one line to reverse.

**Ramps are a stub and were found to be one while checking that.** `ramp.tres` is a flat slab
identical to `ship_floor`, `RampGeometry.edge_heights` has had no production caller since
taskblock-38 Pass C wrote it, `MapGen` authors none, and the only live reader of `Surface.RAMP_TAG`
is the player-facing label in `CellInspection`. **That is unbuilt content, not a removal** — tb60
Pass A retired a ramp as *machinery* and said explicitly that it survives as content; the content
never arrived. Queued as `PLAN`'s *Ramps become real slopes*, flagged in the part's `display_name`
so an author reaching for one sees it, and guarded by
`test_ramp_geometry.gd::test_a_ramp_is_still_a_flat_stub_and_says_so`, whose failure message is the
instruction for whoever makes them real. **The guard is a guard rather than a comment because a
comment is exactly what went stale here** — `Surface.RAMP_TAG`'s header claimed a sloped profile for
thirty-one taskblocks. Demonstrated non-vacuous both ways: giving the ramp a taller box reddens the
slope half, removing the `display_name` flag reddens the other.

**`PLAN` item 1's two stale lines are corrected by the item closing.** Both claims — *"a third fixed
generation height (+4) is what surfaces it"* and *"an exterior wall must follow its neighbouring
tiles up"* — described work that is built and tested (`MapGen.TALL_ROOM_LEVEL`,
`test_a_tall_shelf_is_generated_somewhere_in_a_seed_sweep`,
`test_no_generated_wall_is_shorter_than_the_floor_beside_it`). The item is gone from `PLAN` because
it landed, and the same stale sentence in `Blocker`'s own header — which would have outlived the
`PLAN` item — was corrected in place. Neither claim was a reason for this block and neither shaped
any pass.
