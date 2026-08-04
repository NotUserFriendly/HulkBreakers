# Taskblock 56 — One view of modules, and an editor that proves it

*Closes `PLAN.md`'s *One view, toggleable modules*, *Seeing what you authored*, *Map and section
editors*, and `BR55.02`. Answers the live half of *Two aim questions*.*

**A long, mostly-unattended block.** The supervisor is away, so every decision below is either settled
here or explicitly CC's to make and flag. **Where a fork is genuinely open, pick the reversible option,
record it in the report, and keep going** — do not stall.

**The editor is the collapse's proof, which is why they are one block.** A section is a small map; the
map editor and the section editor differ by two buttons and one panel. If the module system is right,
a whole new surface costs almost no view code. If it is wrong, the editor becomes a sixth overlay
subclass and everyone can see it.

**Push everything into logic.** `BuilderController` is the precedent — 161 lines of pure headless
controller against 305 lines of scene that *only reads it and draws*, with its own header calling the
builder "the best test the assembler will ever get." **Do that again.** Placement, claims, edges,
validation, save and load are all headless and all testable; only drawing is not.

---

# PASS A — `BR55.02`: tile geometry is wound inside out

Already diagnosed: it is `_add_box`, and there are no normals to disagree with the winding. A single
tweak.

**Do not fix it by disabling backface culling** — that hides it, doubles fragment cost per tile, and
leaves the geometry wrong for the wall-cutout shader.

**TESTS:** the emitted winding is consistent with every other box the project builds (assert on the
vertex order, not on a render).

---

# PASS B — Answer the aim question, in writing

**Where does a shot actually aim — the dartboard point on the target, or the target's centre? And does
the answer differ between player control and AI control?**

`docs/02` says the shot resolves from the shooter's real angle, so both paths should agree. **If they
do not, that is a second aiming implementation** and the no-parallel-systems rule applies.

- Trace both paths from origin to the resolver's input and **write the answer into `docs/02`**, whatever
  it is.
- **This bears on `BR51.01`** (AI rounds up to 43° off facing, chaingun units within 8.6° and everything
  else drifting). *They agree* removes a suspect; *they differ* is a strong lead.
- **An investigation, not a fix.** If it turns up the cause of `BR51.01`, append to that entry and stop
  — do not fix it here.

**TESTS:** if the two paths agree, a test asserting they agree, so a later change cannot silently
separate them.

---

# PASS C — Extract the modules

`SquadControlOverlay` is **942 lines**, `SpectatorOverlay` **718**, and they duplicate each other
because Spectator cannot inherit Squad without dragging in `TacticsController` and the whole unit-input
path. `SingleUnitOverlay` is 54 lines because inheritance *was* available to it. **Inheritance forced
the fork.**

**The precedent already exists and works.** `CombatLogPanel` is a `VBoxContainer` both overlays
instantiate. It has never joined the hierarchy and never needed to.

Pull the shared surface out as modules on that pattern: board, camera controls, inspect, combat log,
stat panels, action bar, queue panel, turn controls, perf panel, debug panel.

**Two axes, not one.** A module is a **display** module or an **input** module, and they toggle
independently — that separation is exactly what `SpectatorOverlay` needed and could not get from
inheritance. Spectator is *all display, no unit input*; that must be expressible as a module set rather
than as a subclass.

**Extract, do not rewrite.** A module's behaviour is whatever the overlay did; this pass moves code and
changes nothing. **Any behaviour change found necessary is a finding to report, not a fix to make.**

**TESTS:** each extracted module has the coverage its overlay had; a module can be instantiated with no
overlay at all (**this is the acceptance** — if a module needs its parent, it is not a module).

---

# PASS D — One view; modes declare module sets

`ControlOverlay` becomes the one view. A **mode** is a declaration of which modules are on — data, not
a subclass.

| today | becomes |
|---|---|
| `SpectatorOverlay` (718) | a mode: display modules, no unit input |
| `SquadControlOverlay` (942) | a mode: display + full unit input |
| `SingleUnitOverlay` (54) | a mode: the above, scoped to one unit |
| `GenerateBoutOverlay` (373) | a mode: board + builder panel |

**Modes are data.** Adding one should be a table entry, not a file. That is the property Pass F tests.

- **Behaviour is preserved exactly.** Every mode does what its overlay did. A difference found is a
  finding, not licence.
- **The view tests will move**, and that is expected work rather than a surprise. Migrate them; do not
  delete them. **Report the count moved and the count deleted separately** — they are different claims.
- **`BR27.04`, `BR32.09` and `BR35.02` are deferred to this refactor** (lighting differs between views;
  spectator's indicator jumps early; spectator tile-inspect resolves to a hidden cell). **Check each
  after the collapse.** Some should evaporate — a divergence between two implementations of one panel
  cannot survive there being one panel. **Do not close them**; they are `SUPERVISOR`-owned. Mark
  `Pending` with what changed.

**TESTS:** each mode composes the module set it declares; a mode with no input modules cannot mutate
state through the view (**assert it, since that is Spectator's whole contract**); a seeded bout renders
identically before and after per mode, by the module set it produces rather than by pixels.

---

# PASS E — The three view gaps, as modules

All three are `PLAN.md`'s *Seeing what you authored*, and all three are now module work.

- **Floor tiles go dark forest green** while there are no models. They share a material with walls and
  units, so a board reads as one mass. Temporary; revert when tiles have their own look.
- **Loading frames what it built.** A section or map load leaves the camera wherever the last bout left
  it. Point it at the new content's bounds. `CameraRig` already solves framing for a set of bodies —
  same solve, different input.
- **Claim volumes get drawn** — a translucent box per claim, **only in an authoring or preview context,
  never in play.** This is a display module that the editor mode turns on and no play mode does.

  | claim | colour |
  |---|---|
  | Exterior | red |
  | Interior | **vibrant lime** green |
  | Empty | blue |
  | Entry | orange |

  **The two greens are deliberately far apart** — dark forest floor, vibrant lime claim — so a claim
  reads against the floor it sits on. Keep that separation if either is retuned.

**A claim is invisible today**, so the only way to know a section declares one is to read its `.tres`.
That is the one thing an editor cannot work around, which is why this pass precedes it.

**TESTS:** the claim module draws one box per claim with the right colour and extent (assert the boxes,
not the render); no play mode instantiates it; framing on load produces a camera whose solved bounds
contain every placed part.

---

# PASS F — The editor

**One editor, two save buttons.** A section is a small map. The map editor and the section editor are
the same surface; **everything section-specific lives in one module** — claims, edges, per-cell chance,
whole-section fields.

**This is the collapse's proof.** The editor mode should be a module set plus one new authoring module.
**If it is not — if it needs to subclass, or reach into another mode, or duplicate a panel — say so
plainly in the report.** That is the block's most valuable possible finding and it must not be quietly
worked around.

## F1. `EditorController`, pure and headless

Follow `BuilderController` exactly: a `RefCounted` in `src/logic/` holding the whole editing model, with
the scene reading it and drawing. Place and remove parts, set heights, add and resize claim volumes,
author edges, set per-cell chances and whole-section fields, undo.

**Everything here is headless-testable and must be tested that way.** The scene gets no logic.

## F2. Save as map, save as section

- **Save as map** → `MapFile` through `MapSerializer`.
- **Save as section** → `SectionFile` through `SectionSerializer`, carrying claims, edges and the
  authoring vocabulary.
- **A map saved and reloaded is the map that was authored.** Round-trip is the test, as it was for both
  formats.

## F3. Run a test bout on it

**The half that matters.** An editor that cannot launch what it authored is a file format with a GUI.
Hand the authored board to the existing bout path — `BoutInjector.load_map` and the bout builder — never
a second route into combat.

## F4. Warn, never block

An authored board that fails the navigability invariant **still loads**. Authoring a deliberately broken
board is legitimate; the editor says so and does not refuse. **Same for every validation**: a claim
conflict, an entry connecting to nothing, a section edge nothing could satisfy. **Warnings are a list
the author reads, not a gate.**

**TESTS:** every `EditorController` operation is tested with no scene; a round-tripped map is
equivalent; a board that fails navigability loads and reports; an authored board launches a bout through
the same path a generated one does; undo restores the prior state exactly.

---

# When to stop and report

The supervisor is away. **Stop and write it up rather than pushing through, if:**

- **Pass C finds a module that cannot stand alone.** That is the collapse failing its own premise and it
  changes the rest of the block.
- **Pass D cannot preserve a mode's behaviour** without a change nobody asked for.
- **Pass F needs a subclass.** Report it; do not build the sixth overlay.
- **A deferred bug (`BR27.04`, `BR32.09`, `BR35.02`) gets worse rather than better.** The refactor was
  supposed to dissolve them.

Otherwise: pick the reversible option, flag it, keep going.

# Acceptance

- `SquadControlOverlay` and `SpectatorOverlay` no longer exist as 942- and 718-line subclasses.
- A mode is a declaration; adding one is a table entry.
- The editor is a module set plus one authoring module, and **the report says outright whether that
  held**.
- `EditorController` is headless and fully covered with no scene.
- An authored board round-trips and launches a bout.
- Tile winding is correct; the aim question is answered in `docs/02`.

# Not this block's job

- **Fixing `BR51.01`.** Pass B may find its cause; appending is the deliverable.
- **The debug-menu overhaul.** Already a module in that system; the rest needs the supervisor watching.
- **`BR52.10`** (friendly fire) — AI work, its own block.
- **The generator.** The editor authors sections; stitching a board from a library is a later item.
- **Closing `SUPERVISOR`-owned entries.** Mark `Pending` with what changed.
