# Taskblock 55 — Only parts carry height, and sections learn to declare

*Advances `PLAN.md`'s *Cells stop carrying height*, *The section authoring vocabulary*, and the
stacking half of *The section format*. Depends on taskblock-54.*

**A doc review follows this block, so it does not split across one.** Everything the section editor will
need to author lands here, exercised by hand-written `.tres` and a seeded preview — the editor itself
comes after the review.

**Vocabulary, because it will get mixed up:** a **tile** is a walkable part inside a cell. A **cell** is
a grid square. A **section** is an authored fragment that the generator will stitch. The last one has
been called "tiles" informally for a long time; it is not one.

---

# PASS A — Re-sweep `void` and `HULK` with a real word boundary

taskblock-54 found that `\\btiles?\\b` **treats `_` as a word boundary**, so
`test_..._extraction_tiles` and `EXTRACTION_TILE_HEIGHT` passed a guard scanning for exactly that word.

**Both earlier sweeps used the same pattern.** Re-run taskblock-40's `void` guard and taskblock-50's
`HULK` guard with the non-letter boundary taskblock-54 adopted, and clean whatever tail they were
missing.

That boundary also gets every genuine substring right for free — `hostile`, `projectile`, `versatile`,
`avoid`, `devoid` — so the allowlists should shrink rather than grow.

**TESTS:** all three guards use one shared boundary helper (**one implementation, not three that drift
apart**); each still passes for its own reserved sense.

---

# PASS B — Cells stop carrying height; tiles carry it

taskblock-54 deleted risers, but **the per-cell ground quad still moves with the cell's height** —
`board_view.gd:526` and `:870` both offset by `_height_for(cell)`. A cell is still a thing with an
elevation, drawn at that elevation, with **nothing behind it**. Same defect the risers had, one
primitive down.

- **Every cell is void.** The grid stops expressing height — one flat plane, or nothing.
- **Height lives on the tile.** A walkable part sits at the height it occupies, and that part is the
  only thing at that elevation and the only thing a shot or a foot can find.
- **Author temporary floor tile parts** to stand in until sections carry real ones. Real geometry,
  hittable, placed at the right height. **The thing you see is the thing that is there.**
- **A 0.3-high tile is standable and hittable**, and nothing here may quantize that away. taskblock-37
  made height continuous deliberately and this is the pass that could quietly undo it.

**Expect the board to look sparser before it looks better**, exactly as the riser deletion did. Floating
slabs are accepted for now — filling a step's side is authored content.

**TESTS:** no cell geometry varies with height; a tile at 0.3 is standable, pathable, and struck by a
ray aimed at it; the escape counter from taskblock-54 does not change on a flat board (**the sweep must
not open new holes in a board that had none**).

---

# PASS C — The section authoring vocabulary

A second class of section data: **declarations consumed at assembly and never present in an assembled
map.** A placed board has a barrel or it does not; it has no "40% chance of a barrel."

**This is where a section stops being a small map.** `SectionSerializer` delegates placement to
`MapSerializer` on the reasoning that a previewed section genuinely is a tiny map. That holds for
placements and stops holding here — **expect the delegation to become partial**, with this vocabulary
owned by the section format alone.

## C1. Claims are volumes, not cell flags

**A claim is a 3D shape and its extent *is* its declaration** — a translucent box, resizable in the
editor, overlapping freely with anything, drawn only while authoring and never present in an assembled
board. That dissolves the whole-column-versus-interval question entirely: the shape is the interval.

**Same geometry, not the same resource type.** A claim has no HP, no material, no sockets, and must
never reach a part picker, loot or a shot plane. A resource carrying a box extent plus a `kind` — **not
a `Part`**, which would inherit everything it must not have.

**Four verbs, all rules about co-occupancy:**

| | says |
|---|---|
| **Empty** | nothing may co-occupy — **forbid** |
| **Interior** / **Exterior** | whatever co-occupies must be inside / outside the hulk — **require** |
| **Entry** | an opening may exist here; overlapping entries **intersect** — **negotiate** |
| **Merge** | identical content may co-occupy and collapses to one — **permit and unify** |

Empty conflicts with any neighbour placement in its volume; Interior conflicts specifically with a
neighbour asserting Exterior in the same one.

**Clutter and Spawner stay per cell**, with a per-cell chance. They name a *place something may appear*
rather than a volume of space. Tags are open `StringName` — `barrel`, `logistic`, `machine` today.

## C2. Entry is permission; doors are content placed inside it

**Only entry is negotiated.** An entry volume says *an opening may exist here*; a door says *an opening
does exist here, this size*. Two sections resolve their entries **by intersection** — the shared opening
is the region both permit — and doors fill what is left.

A big entry meeting a small one yields the small one because that is what the intersection **is**. No
comparison, no ranking, just geometry.

- **A door auto-declares an entry volume over its own face, and that volume is adjustable.** Expand it
  and a neighbour's larger door may overwrite yours; leave it at face size and only a fitting door can
  join. **Adjust the door's own claim; never add a second entry volume beside it.**
- **A door whose entry volume is deleted is furniture** — not a join point, not overwritable.
- **An entry connecting to nothing becomes a wall.** Otherwise doors overwrite paintings and open into
  the back of an oven.
- **Walls beside a door force a small-to-small connection** — denial by geometry, not metadata.
- **Where two entries must still be ranked, rank by face area.** 5-tall x 1-wide beats 2x2; thickness is
  meaningless for an opening.

## C2b. Merge

**Two enclosed rooms side by side share one wall, not two.** Same type, one part — which is also how
flush-mounted entries mesh, since the walls they sit in overlap.

- **Unification, not deduplication.** Two 0.2-thick walls merge to **0.2**, not 0.4. One part, and
  damage, destruction and shot resolution all see one thing.
- **It is the deliberate exception to Pass D's interval rule.** A merge volume is exactly where vertical
  overlap is legal — **the stacking check must know that or it will refuse every shared wall.**
- **Merge applies to floors too**, for the same reason.
- **Differing types refuse the join, with a reason.** A silently doubled wall is the invisible defect
  this system exists to prevent.

## C3. Whole-section declarations

- **Maximum spawned clutter items**, and a **banned clutter list**.
- **`minimum_garrison`** — if the roll produces fewer than this, the section spawns **none**. A cavernous
  room never contains one lonely guard. All-or-nothing, not a minimum topped up.
- **`maximum_garrison`** — its foil.
- **Encounter types** — a whitelist. **The encounter system does not exist**; the field is recorded now
  so authored sections need not be revisited. Author it, validate it, consume it nowhere.
- **Is this section a room on its own, or part of a larger one?** **The load-bearing one.** Encounters
  roll **per room**, and a room may be several sections, so crossing an invisible seam inside one large
  room must not trigger anything. It is the same distinction that makes an edge piece legal: a square of
  empty cells with one exterior wall is explicitly *not* a room.

**TESTS:** an Interior claim overlapping a neighbour's Exterior claim is refused and the reason names
both; Empty refuses any neighbour placement in its volume; two entry volumes resolve to their
intersection; an entry connecting to nothing becomes a wall; a door with no entry volume is never
overwritten; two same-type walls merge to one part at the original thickness (**assert the thickness —
0.4 is the failure**); two different-type walls refuse with a reason; a merged floor is one part; a
garrison roll below `minimum_garrison` spawns nothing rather than a reduced number; a multi-section room
rolls one encounter, not one per section.

---

# PASS D — Sections stack: intervals, and `up`/`down` edges

**A section must be able to sit above or below another** — an observation room on top of a staircase, a
barracks at the bottom, and a second tall room refused because it needs space the staircase occupies.

**Claim volumes already carry this** — a claim's box *is* its vertical extent, so stacking asks whether
two sections' claimed volumes intersect. **Except where a Merge volume says overlap is legal**, which is
the shared-wall case and must be honoured here or every adjacent pair of rooms is refused.

**Do not introduce voxels.** taskblock-37 made height continuous on purpose and the collapse case
reaffirmed it. A voxel grid quantizes to its resolution — 0.5 voxels cannot express a 0.3 step, and 0.1
voxels are twenty mostly-empty layers per cell. **Intervals keep height continuous and cost one
comparison.**

**`up` and `down` are data, not code.** `SectionFile.edge_for(side)` already takes an open `StringName`
— *"sides are a closed set of four in practice"*.

Two things that follow:

- **Entry cells need a height.** A door at ground level and a door at the top of a staircase are
  different joins.
- **The whole-column question is already answered** — a claim is a box, so its extent says exactly what
  it claims. Nothing extra to declare.

**TESTS:** two sections with disjoint intervals share a cell; overlapping intervals are refused with
both intervals named; a section joins another through its `up` edge; an entry at height 3 does not match
an entry at height 0; `can_join` still reads both edges with neither as host (taskblock-54's finding
holds vertically too).

---

# PASS E — Demo sections, and a preview that rolls

**Hand-author sections that exercise the vocabulary**, not just the format. Between them they should
cover: clutter and spawner cells with chances, a garrison floor that can fail, an Empty claim a
neighbour wants, an Interior/Exterior conflict, an entry that connects and one that does not, **a small
door with an expanded entry claim that a larger door overwrites**, **two rooms whose walls merge**, a
stacked pair, and a section that is explicitly *not* a room on its own.

**Give them meaningful names.** taskblock-54's `east_hall` and `west_hall` are identical and the names
say nothing — fine as format fixtures, useless as vocabulary fixtures. A name should say what the
section is *for*, since these will be read far more often than they are run.

**Preview takes a seed and rolls the declarations.** Reloading with a different seed produces a
different example of the same section; reloading with the same seed reproduces it exactly. **That makes
the preview the determinism test as well as the authoring tool.** Loading an assembled map populates
every section's declarations the same way.

**Every roll draws from the seeded RNG in a stable iteration order** — the iteration is over a
dictionary of cells, which is where this gets got wrong.

**TESTS:** the same seed previews identically twice; different seeds differ; a preview contains only
things the section's declarations permit; a banned clutter item never appears; the clutter cap holds;
an assembled two-section map rolls both sections' declarations.

---

# Acceptance

- `void`, `HULK` and `tile` guards share one boundary and are clean.
- No cell geometry varies with height; a 0.3 tile is standable and hittable.
- The vocabulary round-trips, validates, and is exercised by named demo sections.
- Two sections stack at one cell; overlapping intervals refuse.
- The same seed previews the same section twice.

# Not this block's job

- **The section editor.** After the doc review.
- **The generator.** taskblock-54 proved a seam; assembling a board is a later item and `MapGen` is on
  its way out regardless.
- **Filling the sides of raised floors.** Authored content; floating slabs are accepted for now.
- **The encounter system.** Pass C authors a whitelist that nothing consumes.
- **The debug menu overhaul** — plain-language submenu descriptions and the rest. Its own pass, later.
- **Overwatch** (`BR52.12`, `BR52.15`) and **friendly fire** (`BR52.10`). Their own blocks.
