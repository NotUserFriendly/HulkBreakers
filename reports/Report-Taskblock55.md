# Taskblock 55 Report — Only parts carry height, and sections learn to declare

All five passes landed in order and the suite is green at **2795 tests**. Pass A came from a prior
session; B–E landed in this one, each committed green.

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

3. **Three Pass E tests passed while proving nothing, and only showed it in their own printed
   output.** The clutter cap was never reached (the fixture tagged clutter `barrel`, which no part
   answers to, so every one was silently skipped); an assembly "reproduced" an empty board twice;
   and a ban test banned a tag the section did not offer. All three now assert the positive case
   first — cap reached, assembly non-empty, banned tag genuinely offered.

4. **Two vocabulary guards caught my own new comments** — the third block running in which this has
   happened. `void` is retired and I had written "every cell is void" (the taskblock's own phrasing)
   in three files; `empty`/`unfloored` is the live word.

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
