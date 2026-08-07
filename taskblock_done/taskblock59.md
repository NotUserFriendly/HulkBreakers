# Taskblock 59 — Finish the editor, and let the tiers into a bout

*Closes `PLAN.md`'s *The editor's Scale tool does not yet author a size*, *The ledge veneer is not
placeable*, and *Author the intelligence tiers onto units*. Depends on taskblock-58.*

**taskblock-60 is bug-sweep prep and taskblock-61 is the sweep.** An unfinished editor presenting as a
pile of bugs would compete with that for attention, so it gets closed here instead of triaged there.

**One class runs through most of this block: something authored a capability and nothing authored the
way in.** `MapPlacement.size` exists, tested, with no gesture that writes it. The ledge veneer exists,
with snap rules and defaults, and cannot be clicked into place. Four intelligence tiers exist with real
gates and no unit is ever anything but `TRAINED`. **In each case the reach is missing, not the thing.**

---

# PASS A — The editor's state corruption

**Two reports are almost certainly one defect**, and it outranks everything else here because it makes
the editor untrustworthy rather than incomplete:

> Clicking a support pillar on top of another support pillar makes an invisible pillar. Other items
> trigger it too. **After that, everything placed was invisible.**

**A failed placement poisoning every later one is state corruption, not a rendering fault.** Find where
a rejected or duplicate placement leaves the view and the model disagreeing, and fix that rather than
the symptom.

**`Delete` removes logically but not visually** is the same disagreement from the other side. Treat both
as one investigation — a model and a view that can disagree about what exists will keep producing
symptoms in whichever direction is exercised next.

**TESTS:** placing a part where one already stands leaves model and view agreeing, whichever way the
placement resolves; a rejected placement does not affect the next one (**assert the second placement
succeeds and is visible, since the poisoning is the real bug**); deleting removes the node as well as
the record; a placement round-trips to a saved map and back with the same visible result.

---

# PASS B — The editor's visible gaps

Smaller, and each is a thing an author reaches for and does not find.

- **No hover ghost over an empty tile.** taskblock-58 built the ghost; it does not appear where there is
  nothing to attach to. An empty cell is where an author most needs to know what a click will do.
- **The parts-list button in UI buttons does not toggle the list.** Wired to nothing, or wired to the
  wrong thing.
- **The select gizmo sits inside items.** Acceptable, but then **it must be clickable and draggable
  there**, and the selected part should render as a **ghost** so the handles are readable through it.
- **Cutout or culling is affecting walls in the editor.** The editor has no unit to cut around, so
  either the cutout should be off in editor modes or it is keying off something stale.
- **Map Thing places only lime-green volumes.** It has no picker, so every claim comes out `Interior`.
  **Give it the same selection the Place tools have** — the claim kinds already exist as a vocabulary.
- **The coordinate readout does not say what is being placed.** It shows the cell and what is under the
  cursor; **add the active thing**, which is the one piece an author needs and cannot infer.
- **Warnings appear when placing `ship_floor`.** Diagnose before silencing: a warning firing on the most
  ordinary placement in the editor is either a real rule being violated or a rule that is wrong.

**TESTS:** a hover over an empty cell produces a ghost; the parts-list button toggles the list; the
gizmo is hit-testable when inside a part; no cutout runs in an editor mode; Map Thing places a claim of
the selected kind; the readout names the active placement; placing `ship_floor` on bare ground produces
no warning, **or the warning is correct and the placement is what changes**.

---

# PASS C — Scale authors a size

`MapPlacement.size` landed with taskblock-58 — tested, serialised, HP scaling with volume, a destroyed
3 x 3 x 0.5 wall leaving a designed hole. **Nothing writes it except a hand-authored `.tres`.**

The gesture already exists too: the **Scale** tool, the gizmo, and face picking all landed. **They are
not connected to the field.**

- **Dragging a face writes `MapPlacement.size`.** Numeric readout while dragging, snapped to 0.1.
- **A top face scales X and Y mirrored**, per the tool's own definition.
- **The authored size round-trips** and the HP follows it.

**This is the taskblock-58 framing finishing its sentence**: map failure should be something an author
shapes, and until this lands an author cannot shape it.

**TESTS:** dragging a face changes `MapPlacement.size` and the readout matches; a resized wall's HP is
proportional to its new volume; the size survives save and load; a top-face drag moves X and Y together.

---

# PASS D — The ledge veneer is placeable

Same shape. The part, the both-ways snap and the defaults all landed; **there is no click that places
one.**

- **Click a ledge's side and it grows down; it can also grow up; if it connects at both ends it snaps to
  both.**
- **Defaults when it connects to nothing:** growing up from an edge, **0.8** — deliberately odd so it
  reads as a default rather than as intent. On the side of a tile with nothing under it, **match the
  picked floor tile's own height.**
- It is a Place Terrain placement, so it uses the struck face like everything else there.

**TESTS:** a click on a ledge side places a veneer that snaps down to what it meets; between two floors
it snaps to both; with nothing above, 0.8; on a tile with nothing under it, the tile's own height.

---

# PASS E — Author the intelligence tiers

`Unit.intelligence_tier` defaults to `TRAINED` and **nothing sets it** — no preset, no matrix, no roster
entry.

**The tiers are not stubs.** The differences are already authored and they are large:

| tier | what it is |
|---|---|
| `MINDLESS` | no memory, no blackboard, and **cannot shoot, take cover or overwatch** — those actions are `GRUNT`+ |
| `GRUNT` | memory and the shoot/cover/overwatch set; no blackboard |
| `TRAINED` | + blackboard, + flank and suppress |
| `ELITE` | + lookahead (`UtilityLookahead.TIERS = ["ELITE"]`) |

**A `MINDLESS` unit is not a `TRAINED` unit with fewer options — it approaches and never fires.** That is
a different bout, not a weaker one.

- **Author it where a unit is authored** — `BotPreset` — so a generated bout has a spread rather than one
  row of the table.
- **Choose the spread deliberately and say why.** It is balance-adjacent, so it wants stating rather than
  inventing; an even split across four tiers is a decision, not a default.

**TESTS:** a preset authors a tier and a generated bout contains more than one; a `MINDLESS` unit never
queues `shoot`, `take_cover` or `overwatch`; a `GRUNT` unit remembers a sighting and does not read the
blackboard; only `ELITE` runs lookahead.

---

# PASS F — Re-measure, and expect it to be worse

**Every completion rate this project has recorded is an all-`TRAINED` rate.** With a spread authored,
take it again.

- **Report per tier and for the mixed bout.** A single number across a mixed roster hides which row
  moved it.
- **An all-`MINDLESS` squad may never complete a mission**, and that is not a failure of this pass — it
  is what a squad that cannot shoot does. **Report it; do not tune it.** If the mixed rate drops below
  the floor, that is a finding about the floor as much as about the AI.
- **`seeds_to_first_win` is the metric**, and it degrades gracefully where a rate does not.

**This is the pass most likely to produce something alarming**, which is why it is in the same block as
the authoring: a measurement taken a block later cannot be attributed to the change that caused it.

**TESTS:** the completion probe reports per tier; the mixed-roster figure is recorded with its spread;
`MIN_COMPLETION_RATE`'s successor is not adjusted in this block.

---

# When to stop and report

- **Pass A's corruption has more than one cause.** Two separate model/view disagreements is a different
  block from one.
- **The `ship_floor` warning is correct.** Then the placement rule is wrong and that is a design
  question, not a fix.
- **Pass F's mixed rate falls below the floor.** Report it with the per-tier breakdown; do not tune the
  spread to make the number acceptable.

# Acceptance

- A rejected placement does not affect the next one, and the editor's model and view never disagree
  about what exists.
- Dragging a face writes a size; the veneer places from a click.
- A generated bout contains more than one intelligence tier.
- Completion is reported per tier, with the mixed figure, untuned.

# Not this block's job

- **The ramp findings**, including auto-placed terrain placing ramps. `PLAN.md`'s *Retire ramps* deletes
  the subsystem; fixing a ramp first is the expensive order.
- **`BR56.01`**, for the same reason.
- **Elevated tile borders.** Its own NEXT item and a rendering judgement.
- **`is_room` adjacency.** Needs the generator.
- **The pacer's candidate budget.** Its own item.
- **Animation.** Recorded, and its prerequisites are not on the list yet.
