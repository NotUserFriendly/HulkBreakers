# Taskblock 55 Report — Only parts carry height, and sections learn to declare

All five passes landed in order and the suite is green at **2795 tests**. Pass A came from a prior
session; B–E landed in this one, each committed green. A closing doc audit found one stale test and
three living-doc gaps, all noted below. **The block was followed by a doc review in which no code was
touched** — see the final section, which also records two defects of mine that surfaced only after
this report first called the block green.

## Decisions made without asking

- **The `tile` vocabulary guard was retired, not weakened.** It banned the word outright, so the
  first code that used it *as intended* failed 73 times across three files. The alternatives were
  a path-scoped exemption (which would have exempted `board_view.gd` — the file with 21 of the
  original 288 misuses, the highest-risk one) or an allowlist entry for `tile` itself (which is
  the guard switched off). Neither is a guard. The distinction I settled on is that **a total ban
  is the right instrument for a *retired* word and the wrong one for a *reserved* one**: `void`
  and `HULK_` must never appear and keep their guards; `tile` was swept out of its wrong sense in
  tb54 specifically so this block could give it its right one, which makes that ban a finished
  migration. **This was raised with the supervisor before acting** and confirmed — recorded here
  because the reasoning, not just the outcome, is what a later reader will need.

- **Grid lines went back to one flat plane rather than following the tile.** The pass says the
  grid may be "one flat plane, or nothing" and that a tile "is the only thing at that elevation."
  Those two together rule out a border riding a tile's top face — it would be the same co-planar
  pairing the ground quad was deleted for. The alternative (lines at tile height) is more legible
  on a stepped board and I passed on it for that reason. A raised tile now hides the lines beneath
  it, and its edge is marked by its own real sides instead.

- **`Surface` was documented as *not* a tile rather than renamed.** A tile is the walkable `Part`;
  a `Surface` is the record of one placed at a cell. Renaming `Surface` to `Tile` would have been
  a ~30-file mechanical change well outside Pass B, and would have been wrong besides — not every
  `Surface` holds a tile (a ladder is placed identically and is explicitly not walkable).

- **A claim is a `Resource` carrying a `Box`, never a `Part` subclass.** Subclassing would have
  inherited hp, material, sockets, `attaches_to` and destructibility — every one of which a claim
  must not have — and each would then need suppressing somewhere. That is the kind of exclusion
  list nobody can justify two blocks later.

- **Vertical joins were lifted out of `stitch` into their own path** rather than encoded as a cell
  offset of `(0,0)`. The horizontal path is written in cell offsets, which say nothing about a
  stacked section; a zero offset that quietly meant "and also separated in Y" reads fine and is
  wrong.

- **Scope taken on: `BR55.01` was recorded rather than fixed.** An intermittent engine abort in
  `LoS.has_los`, seen once in a full run and not reproducible. `Grid.get_opacity` indexes a flat
  array with no bounds check and `LoS` never calls `in_bounds`. Guessing at a fix without a
  reproduction would be a change nobody could verify, and it is on the AI path rather than this
  block's.

## Tests that failed, then were corrected

**Ten failing before correction, across four episodes.**

1. **Three stacking assertions assumed a deck sits at the ceiling height. It sits 0.2 above it.**
   `ship_floor` is a 0.2-thick slab hung *below* the height it is placed at, so a deck resting its
   underside on a 3.0 ceiling has its walkable top at **3.2**. The resolver was right and my
   assertions were wrong. This is the most useful failure in the block: it is also the clearest
   argument for the interval model, since a quantized grid at any usable resolution could not
   express a 0.2 deck, let alone tell "resting on the ceiling" from "overlapping the room below."

2. **Four merge tests placed the two sections flush, so their walls never overlapped.** Flush
   placement puts two walls in *adjacent* cells — touching face to face, which is the doubled-wall
   defect the merge verb exists to prevent, not the merge case. Sharing a wall means the sections
   overlap by that column. Fixture geometry was wrong, not the resolver.

3. **Four tests passed while proving nothing.** Three were in Pass E and only showed it in their
   own printed output: the clutter cap was never reached (the fixture tagged clutter `barrel`,
   which no part answers to, so every one was silently skipped); an assembly "reproduced" an empty
   board twice; and a ban test banned a tag the section did not offer. All three now assert the
   positive case first — cap reached, assembly non-empty, banned tag genuinely offered.

   The fourth surfaced only in the closing audit: `test_grid_line_color_is_pushed_well_away_from_
   the_ground_color` compared grid lines against `WorldPalette.GROUND` — **a colour nothing has
   drawn since Pass B deleted the ground quad.** A contrast assertion against a colour that is
   never rendered passes forever and means nothing. It now measures against the *material* colour a
   floor tile is actually drawn in. Worth flagging as a class: deleting a thing does not fail the
   tests that measured it, it just makes them vacuous, and only reading them catches that.

4. **The retired-word guard caught my own new comments, twice.** First in three files during Pass
   B — I had written "every cell is void", the taskblock's own phrasing, and `empty`/`unfloored` is
   the live word — and again in the closing audit, in the very note explaining why
   `WorldPalette.GROUND` is no longer drawn. **This is the third block running in which vocabulary
   guards have caught the author writing about them**, which keeps being both a good sign the rule
   is real and a standing hazard when documenting a retirement.

## Living-doc gaps found in the closing audit

Recorded because each was a real staleness rather than a formatting tidy:

- **`PLAN.md` still carried the full specs for the vocabulary and stacking items** under "landed"
  headers. `PLAN.md` is forward-only, so a landed item reading as an unbuilt spec is the one thing
  it must not do. Both are collapsed to a landed summary, with the genuinely-still-open residue
  kept as its own list (`is_room` adjacency, the unconsumed encounter whitelist, the
  `part_for_tag` hook, and the absent thin wall part), each carrying its own **Needs:** line.
- **`SUPERSEDED.md` had only Pass B's reversals.** Passes C, D and E each overturned a recorded
  decision — the `MapSerializer` delegation becoming partial, `SectionEdge.side` no longer being
  "a closed set of four", openings gaining a height, and `to_grid` gaining a roll. Five rows added,
  including one for `WorldPalette.GROUND` no longer being drawn in.
- **`docs/10` described a ground plane that no longer exists** ("the ground is a distinct value
  from the void so the board is actually visible"), and used the retired absence word in its own
  palette table. Corrected, and the tile/cell distinction stated where the palette is defined.

## Open questions

- **The literal "0.2 merges to 0.2, not 0.4" case cannot be exercised with shipped content.** The
  shipped `wall` is a full-cell **1.0 x 2.4 x 1.0** box, not a thin slab, so there is no 0.2-thick
  wall to merge. The test asserts the *invariant* instead — merged thickness equals one part's own
  authored thickness, read from the part — which holds at any thickness and does not bake in a
  number the content does not have. If walls are meant to become thin slabs, that is content work
  and the assertion already covers it; if the 0.2 in the spec was illustrative, nothing is owed.

- **`is_room` grouping is order-based, not adjacency-based.** A section declaring `is_room` starts
  a room; one that does not joins the room already open. With two sections there is only one
  possible adjacency, so a real adjacency graph would be inventing the generator's job — but this
  will need replacing when the generator lands, and it is the one place in the vocabulary where the
  implementation is narrower than the concept.

- **`SectionRoller.part_for_tag` is a flagged hook, not a design.** A clutter tag names a *kind* of
  thing and choosing which part a kind resolves to is a content library's job. There is no content
  library, so it resolves a tag to a part of the same id and to nothing otherwise — deliberately
  the dullest possible rule, so it does not quietly become where content selection lives.

- **The suite's `escaped`/`turns`/`floods` counters are not comparable run to run.** I chased an
  apparent `escaped 190 → 181` regression before finding that `test_full_mission.gd` seeds from the
  clock deliberately; three full runs gave 190, 181 and 183 on effectively identical code. **The
  number that informed my initial concern was noise, and I am recording that plainly** — anyone
  comparing these totals across runs is measuring the sampler.

## After the block — the post-55 doc review

**No code was touched, by instruction.** Everything here is ledger and plan work, and the two code
defects named below were investigated by reading and left unfixed.

### Two of my own defects surfaced only after this report called the block green

- **`BR55.02` — floor tiles render inside out.** The supervisor found it. It is `BoardView._add_box`,
  which Pass B added and which is **the only hand-wound geometry in the file** — every other box on
  the board is a Godot `BoxMesh`, correct by construction, which is why fifty blocks of parts never
  showed this. On the ticket's own question, whether normals disagree with the winding: **there are
  no normals to disagree.** `_add_quad` calls `surface_add_vertex` and nothing else, and no
  `surface_set_normal` exists in the file. Worse, the doc comment I wrote there asserts the quads are
  "wound counter-clockwise seen from outside" — **the bug written down as if it were true**, which
  will send the next reader elsewhere.
- **A test that measured a colour nothing draws.** `test_grid_line_color_…_ground_color` compared
  grid lines against `WorldPalette.GROUND` after Pass B deleted the quad that was the only thing
  drawn in it.

**Both are the same shape, and it is the shape worth carrying forward.** Pass B's tests assert vertex
*counts* and an *AABB*; geometry in the right place facing the wrong way satisfies every one of them,
and deleting a thing does not fail the tests that measured it — it makes them vacuous. The suite went
green on both and nothing pointed at either. CLAUDE.md's *read the real node back* rule was applied to
**placement** and not to **orientation**, and that gap is mine rather than the rule's.

### The `BR27.01` split was three entries, not four, and the id range was taken

The taskblock-51 spec that ordered the split said four, written from the entry's title; the entry's
own 2026-07-21 breakdown records part (4) as *"the supervisor's own original rephrasing of (1)-(3)
together, not a distinct fourth symptom"*. And `BR27.10`–`BR27.13` already existed in the archive
describing unrelated taskblock-27 bugs, so the split took `BR27.15` onward.

**Investigating the one still-open piece changed what it is.** `BR27.15` is not a broken flow — every
controller-state test on it passes. **Nothing in the view layer reads step-out state at all**, so the
safety-sorted candidate cells and the mouse-wheel cycling are both invisible, and the player is given
nothing between the two clicks the flow requires. It is a missing view affordance, and the two fixes
(draw the mode, or collapse it to one click) differ in kind rather than in size.

### The ledger had lost three entries outright

`BR51.21`–`BR51.23` were filed together and **deleted from `BUGS.md` by a fix commit that never
touched the archive**. Two of them were genuinely fixed and lost their closure markers — one is cited
by id in `detonation.gd`, so the fix names a bug whose entry had gone. The third was never fixed, is
live today, and had been referenced by a *closed* entry as the reason that entry could only be judged
from a different path.

**And `BUGS.md`'s own header taught vocabulary its legend contradicts** — the retired two-word
statuses, and closure gated on `source` rather than `owner`. Since the supervisor may promote any
entry to `SUPERVISOR` ownership, those two can differ, so the stale text would have authorised
closing an owner-gated entry. It is instructional text a future session reads and follows.

### Still open from this block

`BR55.02` is mine and unfixed — the doc review was not the place for it. The winding fix is small; the
comment correction has to ride with it, and a test that reads an outward direction off the built mesh
is what stops it recurring.
