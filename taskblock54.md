# Taskblock 54 — Tiles, gaps, and sections

*Advances `PLAN.md`'s vocabulary item, *The section format*, and the first step of *The generator is
stitching, not carving*. Depends on taskblock-53.*

**The through-line: only parts are real.** A unit walks on a part, a shot hits a part, and anything with
no part behind it is open space — visibly and physically. Everything in this block follows from that,
including the parts that look like losses.

---

# PASS A — `tile` is the walkable part; `cell` is the grid square

**Reserve `tile` for the walkable part itself.** `floor_bulkhead` inside a cell is a *tile*. That gives
walkable parts their own word now that floors, walls, ramps and ladders are all `Part`s and only some of
them are stood on.

**`cell` is the grid square**, which is already the code's word — `Vector2i cell` everywhere. So this
half is a sweep of comments and identifiers that currently use `tile` to mean "cell in the casual
sense," and every one of those is now wrong.

**288 references across `src`, `test` and `tools`** — nearly four times taskblock-40's `void` sweep.
Concentrated in `board_view.gd` (21), `map_gen.gd` (19), `inspect_panel.gd` (12) and
`utility_context.gd` (11), but spread thin over the rest. **Same acceptance as the `void` sweep: a grep
for `tile` returns only walkable-part uses**, comments and doc-comments included.

Three categories, and only the second is mechanical:
- **Means "cell"** → rename. The bulk of them.
- **Means the walkable part** → keep, and it is now the reserved sense.
- **Means neither** (`multi-tile objects`, `tileable`, tilesets in art notes) → judge each; the word is
  doing ordinary English work and may be fine.

**TESTS:** a guard test asserting the sweep is clean, scoped to permit the reserved sense.

---

# PASS B — Delete risers; count what escapes

## B1. Risers go away entirely

`BoardView._build_terrain` currently draws two things: a flat quad per cell at that cell's height, **and
a vertical riser quad** along every edge where orthogonally-adjacent cells differ in height — the
stepped, XCOM-style terrace. The flat quad now has a `Part` behind it. **The riser has nothing behind it
at all**, which is `BR52.03`: a round fired horizontally into a step passes through it and travels on
under the raised floor.

**Stop emitting risers. Do not replace them.** A step is **one part at the height it needs to be**, not a
stack and not a face. The vertical gap between two heights is genuinely open space, and drawing nothing
there is correct: *render is hitbox* (`docs/10`) is **restored** by the deletion, because the drawing and
the geometry now agree by both being absent.

**`BR52.03` closes as `Obsolete`, not `Resolved`** — the code it describes is gone rather than fixed.
`SUPERSEDED.md` records the terrace model's retirement.

**Expect raised floors to read as floating slabs.** Filling a step's side is now **authored content** — a
wall, a strut, a bulkhead placed by a section — not an automatic terrain feature. That will look wrong
before sections exist, and it is not a regression.

## B2. Height stays continuous, and anything standable is standable

A walkable part sits at whatever height it sits at. **A 0.3-high part produced by a collapse is
standable**, and nothing may quantize that away — no level index, no 0.5 grid, no rounding in
walkability. taskblock-37 made height continuous on purpose and this is the pass that could quietly undo
it.

## B3. Escaped projectiles become a measurement

Gaps mean shots can leave the board. **That is legitimate, and it is now worth counting.**

taskblock-52's acceptance — *a shot in a closed room nearly always hits something* — still holds; what
changes is that rooms are not necessarily closed. So **"missed everything and left the map" stops being
a defect and becomes a metric**: how leaky is this map.

- Emit it as its own outcome, distinct from a miss that struck something else.
- The ray chain already knows — it is the chain terminating without a hit.
- **Report it per bout**, alongside the existing work counters. A section that leaks badly is a content
  problem the number will surface long before anyone notices by eye.

**TESTS:** no riser geometry is emitted for any height difference; a horizontal shot into a step passes
through and is counted as escaped rather than silently vanishing; a 0.3-high walkable part is standable
and pathable; escaped count is zero in a sealed room and non-zero in an open one.

---

# PASS C — The section format

**A second format, not the map format used smaller.** A `MapFile` is a complete board. A **section** is a
*fragment*, defined by its **edges** rather than its interior.

- **Edge metadata is the whole reason it is separate.** Where a neighbour may attach, which edges are
  exterior, what a join requires. A `MapFile` has nowhere to put any of that.
- **A legitimate section is a square of empty cells with one exterior wall and no interior walls** — an
  edge piece of a very large room, meaningless alone and only whole once its neighbours exist. **The
  format must accept that**; if it cannot, it is a map format wearing a different name.
- **The attachment grammar is the precedent, one scale up.** Sections joining at compatible edges is
  `attaches_to` semantics against edges instead of sockets, and taskblock-53 proved that grammar holds
  against real content for the first time. **Reuse the reasoning; do not assume the same code fits** —
  an edge is not a socket, and finding out where the analogy breaks is part of this pass.
- Reuse `MapSerializer`'s decisions wherever they hold: parts by id, no runtime state, one open `kind`
  rather than a class per placement, a Resource per placement rather than parallel arrays.

**TESTS:** round-trip equivalence; a section of empty cells with one exterior wall is valid; a section
declaring an edge join that nothing could satisfy is rejected with a readable reason; a malformed file
warns rather than crashing.

---

# PASS D — Author sections, and preview them

**Hand-author two or three sections that are meant to join.** Enough to prove the edge metadata says
something true — at minimum one with an open edge, one that satisfies it, and one that deliberately does
not.

**They must be loadable and previewable from the debug menu, the same way maps are.** taskblock-53 built
`MapCatalog` plus a disk-populated dropdown and `BoutInjector.load_map` resolving a name *or* a path.
Mirror that shape rather than inventing a second one — previewing a section loads it alone on an
otherwise empty board so its geometry and edges can be looked at directly.

**Authored by a script, per convention.** `tools/author_*` is how every authored `.tres` in this project
is produced; the `.tres` is the serialization, the script is where the intent lives.

**TESTS:** every authored section round-trips; the catalog lists them; previewing one produces a board
containing only that section.

---

# PASS E — Prove a join, and nothing more

**As little as possible.** Place two authored sections adjacent, validate the seam, and confirm a unit
can walk from one into the other.

- **Not a generator.** No library selection, no layout algorithm, no whole-board assembly. `MapGen` is
  on its way out and **nothing here should extend it.**
- **The question is only whether the edge metadata is sufficient** to decide that two sections may join
  and to place the second correctly relative to the first. If it is not, that is the block's most
  valuable finding and the format changes before anything is built on it.
- **Navigability still applies.** taskblock-53's asymmetric flood does not care how a board was
  produced; a stitched pair passes it or the join is wrong.

**TESTS:** two compatible sections join and a path exists across the seam; two incompatible sections are
refused with a reason; the joined board passes the navigability invariant; a seeded bout on a stitched
board is reproducible.

---

# Acceptance

- A grep for `tile` returns only walkable-part uses.
- No riser geometry anywhere; `BR52.03` `Obsolete`; escaped projectiles counted and reported.
- A 0.3-high part is standable.
- Sections round-trip, preview from the debug menu, and two of them join.

# Not this block's job

- **The section editor.** `PLAN.md` sequences it after the format; this block authors by hand.
- **The generator rewrite.** Pass E proves a join; it does not assemble a board.
- **Filling the sides of raised floors.** Authored content, and there is nothing to author it into yet.
- **Overwatch.** `BR52.12` and `BR52.15` are getting their own small block.
- **`BR52.10`** (friendly fire). Saved for a dedicated AI block.
