# Taskblock 58 — Faces, locations, one answerer, and the editor's real tools

*Advances `PLAN.md`'s *The editor's tool set*, *Sight-blocking is geometry*, *Floors reference a
location*, and *Parts get real dimensions*. Depends on taskblock-57.*

**Three prerequisites and then the editor.** A, B and C exist because building the tools on top of the
current foundations would mean building a second system in each case — a second notion of where a thing
is, a second thing that reports a face, a third thing that answers whether A can see B.

**Grid agnosticism is not a prerequisite and is not built here.** What the editor needs is B; plural
grids are a later item. **The one rule this block owes it:** ask a grid, never compute adjacency from
coordinates inline. `src/` has two inline sites against thirty-one accessor calls — **the editor
inherits that discipline by using the same accessors, and must not be the third site.**

**Do not validate against the skewed-ship case.** Build as though it will exist; testing against a
system that does not is how wrong information gets recorded as a measurement.

---

# PASS A — Stop discarding the face

**The face is already computed.** `RayCaster` returns `hit.normal` and `hit.exit_normal`, and
`UnitPicker`'s inner slab test returns `{t, normal, inside}` where the normal is *"the struck face's
real world normal."* **`PartPicker.hit` then drops it**, returning `{unit, part, cell, t}`.

Only `RayChain` reads a normal today, to reflect deflections.

- **Widen `PartPicker.hit` to carry the normal through**, and thread it to whatever the editor picks
  with. **Nothing new is computed** — this is a value that already exists reaching a caller that needs
  it.
- **Two systems cannot diverge here** because there has only ever been one computation. That is the
  reason this is Pass A rather than part of the editor work.

**TESTS:** a pick against a box's top face reports the up normal and a side pick reports that side's;
the normal a pick reports equals the one `RayCaster` reports for the same ray (**assert the agreement,
since one computation is the whole claim**); a miss reports no normal rather than a zero vector that
reads as one.

---

# PASS B — A placement has a position; a cell does not own it

**Today a cell owns its surfaces** — `Grid.surfaces` is `Dictionary[Vector2i, Array[Surface]]`, so a
floor's position is its dictionary *key*. Moving one means delete-and-re-add, and a floor cannot exist
except as something a cell holds.

**Invert it: a placement carries a position, and the cell lookup becomes an index.**

**This is cheap, and the reason is that the accessor already exists.** `Grid.surfaces_at(cell)` and
`add_surface()` are the interface. **Only five places touch the dictionary directly**, and all five
iterate *"every cell that has surfaces"* rather than looking one up — `camera_framing_module`,
`board_view` (twice), `ray_caster`, and `Grid.dup`. So the storage changes behind `surfaces_at()`, those
five get a `placements()` to walk, and **every other reader is untouched.**

**`GROUND` is the one rule that genuinely changes.** `ship_floor.attaches_to = ["GROUND"]` means *the
cell*, and `GridPlacement.can_place` refuses a second `GROUND` part per cell — the rule taskblock-39
re-architected `MapGenScratch` around. With no cell to attach to, `GROUND` becomes either *attaches to
nothing, held up by neighbours* or retires in favour of a support requirement. **Pick one and write it
down**; do not leave it implied by whatever the code happens to do.

**Not in this pass:** the support graph, weight, cantilever, gravity conduction. This is the inversion
only — the thing those need in order to be possible.

**TESTS:** `surfaces_at(cell)` returns what it returned before for every authored map (**round-trip an
existing map and compare, since this is a storage change with no intended behaviour change**); moving a
placement updates the index and leaves no stale entry; the five iterators walk the same set they did;
a seeded bout on `proving_ground` is byte-identical before and after.

---

# PASS C — One thing answers "can A see B"

**Three things answer it today**, which is the no-parallel-systems rule broken in the open:

| | how |
|---|---|
| `LoS.has_los` | walks `Grid.line` reading `Grid.opacity`, **a flat per-cell float array** |
| `VisibilityField` | bitboards from a shadowcast — **which reads that same array**, and records its own limit: *occlusion data here is 2D, per cell, with no per-level* |
| `RayCaster` | marches real 3D geometry |

**Geometry already knows what blocks. Make it the only answerer.**

- **Every 3D volume blocks sight** because it is a volume, not because a cell was flagged. **`Grid.opacity`
  retires**, and with it the editor's `sight_blocking` tool.
- **Height comes for free.** A 1.0 wall stops blocking sight to a unit standing at 3.0 — which it does
  today only because the array has no height.
- **`DamageResolver` stops clearing a flag** when a wall dies (`:567`). Destroying the geometry *is*
  clearing it.
- **Gases and windows become the exception**, arriving later as volumes with a transmission property.
  **Opaque by default, transparent by declaration** — the right direction for the exception to run.

## C1. Cover reads the field; it does not walk its own line

**Six places call `LoS.has_los` directly** — `cover`, `overwatch`, `attack_action`, `burst_action`,
`world_view`, `cell_inspection`. **One is hot:** `Cover.is_covered_from` calls it **per candidate cell**,
inside the scoring loop taskblock-43 measured at 98.3 ms.

**That call is itself a duplicate** — the field already computed the answer for that target this turn.
So cover reading the field is the correctness fix *and* the cost mitigation, and it arrives with this
pass rather than after it.

**Field construction is once per target per turn either way**, so its per-cell cost rising is affordable.
**Per-query cost must stay a bit test.** Report both numbers.

**Not in this pass: `Cover.is_covered_from`'s own flatness.** It takes two `Vector2i` and has no height
in it. Reading a 3D field fixes *what it sees*; making cover directional in three dimensions is
`PLAN.md`'s own item and belongs with the multi-grid work.

**TESTS:** a 1.0 wall does not block sight to a unit at 3.0, and a 3.0 wall does (**the case the array
could not express**); destroying a wall restores sight with nothing clearing a flag; cover's answer
matches the field's for the same pair; a seeded bout is byte-identical where geometry and the old array
agreed; field build cost and per-query cost both reported.

---

# PASS D — Seven tools

Ten become seven, grouped by what a click *means* rather than what it touches.

| tool | a click |
|---|---|
| **Select** | Inspect on click; move with the gizmo. **X and Y snap to one-tile increments and auto-connect to the new neighbours** |
| **Place Terrain** | Walls, floors, anything tagged terrain. **Attaches to the struck face** (Pass A), with a **ghost** so the result is never a surprise |
| **Scale** | Anything scaleable. The gizmo attaches to the **face clicked**; a top face scales X and Y **mirrored**. Numeric readout while dragging |
| **Delete** | Highlights on hover, deletes on click. Map things, tiles, parts — everything |
| **Place Map Thing** | Claims, extract zones, spawn tiles, later scripted tiles. **Everything the player never sees** |
| **Place Big Part** | Cover and cover spawners — anything that stops a unit entering a cell without being terrain |
| **Place Part** | Everything else |

**Retiring as verbs:** `spawn_a`/`spawn_b`/`spawn_none` and `chance` fold into *Place Map Thing*;
`sight_blocking` retires with Pass C.

**A chance becomes a thing you place**, not a verb — a generic *this could be any cover* item with
defaults, and selecting it lets you change them: which categories, what chance.

**Keep the generated-from-vocabulary property.** `EditorModule.TOOLS` drives the buttons today and an
eighth verb gets one for free. Do not replace that with a hand-written list while reorganising it.

**TESTS:** every tool in the vocabulary has a button; a chance placed as a thing round-trips with its
categories and value; no tool named `sight_blocking` survives; the retired spawn verbs are reachable
through *Place Map Thing* and set the same markers.

---

# PASS E — The parts list, and placing by face

**Every Place tool opens a parts list on the right, in the Inspect slot**, toggleable from UI buttons.

**It goes where Inspect goes because while placing you cannot be selecting.** The two are mutually
exclusive by construction, so sharing a slot is correct rather than a compromise — say so where the
slot is declared, or someone will later read it as a collision.

**Placing attaches to the struck face**, using Pass A's normal:

- **A ghost of the result before the click.** The pass's real acceptance is that **what appears is what
  the ghost showed** — a placement that surprises is the defect this exists to prevent.
- **Faces define connections**, which is what a grid-agnostic world will need anyway: once positions are
  their own and grids are plural, a face is the only thing two placements can agree about.

**TESTS:** the ghost's transform equals the placement's; aiming at a top face places above and a side
face places beside; the list is searchable and offers every part the active tool permits; the list and
Inspect never mount together.

---

# PASS F — Real dimensions, and HP by volume

- **Walls resize on X, Y and Z.** A 3 x 3 x 0.5 wall is **one part**, and destroying it leaves a hole of
  a designed size. **Map failure becomes something an author shapes** rather than something that emerges
  a cell at a time.
- **HP scales by volume.** The alternative is three walls pretending to be one, and this keeps a big wall
  tougher than a small one without a number authored per size.
- **Support pillar upgrades from cover to a terrain part**, since it holds things up.

## The ledge veneer

A flat wall attaching to a tile's top edge, and sideways to tiles above it. **Name is provisional — say
so in the report if a better one turns up while building it.**

- **It grows both ways and snaps to what it meets.** Clicking a ledge's side grows it **down**; it can
  also grow **up**; **if it connects at both ends it snaps to both.**
- **Defaults when it connects to nothing:** growing up from an edge, **0.8** — deliberately odd so it
  reads as a default rather than as intent. Clicking the side of a tile with nothing under it, **match
  the picked floor tile's own height**.
- **HP by volume**, like everything above.

**TESTS:** a resized wall's HP is proportional to its volume; a 3x3x0.5 wall destroyed leaves a hole of
its own size; a veneer between two floors snaps to both; a veneer with nothing above it is 0.8; a veneer
on a tile with nothing under it matches that tile's height.

---

# When to stop and report

- **Pass B changes behaviour anywhere.** It is a storage inversion with no intended behavioural effect;
  a difference is a finding.
- **Pass C's per-query cost stops being a bit test.** The field exists to keep it one.
- **`GROUND`'s replacement is not obvious.** Pick the reversible option, flag it, keep going — but say
  which and why.
- **A tool cannot be generated from the vocabulary.** That property is worth more than any individual
  tool.

# Acceptance

- A pick reports the struck face, and it is the same face `RayCaster` reports.
- `surfaces_at()` behaves identically while a placement owns its position.
- `Grid.opacity` is gone; a 1.0 wall does not hide a unit at 3.0.
- Seven tools, all generated from the vocabulary.
- What the ghost showed is what gets placed.
- A wall's HP follows its volume.

# Not this block's job

- **Plural grids, portals, rotations.** Later. Add no inline cell arithmetic.
- **The support graph, weight, cantilever, gravity.** Pass B makes them possible; none is built.
- **Cover becoming directional in 3D.** Pass C fixes what cover *sees*; the flatness is its own item.
- **The skewed-ship case.** Build as though it will exist; validate nothing against it.
- **`BR56.01`** — a facing bug in the ramp subsystem a NEXT item deletes.
