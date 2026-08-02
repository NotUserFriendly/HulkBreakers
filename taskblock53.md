# Taskblock 53 — Ladders, an authored map, and a suite that stops keeping score

*Advances `PLAN.md` NEXT item 3 (multi-level) and *The tile format*. Pass A is unrelated housekeeping,
deliberately placed first so no later pass spends time updating a file meant to go stale.*

**The governing decision, and it reframes `BR46.02`:** climbing parts are the exception, not the rule.
**A map must be fully navigable by a unit with no climbing capability.** Navigability is a property of
the *map*, not of the bots — so the fix is content and generation, not a `CLIMBER` part.

**And stranding is a legitimate outcome, not a failure mode.** Players will be incentivised to knock
enemies off ledges, into holes, and to shoot legs off so a target cannot pursue. **That is the game
working.** What is a defect is a *generator* producing ground with no route out when nobody chose it.
This distinction changes what the tests assert: the no-one-way-ground invariant belongs to map
generation, not to runtime.

---

# PASS A — Disjoint the audit from the game's tests

The suite audit is a tool the supervisor reaches for, not a thing the project runs. Today it is
entangled: `test_per_test_counters_sum_to_the_file_level_profile` gates on the profile's global totals,
so `suite_audit.csv` and `suite_profile.json` must agree — which is why taskblock-52 could not preserve
the CSV's deliberate staleness and had to regenerate it.

**Nothing should depend on it.**

- **Fully separable.** A release build can have the audit removed entirely, and plugging it back in for
  the next audit is a re-add, not a repair. Its own directory, its own entry point, no imports from it
  anywhere in `src/` or the ordinary test tree.
- **Break the coupling.** The sum assertion is the load-bearing check *of the profiler*, so keep it —
  but it must gate the profiler against itself, not against a committed CSV. **The CSV stops being an
  input to any test.**
- **It goes stale by design.** Once disjoint, a stale CSV is the expected state. Say so where it lives;
  `docs/TEST-AUDIT.md` already carries the rule and should carry the mechanism too.
- **`gdlint` and the parse guard still see it** — it must compile, or the first audit after six months
  is a debugging session. Compiling is the only obligation it keeps.

**TESTS:** the ordinary suite passes with the audit directory deleted (**this is the acceptance** —
prove it by removing it, running, and restoring); the profiler's sum assertion still fails when
per-test counters disagree with the file-level totals; no test reads `suite_audit.csv`.

---

# PASS B — The tile format

**Nothing serializes today** — no save, no load, nothing. `Grid` and its surfaces exist only as
generated or hand-built objects.

- **A saved, height-aware map.** Cells, their ordered `Array[Surface]` (part, height, facing), blockers,
  field items, spawn zones.
- **Round-trip is the test.** Save a generated map, load it, and assert the loaded `Grid` is equivalent
  to the original — same surfaces, same heights, same facings, same blockers. **A seeded bout on the
  loaded map resolves identically to the same bout on the generated one.**
- **CC hand-authors the first map** as a `.tres`. There is no editor and this block does not build one;
  the point is a committed, hand-made map with real vertical structure that later work can load instead
  of hunting a seed.
- **A placeholder way to load it.** A debug verb or a crude list is enough — `PLAN.md` sequences the
  real menu after the editors, and a cheesy placeholder is explicitly acceptable.

**Why it earns its place before the multi-level work:** every AI diagnosis for the last eight blocks has
been done by hunting seeds. A hand-authored map turns *"find a seed that reproduces this"* into *"build
the situation."* Doing multi-level first would mean hand-building a GDScript fixture that this pass
throws away.

**TESTS:** round-trip equivalence; a bout on a loaded map is byte-identical to the same bout on the
generated original; a malformed file is rejected with a readable error rather than a crash.

---

# PASS C — The ladder, and the first real test of the attachment grammar

## C1. The grammar exists and has never been used

taskblock-38 Pass A built the placement model: an ordered `Array[Surface]` per cell, each carrying
**part, height and facing**, gated by an attachment grammar with `attaches_to`/`DataValidator`
semantics unchanged from body assembly. Its spec said, in as many words:

> the attachment grammar comes in now, even though nothing authors a catwalk this block — build and
> test the rule now so the model is proven, otherwise the first catwalk discovers the grammar doesn't
> hold.

**Nothing has ever side-attached.** The grammar's only recorded behaviour is *refusing* a second
`GROUND` placement (`map_gen_scratch.gd:7-8` — which is why taskblock-39 had to re-architect carving).
**The ladder is that first catwalk, and this pass finds out whether the grammar holds.** If it does not,
say so plainly; that is a more valuable result than a ladder.

## C2. What a ladder is

**A part with two differently-oriented attachments**, which is the thing the model has not been asked
for yet:

- **Top attaches horizontally** to the upper walkable surface.
- **Bottom attaches vertically** to the lower walkable surface.
- **It attaches to surfaces, not to cells** — the cells follow from where those surfaces are. That
  sidesteps the cell-versus-edge modelling question entirely.
- **Tileable to arbitrary height.** A segment side-attaches to the segment below it, so a run of three
  spans three levels with no new rule.

**`Surface` already carries `facing`**, and `attaches_to` is a flat list of socket types. Whether
orientation needs to become part of the attachment vocabulary — or whether facing plus two attach
points is enough — is the design question this pass answers. **If the attachment model needs an
orientation concept it does not have, that is a `docs/01` change and it should be written there**, not
left implicit in a ladder.

## C3. It is a part, therefore shootable and destructible

**Destructible on purpose.** `is_destructible` became real in taskblock-52; a ladder does not use it.
Cutting a ladder to cut a route is exactly the tactical texture stranding-as-outcome is meant to enable.

**A unit on a destroyed ladder falls**, taking the drop as an ordinary hop-down would — the same
outcome, arrived at involuntarily. Rare, but reachable, and it wants defining rather than defaulting.

## C4. Traversal reuses `ClimbAction`

`ClimbAction.is_legal` already checks adjacency, walkability, and not-a-ramp; its final gate is
`shell.can_climb()`. **A ladder is a second source of legality for an action that already exists** —
`can_climb() or ladder_present`. No new action, no new cost model, one term in `move_cost`.

Ladder traversal should cost more than a ramp. That number is flagged, not designed.

**TESTS:** a ladder side-attaches to a raised surface and the grammar accepts it; a ladder with no
upper surface to attach to is **rejected**; three stacked segments span three levels; a unit with no
`CLIMBER` tag climbs a ladder; the same unit cannot climb a bare face; destroying a ladder mid-climb
drops the unit; `move_cost` prefers a ramp over a ladder at equal distance.

---

# PASS D — The generator owes navigability

**Rise ≤ 2 gets a ramp; anything higher gets a ladder.** A generator rule only — **the editor will
enforce nothing.** An authored map may be broken on purpose; the editor's job later is to *warn*, never
to block.

- **Ramps where they are missing**, per `PLAN.md`: any region whose only exits are descents gets a route
  out.
- **The invariant is `BR46.02`'s own check.** Asymmetric reachability — flood out from a spawn, then
  flood back from every cell reached, and ask whether the spawn is still in the set. It currently fails
  on **16 of 40** generated maps at real bout size; a symmetric check calls all 60 of 60 clean, which is
  why this went unnoticed.
- **`BR46.02` closes as a generation fix**, not a behaviour one.
- **Note for the record:** map generation is due for a full rewrite once a map editor exists. Fix the
  invariant; do not rebuild the generator here.

**Not this pass:** the descent-preference consideration weight. With the generator guaranteeing a route
out, a weight that discourages hop-downs is a *preference* rather than a safety net — and adding it here
would mask whether the generator fix worked. **Land the generator fix, measure, then decide.**

**TESTS:** across a seed sweep, every generated map passes the asymmetric flood; a rise of 2 or less
produces a ramp; a greater rise produces a ladder; an authored map that fails the invariant still loads
(warning, not rejection).

---

# PASS E — The AI can finally go up, and can be interrupted doing it

Two gaps flagged when `ClimbAction`/`HopDownAction` were built in taskblock-37 and never closed:

- **No AI path ever queues either action.** The planner moves exclusively via `MoveAction`, so vertical
  movement has never happened in a real bout. With ladders authored and the generator placing them,
  this is now the difference between a usable map and a decorative one.
- **Neither integrates with `MoveAction`'s mid-move overwatch-trigger hook.** An ordinary move can be
  interrupted mid-flight; a climb cannot. **A unit on a ladder is the most exposed it will ever be** —
  slow, committed, and unable to take cover — so it is the worst possible thing to be uninterruptible.
  "Every real exposure the same" (`docs/09`).

**The authored map from Pass B is the test surface.** A generated map may or may not produce the
geometry that exercises this; an authored one is built to.

**TESTS:** a planner given a target reachable only by ladder queues a `ClimbAction`; an overwatching
unit triggers on a climber mid-climb; the interrupted climb resolves consistently with an interrupted
move (**same rule, not a parallel one**); a seeded bout on the authored map is reproducible.

---

# Acceptance

- The suite passes with the audit directory removed.
- A hand-authored multi-level map round-trips and plays.
- A ladder side-attaches, stacks, and is climbable without `CLIMBER`.
- Every generated map passes the asymmetric flood.
- An AI unit climbs, and can be shot off a ladder.

# Not this block's job

- **A `CLIMBER` part.** Deliberately skipped — maps must work without one.
- **The map editor.** `PLAN.md` sequences it after the format. This block authors by hand.
- **Rewriting map generation.** Fix the invariant only.
- **The descent-preference weight.** See Pass D.
- **`BR52.10`** (friendly fire). Saved for a dedicated AI block.
